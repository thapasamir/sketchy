defmodule BackendWeb.RoomChannel do
  use BackendWeb, :channel

  alias Backend.RateLimit
  alias Backend.Rooms
  alias Backend.Rooms.Room
  alias BackendWeb.ChannelLimits

  # A client joins topic "room:ABCD" with params %{"player_id" => "..."}.
  # Replying {:ok, payload, socket} accepts the join and sends payload to the joiner;
  # {:error, payload} rejects it. The returned socket carries per-connection state.
  @impl true
  def join("room:" <> code, %{"player_id" => player_id}, socket) when is_binary(player_id) do
    ip = socket.assigns[:client_ip] || "unknown"

    # how often one address may join, and how many seats it may hold at once
    with :ok <- limit_join(RateLimit.hit(:channel_join, ip)),
         :ok <- limit_seats(RateLimit.hold_seat(ip)) do
      # Subscribe first, then read state: an update landing in between can't be missed.
      Rooms.subscribe(code)
      join_room(code, player_id, socket)
    end
  end

  def join("room:" <> _code, _params, _socket), do: {:error, %{reason: "player_id_required"}}

  defp limit_join(:ok), do: :ok
  defp limit_join({:error, _retry_ms}), do: {:error, %{reason: "rate_limited"}}

  defp limit_seats(:ok), do: :ok
  defp limit_seats({:error, :too_many}), do: {:error, %{reason: "too_many_connections"}}

  defp join_room(code, player_id, socket) do
    case Rooms.connect(code, player_id, self()) do
      {:ok, room} ->
        socket =
          socket
          |> assign(room_code: room.code, player_id: player_id)
          # how fast this connection may send messages (see ChannelLimits); none when limits are off
          |> assign(:limits, if(RateLimit.enabled?(), do: ChannelLimits.new()))

        {:ok,
         %{
           room: Room.to_public(room),
           secret: Room.secret_for(room, player_id),
           vote: Room.my_vote(room, player_id),
           # a player who joins or refreshes mid-game gets the picture as it is now
           strokes: Room.strokes_public(room),
           you: player_id
         }, socket}

      {:error, reason} ->
        {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  # Messages from the browser, counted first: one that comes too fast is refused, and a
  # connection that keeps doing it is closed.
  @impl true
  def handle_in(event, params, socket) do
    case take(socket, event) do
      {:ok, socket} ->
        dispatch(event, params, socket)

      {:refused, socket} ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}

      {:abusive, socket} ->
        # not just this room's channel: the whole connection, or it could simply join again
        if socket.id, do: BackendWeb.Endpoint.broadcast(socket.id, "disconnect", %{})
        {:stop, {:shutdown, :rate_limited}, socket}
    end
  end

  defp take(%{assigns: %{limits: limits}} = socket, event) when is_map(limits) do
    {status, limits} = ChannelLimits.take(limits, event)
    {status, assign(socket, :limits, limits)}
  end

  # (no limits on this connection: they are switched off)
  defp take(socket, _event), do: {:ok, socket}

  # What each message does. The server decides everything: a non-host asking to change
  # settings is simply refused, whatever the UI showed.
  defp dispatch("update_settings", params, socket) do
    socket.assigns.room_code
    |> Rooms.update_settings(socket.assigns.player_id, params)
    |> to_reply(socket)
  end

  defp dispatch("start", _params, socket) do
    socket.assigns.room_code
    |> Rooms.start_game(socket.assigns.player_id)
    |> to_reply(socket)
  end

  defp dispatch("set_ready", %{"ready" => ready}, socket) do
    socket.assigns.room_code
    |> Rooms.set_ready(socket.assigns.player_id, ready)
    |> to_reply(socket)
  end

  defp dispatch("kick", %{"player_id" => target_id}, socket) when is_binary(target_id) do
    socket.assigns.room_code
    |> Rooms.kick(socket.assigns.player_id, target_id)
    |> to_reply(socket)
  end

  # Strokes arrive many times a second. Success is silent (no reply traffic); only a refusal
  # is answered, so the drawer's browser can tell them why.
  defp dispatch("draw", params, socket) when is_map(params) do
    case Rooms.draw(socket.assigns.room_code, socket.assigns.player_id, params, self()) do
      :ok -> {:noreply, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  # "Show me the picture as the server has it." A drawer draws optimistically, so after a refusal
  # (or when their turn ends) they ask for this to be sure their screen matches everyone's.
  defp dispatch("vote", %{"target_id" => target_id}, socket) when is_binary(target_id) do
    socket.assigns.room_code
    |> Rooms.vote(socket.assigns.player_id, target_id)
    |> to_reply(socket)
  end

  defp dispatch("guess", %{"text" => text}, socket) when is_binary(text) do
    socket.assigns.room_code
    |> Rooms.guess(socket.assigns.player_id, text)
    |> to_reply(socket)
  end

  defp dispatch("next_round", _params, socket) do
    socket.assigns.room_code
    |> Rooms.next_round(socket.assigns.player_id)
    |> to_reply(socket)
  end

  defp dispatch("play_again", _params, socket) do
    socket.assigns.room_code
    |> Rooms.play_again(socket.assigns.player_id)
    |> to_reply(socket)
  end

  defp dispatch("chat", %{"text" => text}, socket) when is_binary(text) do
    socket.assigns.room_code
    |> Rooms.chat(socket.assigns.player_id, text)
    |> to_reply(socket)
  end

  defp dispatch("chat", _params, socket),
    do: {:reply, {:error, %{reason: "empty"}}, socket}

  defp dispatch("set_avatar", face, socket) when is_map(face) do
    socket.assigns.room_code
    |> Rooms.set_avatar(socket.assigns.player_id, face)
    |> to_reply(socket)
  end

  defp dispatch("react", %{"id" => id}, socket) do
    socket.assigns.room_code
    |> Rooms.react(socket.assigns.player_id, id)
    |> to_reply(socket)
  end

  defp dispatch("react", _params, socket),
    do: {:reply, {:error, %{reason: "invalid_reaction"}}, socket}

  defp dispatch("sync", _params, socket) do
    case Rooms.fetch_member_room(socket.assigns.room_code, socket.assigns.player_id) do
      {:ok, room} -> {:reply, {:ok, %{strokes: Room.strokes_public(room)}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  defp dispatch("undo", _params, socket) do
    case Rooms.undo(socket.assigns.room_code, socket.assigns.player_id, self()) do
      {:ok, event} -> {:reply, {:ok, event}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  defp dispatch("finish_turn", _params, socket) do
    socket.assigns.room_code
    |> Rooms.finish_turn(socket.assigns.player_id)
    |> to_reply(socket)
  end

  defp dispatch("leave", _params, socket) do
    Rooms.leave(socket.assigns.room_code, socket.assigns.player_id)
    {:reply, :ok, socket}
  end

  # a message this server doesn't know: say so, rather than crash the connection
  defp dispatch(_event, _params, socket),
    do: {:reply, {:error, %{reason: "unknown_event"}}, socket}

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

  # A stroke from the drawer. Everyone except the channel that sent it is shown it.
  def handle_info({:draw_event, origin, _event}, socket) when origin == self(),
    do: {:noreply, socket}

  def handle_info({:draw_event, _origin, event}, socket) do
    push(socket, "draw", event)
    {:noreply, socket}
  end

  # Someone said something. Every socket in the room is told; nothing is kept.
  def handle_info({:chat, message}, socket) do
    push(socket, "chat", message)
    {:noreply, socket}
  end

  # Someone reacted. Same as chat: every socket is told, nothing is kept.
  def handle_info({:reaction, event}, socket) do
    push(socket, "reaction", event)
    {:noreply, socket}
  end

  def handle_info({:room_updated, room}, socket) do
    # `room` is the same for everyone; `secret` is computed per socket from THIS player's id
    push(socket, "room_updated", %{
      room: Room.to_public(room),
      secret: Room.secret_for(room, socket.assigns.player_id),
      vote: Room.my_vote(room, socket.assigns.player_id)
    })

    {:noreply, socket}
  end
end
