defmodule BackendWeb.AvatarChannelTest do
  # Changing your face while in a room
  use BackendWeb.ChannelCase, async: true

  alias Backend.Rooms
  alias BackendWeb.{RoomChannel, UserSocket}

  defp enter(code, id) do
    UserSocket
    |> socket("test", %{})
    |> subscribe_and_join(RoomChannel, "room:" <> code, %{"player_id" => id})
  end

  setup do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    {:ok, %{player_id: guest}} = Rooms.join_room(code, "Guest")
    {:ok, _, host_socket} = enter(code, host)
    {:ok, _, guest_socket} = enter(code, guest)
    %{code: code, host: host_socket, host_id: host, guest: guest_socket, guest_id: guest}
  end

  test "a player changes their face and the room is told", %{guest: socket, guest_id: id} do
    ref = push(socket, "set_avatar", %{"eyes" => 6, "mouth" => 5, "hat" => 4})
    assert_reply ref, :ok

    # (earlier updates, from people connecting, are in the mailbox too: wait for the one with the new face)
    assert_push "room_updated", %{
      room: %{players: [_host, %{id: ^id, avatar: %{eyes: 6, mouth: 5, hat: 4}}]}
    }
  end

  test "it changes only theirs", %{guest: socket, host_id: host} do
    {:ok, before} = Rooms.fetch_member_room(socket.assigns.room_code, host)
    ref = push(socket, "set_avatar", %{"eyes" => 0, "mouth" => 0, "hat" => 0})
    assert_reply ref, :ok
    {:ok, later} = Rooms.fetch_member_room(socket.assigns.room_code, host)
    assert later.players[host].avatar == before.players[host].avatar
  end

  test "a face that isn't valid is refused, and the old one stays", %{
    guest: socket,
    guest_id: id,
    code: code
  } do
    {:ok, before} = Rooms.fetch_member_room(code, id)

    for bad <- [%{"eyes" => 99, "mouth" => 0, "hat" => 0}, %{"eyes" => "a"}, %{}] do
      ref = push(socket, "set_avatar", bad)
      assert_reply ref, :error, %{reason: "invalid_avatar"}
    end

    {:ok, later} = Rooms.fetch_member_room(code, id)
    assert later.players[id].avatar == before.players[id].avatar
  end

  test "something that isn't even a map gets an answer, not a crash", %{guest: socket} do
    ref = push(socket, "set_avatar", "a face")
    assert_reply ref, :error
    assert Process.alive?(socket.channel_pid)
  end

  test "a player who joined with a face still has it after connecting" do
    {:ok, %{code: code, player_id: id}} =
      Rooms.create_room("Sam", %{"eyes" => 2, "mouth" => 3, "hat" => 4})

    {:ok, reply, _socket} = enter(code, id)
    assert [%{avatar: %{eyes: 2, mouth: 3, hat: 4}}] = reply.room.players
  end
end
