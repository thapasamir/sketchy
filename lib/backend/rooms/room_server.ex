defmodule Backend.Rooms.RoomServer do
  @moduledoc """
  One process per room. It owns that room's `Room` struct and is the only thing allowed to change it.

  Other code never touches the struct directly: it sends this process a message
  (`GenServer.call/2`) and the process handles messages one at a time, in order.
  That is why no locks are needed.
  """

  # :temporary = if this process crashes, do NOT restart it. A restart would start from empty
  # state (the players would be gone), so a crashed room should just close.
  use GenServer, restart: :temporary

  require Logger

  alias Backend.Rooms.Room

  # --- Client API: runs in the CALLER's process ---

  def start_link(opts) do
    code = Keyword.fetch!(opts, :code)
    GenServer.start_link(__MODULE__, opts, name: via(code))
  end

  def get_state(code), do: call(code, :get_state)

  def add_player(code, player_id, name), do: call(code, {:add_player, player_id, name})

  # Registry.lookup is a cheap in-memory lookup: code -> pid
  defp call(code, message) do
    case Registry.lookup(Backend.RoomRegistry, code) do
      [{pid, _value}] -> GenServer.call(pid, message)
      [] -> {:error, :room_not_found}
    end
  end

  # Registering under {:via, Registry, ...} makes the code the process's name.
  # Starting a second process with the same code fails with {:error, {:already_started, pid}}.
  defp via(code), do: {:via, Registry, {Backend.RoomRegistry, code}}

  # --- Callbacks: run INSIDE the room process ---

  @impl true
  def init(opts) do
    code = Keyword.fetch!(opts, :code)
    host = Keyword.fetch!(opts, :host)

    room = code |> Room.new(host.id) |> Room.add_player(host.id, host.name)
    Logger.info("Room #{code} created by #{host.name}")
    {:ok, room}
  end

  # Pattern matching on the message picks the clause, like a router for messages.
  @impl true
  def handle_call(:get_state, _from, room) do
    {:reply, {:ok, room}, room}
  end

  def handle_call({:add_player, player_id, name}, _from, room) do
    room = Room.add_player(room, player_id, name)
    {:reply, {:ok, room}, room}
  end
end
