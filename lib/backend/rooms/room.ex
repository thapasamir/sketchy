defmodule Backend.Rooms.Room do
  @moduledoc """
  The state of one room. Plain data plus pure functions: no processes, no side effects.

  Every function takes a room and returns a new room (data is immutable).
  `Backend.Rooms.RoomServer` is the process that holds the current value.
  """

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
    player = %{id: player_id, name: name, connected?: true, joined_at: DateTime.utc_now()}
    %{room | players: Map.put(room.players, player_id, player)}
  end

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
      |> Enum.map(&%{id: &1.id, name: &1.name, connected: &1.connected?})

    %{
      code: room.code,
      host_id: room.host_id,
      phase: room.phase,
      settings: room.settings,
      players: players
    }
  end
end
