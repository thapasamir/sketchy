defmodule Backend.RateLimit do
  @moduledoc """
  Limits how often one source (an IP address, a username, ...) may do one kind of thing.

  Each limit is a *policy*: a name, a count and a window ("60 guests per 10 minutes"). A source
  that goes over the count is refused until the window ends. The counts live in memory (ETS) on
  this server, which is right for one server; with several they would need to be shared.

  Policies and their numbers are in `@policies` below. Two settings, for operators and for tests:

    * `config :backend, :rate_limits, enabled: false` turns every limit off.
    * `config :backend, :rate_limits, scale: 0.1` multiplies every count (never below 1), to be
      stricter (or looser) everywhere at once. Both can be set with the `RATE_LIMITS` (`off`) and
      `RATE_LIMIT_SCALE` environment variables (see config/runtime.exs).

  The counting is a fixed window: a window is a slice of the clock, and a source's count restarts
  at zero in each slice. Simple and cheap; the cost is that a source can use up one window's allowance
  right at its end and another right at the start of the next.
  """

  use GenServer

  require Logger

  @table __MODULE__
  @sweep_every_ms 60_000

  # name => {how many, per how many ms}. "ip" policies are counted per address (see ClientIP).
  @policies %{
    # --- accounts ---
    # a school or a household shares one address, so these are generous per person...
    guest: {60, 600_000},
    # ...and the same kind of thing across everybody, to stop many addresses together
    guest_all: {1_500, 600_000},
    # hashing a password is slow on purpose, so each attempt costs real CPU
    register: {10, 3_600_000},
    register_all: {300, 3_600_000},
    login: {30, 600_000},
    # per username, so guessing one account's password from many addresses is slow too
    login_user: {10, 900_000},
    # --- rooms ---
    room_create: {20, 600_000},
    room_join: {60, 300_000},
    # joining a room that doesn't exist: the sign of someone guessing codes (about 330,000 of them)
    room_miss: {15, 300_000},
    # --- the operator's stats page: wrong passwords are counted (see AdminController) ---
    admin_miss: {10, 600_000},
    # --- the rest of the API, as a ceiling over everything above ---
    api: {300, 60_000},
    # --- the live connection ---
    socket_connect: {30, 60_000},
    channel_join: {30, 60_000}
  }

  # --- the API ---

  @doc """
  Count one more `policy` event for `subject`. Returns `:ok`, or `{:error, retry_after_ms}` when
  `subject` is over the policy's count for this window.
  """
  def hit(policy, subject, now \\ now_ms()) do
    if enabled?() do
      {limit, window_ms} = policy!(policy)
      window = div(now, window_ms)
      expires = (window + 1) * window_ms
      key = {policy, subject, window}
      count = :ets.update_counter(@table, key, {2, 1}, {key, 0, expires})

      cond do
        count <= limit ->
          :ok

        true ->
          # say so once per window, not once per refused request (a flood must not fill the log)
          if count == limit + 1,
            do:
              Logger.warning(
                "Rate limit: #{policy} over #{limit} per #{div(window_ms, 1000)}s for #{inspect(subject)}"
              )

          {:error, expires - now}
      end
    else
      :ok
    end
  end

  @doc "Is `subject` already over `policy` for this window? Doesn't count anything."
  def blocked?(policy, subject, now \\ now_ms()) do
    if enabled?() do
      {limit, window_ms} = policy!(policy)

      case :ets.lookup(@table, {policy, subject, div(now, window_ms)}) do
        [{_key, count, expires}] when count >= limit -> {:blocked, expires - now}
        _ -> false
      end
    else
      false
    end
  end

  @doc "The count and window of a policy, after the `scale` setting."
  def policy!(policy) do
    {limit, window_ms} = Map.fetch!(@policies, policy)
    {max(1, round(limit * scale())), window_ms}
  end

  def policies, do: Map.keys(@policies)

  @doc "Forget every count (tests)."
  def reset, do: :ets.delete_all_objects(@table)

  @doc """
  Hold a seat for `ip` for as long as the calling process lives: one per live room connection.
  Refuses with `{:error, :too_many}` when the address already holds as many as a few games' worth
  (`:seats_per_ip`, scaled like the other limits), so a script can't keep hundreds of connections
  open. The seat is let go by itself when the process ends.
  """
  def hold_seat(ip) do
    limit = max(1, round(Keyword.get(settings(), :seats_per_ip, 24) * scale()))

    cond do
      not enabled?() -> :ok
      Registry.count_match(Backend.SeatRegistry, ip, :_) >= limit -> {:error, :too_many}
      true -> (fn {:ok, _} -> :ok end).(Registry.register(Backend.SeatRegistry, ip, nil))
    end
  end

  defp settings, do: Application.get_env(:backend, :rate_limits, [])

  @doc "Are the limits on?"
  def enabled?, do: Keyword.get(settings(), :enabled, true)
  defp scale, do: Keyword.get(settings(), :scale, 1)
  defp now_ms, do: System.system_time(:millisecond)

  # --- the process that owns the table, and tidies it ---

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      write_concurrency: true,
      read_concurrency: true
    ])

    schedule_sweep()
    {:ok, nil}
  end

  # Counts of windows that have ended are of no use: remove them, or the table would only grow.
  @impl true
  def handle_info(:sweep, state) do
    sweep(now_ms())
    schedule_sweep()
    {:noreply, state}
  end

  @doc false
  def sweep(now), do: :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every_ms)
end
