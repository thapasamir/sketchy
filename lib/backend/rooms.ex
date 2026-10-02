defmodule Backend.Rooms do
  @moduledoc """
  The public API of the rooms domain.

  The web layer (controllers, channels) calls ONLY this module. It never starts processes or
  talks to `RoomServer` itself, so how rooms work internally can change without touching the web code.
  """

  alias Backend.Rooms.{Room, RoomServer}

  # No I or O, so codes are easy to read out loud and hard to mix up with 1 and 0.
  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ"
  @code_length 4
  @max_name_length 20
  @max_code_attempts 10

  @doc """
  Create a room and make `host_name` its first player (and host).

  Returns `{:ok, %{code: code, player_id: id}}` or `{:error, reason}`.
  """
  def create_room(host_name) do
    with {:ok, name} <- validate_name(host_name) do
      start_room(%{id: new_player_id(), name: name}, @max_code_attempts)
    end
  end

  @doc """
  Join an existing room as a new player.

  Returns `{:ok, %{code: code, player_id: id}}` or `{:error, reason}` where reason is one of
  `:name_required`, `:name_too_long`, `:room_not_found`, `:room_full`, `:name_taken`, `:game_in_progress`.
  """
  def join_room(code, name) do
    with {:ok, name} <- validate_name(name),
         player_id = new_player_id(),
         {:ok, room} <- RoomServer.join(normalize_code(code), player_id, name) do
      {:ok, %{code: room.code, player_id: player_id}}
    end
  end

  @doc "Mark `player_id` as connected through `pid` (their channel). Fails if they aren't in the room."
  def connect(code, player_id, pid), do: RoomServer.connect(normalize_code(code), player_id, pid)

  @doc "Leave on purpose: the seat is freed immediately, and the room closes if it's now empty."
  def leave(code, player_id), do: RoomServer.leave(normalize_code(code), player_id)

  @doc "Host changes the settings. `params` come straight from the browser (string keys)."
  def update_settings(code, player_id, params) do
    changes =
      for {param, key} <- [{"rounds", :rounds}, {"draw_time", :draw_time}],
          Map.has_key?(params, param),
          into: %{},
          do: {key, params[param]}

    RoomServer.update_settings(normalize_code(code), player_id, changes)
  end

  @doc "A non-host player toggles ready."
  def set_ready(code, player_id, ready?),
    do: RoomServer.set_ready(normalize_code(code), player_id, ready?)

  @doc "Host removes another player from the lobby."
  def kick(code, host_id, target_id),
    do: RoomServer.kick(normalize_code(code), host_id, target_id)

  @doc "Host starts the game."
  def start_game(code, player_id), do: RoomServer.start_game(normalize_code(code), player_id)

  @doc "Get `{:room_updated, room}` messages in this process whenever the room changes."
  def subscribe(code) do
    Phoenix.PubSub.subscribe(Backend.PubSub, "rooms:" <> normalize_code(code))
  end

  @doc "Returns `{:ok, room}` only if `player_id` is a member of the room."
  def fetch_member_room(code, player_id) do
    with {:ok, room} <- RoomServer.get_state(normalize_code(code)) do
      if Room.member?(room, player_id), do: {:ok, room}, else: {:error, :not_a_member}
    end
  end

  # Ask the supervisor to start a room under a random code. If that code is taken the start
  # fails atomically with :already_started and we simply try another code. Checking first
  # ("is it free?") and then starting would be a race between two players creating rooms at once.
  defp start_room(_host, 0), do: {:error, :no_free_code}

  defp start_room(host, attempts_left) do
    code = generate_code()
    spec = {RoomServer, code: code, host: host, grace_ms: grace_ms()}

    case DynamicSupervisor.start_child(Backend.RoomSupervisor, spec) do
      {:ok, _pid} -> {:ok, %{code: code, player_id: host.id}}
      {:error, {:already_started, _pid}} -> start_room(host, attempts_left - 1)
      {:error, _other} -> {:error, :room_start_failed}
    end
  end

  # How long a disconnected player keeps their seat (config/test.exs shortens it for tests)
  defp grace_ms, do: Application.get_env(:backend, :reconnect_grace_ms, 30_000)

  defp validate_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :name_required}
      String.length(trimmed) > @max_name_length -> {:error, :name_too_long}
      true -> {:ok, trimmed}
    end
  end

  defp validate_name(_), do: {:error, :name_required}

  defp generate_code do
    for _ <- 1..@code_length, into: "", do: <<Enum.random(@code_alphabet)>>
  end

  defp new_player_id, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

  defp normalize_code(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  defp normalize_code(_), do: ""
end
