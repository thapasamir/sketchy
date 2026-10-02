defmodule BackendWeb.RoomChannel do
  use BackendWeb, :channel

  alias Backend.Rooms
  alias Backend.Rooms.Room

  # A client joins topic "room:ABCD" with params %{"player_id" => "..."}.
  # Replying {:ok, payload, socket} accepts the join and sends payload to the joiner;
  # {:error, payload} rejects it. The returned socket carries per-connection state.
  @impl true
  def join("room:" <> code, %{"player_id" => player_id}, socket) when is_binary(player_id) do
    # Subscribe first, then read state: an update landing in between can't be missed.
    Rooms.subscribe(code)

    case Rooms.fetch_member_room(code, player_id) do
      {:ok, room} ->
        socket = assign(socket, room_code: room.code, player_id: player_id)
        {:ok, %{room: Room.to_public(room), you: player_id}, socket}

      {:error, reason} ->
        {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  def join("room:" <> _code, _params, _socket), do: {:error, %{reason: "player_id_required"}}

  # Messages sent to this channel's own process (from PubSub) arrive in handle_info.
  @impl true
  def handle_info({:room_updated, room}, socket) do
    push(socket, "room_updated", %{room: Room.to_public(room)})
    {:noreply, socket}
  end
end
