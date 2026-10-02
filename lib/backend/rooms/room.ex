defmodule Backend.Rooms.Room do
  @moduledoc """
  The state of one room. Plain data plus pure functions: no processes, no side effects.

  Every function takes a room and returns a new room (data is immutable).
  `Backend.Rooms.RoomServer` is the process that holds the current value.
  """

  @max_players 8
  @min_players 3
  @round_range 2..4
  @draw_time_range 30..90//10

  defstruct code: nil,
            host_id: nil,
            phase: :lobby,
            players: %{},
            settings: %{rounds: 3, draw_time: 60},
            created_at: nil

  @type t :: %__MODULE__{
          code: String.t(),
          host_id: String.t(),
          phase: atom(),
          players: %{String.t() => map()},
          settings: map(),
          created_at: DateTime.t()
        }

  def new(code, host_id) do
    %__MODULE__{code: code, host_id: host_id, created_at: DateTime.utc_now()}
  end

  def add_player(%__MODULE__{} = room, player_id, name) do
    player = %{
      id: player_id,
      name: name,
      connected?: false,
      ready?: false,
      joined_at: DateTime.utc_now()
    }

    %{room | players: Map.put(room.players, player_id, player)}
  end

  @doc """
  The rules for joining, kept pure so they are trivial to test.
  Returns `{:ok, room}` or `{:error, reason}`.
  """
  def join(%__MODULE__{} = room, player_id, name) do
    cond do
      room.phase != :lobby -> {:error, :game_in_progress}
      player_count(room) >= @max_players -> {:error, :room_full}
      name_taken?(room, name) -> {:error, :name_taken}
      true -> {:ok, add_player(room, player_id, name)}
    end
  end

  def name_taken?(%__MODULE__{} = room, name) do
    wanted = String.downcase(name)
    Enum.any?(room.players, fn {_id, p} -> String.downcase(p.name) == wanted end)
  end

  def set_connected(%__MODULE__{} = room, player_id, connected?) do
    case room.players do
      %{^player_id => player} ->
        %{room | players: Map.put(room.players, player_id, %{player | connected?: connected?})}

      _ ->
        room
    end
  end

  @doc """
  Remove a player. If the host left, the longest-present connected player becomes host
  (or the longest-present player if nobody is connected). An empty room has `host_id: nil`.
  """
  def remove_player(%__MODULE__{} = room, player_id) do
    players = Map.delete(room.players, player_id)
    host_id = if player_id == room.host_id, do: next_host(players), else: room.host_id
    %{room | players: players, host_id: host_id}
  end

  defp next_host(players) when map_size(players) == 0, do: nil

  defp next_host(players) do
    candidates = Map.values(players)
    pool = Enum.filter(candidates, & &1.connected?)
    pool = if pool == [], do: candidates, else: pool
    Enum.min_by(pool, & &1.joined_at, DateTime).id
  end

  @doc "Host-only. `changes` may hold `:rounds` and/or `:draw_time` as integers."
  def update_settings(%__MODULE__{} = room, player_id, changes) do
    with :ok <- check_host(room, player_id),
         :ok <- check_lobby(room),
         {:ok, settings} <- merge_settings(room.settings, changes) do
      # Everyone said "ready" to the OLD settings, so a real change asks them again.
      players = if settings == room.settings, do: room.players, else: reset_ready(room.players)
      {:ok, %{room | settings: settings, players: players}}
    end
  end

  @doc "A non-host player says they are (or are no longer) ready to start."
  def set_ready(%__MODULE__{} = room, player_id, ready?) when is_boolean(ready?) do
    with :ok <- check_lobby(room),
         :ok <- check_member(room, player_id),
         :ok <- check_not_host(room, player_id) do
      player = %{room.players[player_id] | ready?: ready?}
      {:ok, %{room | players: Map.put(room.players, player_id, player)}}
    end
  end

  def set_ready(_room, _player_id, _ready), do: {:error, :invalid_ready}

  @doc "Host-only. Returns `:ok` if `host_id` may remove `target_id`; the removal itself is `remove_player/2`."
  def can_kick(%__MODULE__{} = room, host_id, target_id) do
    with :ok <- check_host(room, host_id),
         :ok <- check_lobby(room),
         :ok <- check_member(room, target_id),
         :ok <- check_not_host(room, target_id) do
      :ok
    end
  end

  @doc "Host-only. Moves the room out of the lobby once enough players are connected."
  def start_game(%__MODULE__{} = room, player_id) do
    with :ok <- check_host(room, player_id),
         :ok <- check_lobby(room),
         :ok <- check_enough_players(room),
         :ok <- check_everyone_ready(room) do
      {:ok, %{room | phase: :playing}}
    end
  end

  defp check_host(room, player_id) do
    if room.host_id == player_id, do: :ok, else: {:error, :not_host}
  end

  defp check_lobby(room) do
    if room.phase == :lobby, do: :ok, else: {:error, :game_in_progress}
  end

  defp check_member(room, player_id) do
    if member?(room, player_id), do: :ok, else: {:error, :not_a_member}
  end

  # the host can't be kicked or "ready": they are the one pressing start
  defp check_not_host(room, player_id) do
    if player_id == room.host_id, do: {:error, :host_cannot}, else: :ok
  end

  # Players who are away don't hold up the start; everyone else must be ready.
  defp check_everyone_ready(room) do
    waiting =
      Enum.any?(room.players, fn {id, p} ->
        id != room.host_id and p.connected? and not p.ready?
      end)

    if waiting, do: {:error, :not_all_ready}, else: :ok
  end

  defp reset_ready(players) do
    Map.new(players, fn {id, p} -> {id, %{p | ready?: false}} end)
  end

  defp check_enough_players(room) do
    connected = Enum.count(room.players, fn {_id, p} -> p.connected? end)
    if connected >= @min_players, do: :ok, else: {:error, :not_enough_players}
  end

  defp merge_settings(settings, changes) do
    rounds = Map.get(changes, :rounds, settings.rounds)
    draw_time = Map.get(changes, :draw_time, settings.draw_time)

    if valid_in?(rounds, @round_range) and valid_in?(draw_time, @draw_time_range) do
      {:ok, %{settings | rounds: rounds, draw_time: draw_time}}
    else
      {:error, :invalid_settings}
    end
  end

  defp valid_in?(value, range), do: is_integer(value) and value in range

  def member?(%__MODULE__{} = room, player_id), do: Map.has_key?(room.players, player_id)

  def player_count(%__MODULE__{} = room), do: map_size(room.players)

  @doc """
  The version of the room that is safe to send to browsers.

  Built by hand on purpose: later the room will hold secrets (the word, who the imposter is),
  and an explicit allow-list means a new field is never sent by accident.
  """
  def to_public(%__MODULE__{} = room) do
    players =
      room.players
      |> Map.values()
      |> Enum.sort_by(& &1.joined_at, DateTime)
      |> Enum.map(&%{id: &1.id, name: &1.name, connected: &1.connected?, ready: &1.ready?})

    %{
      code: room.code,
      host_id: room.host_id,
      phase: room.phase,
      settings: room.settings,
      min_players: @min_players,
      max_players: @max_players,
      players: players
    }
  end
end
