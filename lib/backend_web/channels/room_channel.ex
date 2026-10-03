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

    case Rooms.connect(code, player_id, self()) do
      {:ok, room} ->
        socket = assign(socket, room_code: room.code, player_id: player_id)

        {:ok,
         %{room: Room.to_public(room), secret: Room.secret_for(room, player_id), you: player_id},
         socket}

      {:error, reason} ->
        {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  def join("room:" <> _code, _params, _socket), do: {:error, %{reason: "player_id_required"}}

  # Messages from the browser. The server decides everything: a non-host asking to change
  # settings is simply refused, whatever the UI showed.
  @impl true
  def handle_in("update_settings", params, socket) do
    socket.assigns.room_code
    |> Rooms.update_settings(socket.assigns.player_id, params)
    |> to_reply(socket)
  end

  def handle_in("start", _params, socket) do
    socket.assigns.room_code
    |> Rooms.start_game(socket.assigns.player_id)
    |> to_reply(socket)
  end

  def handle_in("set_ready", %{"ready" => ready}, socket) do
    socket.assigns.room_code
    |> Rooms.set_ready(socket.assigns.player_id, ready)
    |> to_reply(socket)
  end

  def handle_in("kick", %{"player_id" => target_id}, socket) when is_binary(target_id) do
    socket.assigns.room_code
    |> Rooms.kick(socket.assigns.player_id, target_id)
    |> to_reply(socket)
  end

  def handle_in("leave", _params, socket) do
    Rooms.leave(socket.assigns.room_code, socket.assigns.player_id)
    {:reply, :ok, socket}
  end

  defp to_reply(:ok, socket), do: {:reply, :ok, socket}
  defp to_reply({:ok, _room}, socket), do: {:reply, :ok, socket}

  defp to_reply({:error, reason}, socket),
    do: {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}

  # Messages sent to this channel's own process (from PubSub) arrive in handle_info.
  @impl true
  def handle_info({:player_kicked, player_id}, %{assigns: %{player_id: player_id}} = socket) do
    # (the same variable twice in a pattern means "only match if they are equal": it's me)
    push(socket, "kicked", %{})
    {:stop, :normal, socket}
  end

  def handle_info({:player_kicked, _someone_else}, socket), do: {:noreply, socket}

  def handle_info({:room_updated, room}, socket) do
    # `room` is the same for everyone; `secret` is computed per socket from THIS player's id
    push(socket, "room_updated", %{
      room: Room.to_public(room),
      secret: Room.secret_for(room, socket.assigns.player_id)
    })

    {:noreply, socket}
  end
end
