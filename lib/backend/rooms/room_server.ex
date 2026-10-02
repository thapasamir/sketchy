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

  def join(code, player_id, name), do: call(code, {:join, player_id, name})

  # Registry.lookup is a cheap in-memory lookup: code -> pid
  defp call(code, message) do
    case Registry.lookup(Backend.RoomRegistry, code) do
      [{pid, _value}] -> call_pid(pid, message)
      [] -> {:error, :room_not_found}
    end
  end

  # The Registry forgets a dead process slightly AFTER it dies. In that gap lookup still returns
  # the old pid, and GenServer.call on a dead pid makes the CALLER exit with :noproc.
  # A room that just closed is simply "not found", so turn that exit into an error value.
  defp call_pid(pid, message) do
    GenServer.call(pid, message)
  catch
    :exit, {:noproc, _call} -> {:error, :room_not_found}
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

  # Check-and-add happens inside ONE message, so two people grabbing the last seat or the same
  # name at the same moment are handled one after the other. The second one is told no.
  def handle_call({:join, player_id, name}, _from, room) do
    case Room.join(room, player_id, name) do
      {:ok, room} ->
        broadcast(room)
        {:reply, {:ok, room}, room}

      {:error, _reason} = error ->
        {:reply, error, room}
    end
  end

  # Tell everyone watching this room. PubSub = "publish to a topic, every subscriber gets a copy".
  # The room process doesn't know or care who is listening (channels, tests, ...).
  defp broadcast(room) do
    Phoenix.PubSub.broadcast(Backend.PubSub, "rooms:" <> room.code, {:room_updated, room})
  end
end
