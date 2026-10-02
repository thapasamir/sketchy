defmodule BackendWeb.RoomChannelTest do
  use BackendWeb.ChannelCase, async: true

  alias Backend.Rooms
  alias BackendWeb.{RoomChannel, UserSocket}

  defp join_room(topic, params) do
    UserSocket |> socket("test", %{}) |> subscribe_and_join(RoomChannel, topic, params)
  end

  test "a member joins and receives the public room state" do
    {:ok, %{code: code, player_id: id}} = Rooms.create_room("Samir")

    assert {:ok, reply, _socket} = join_room("room:" <> code, %{"player_id" => id})
    assert reply.you == id
    assert %{code: ^code, host_id: ^id, players: [%{id: ^id, name: "Samir"}]} = reply.room
  end

  test "someone who is not in the room is rejected" do
    {:ok, %{code: code}} = Rooms.create_room("Samir")

    assert {:error, %{reason: "not_a_member"}} =
             join_room("room:" <> code, %{"player_id" => "nope"})
  end

  test "an unknown room is rejected" do
    assert {:error, %{reason: "room_not_found"}} = join_room("room:ZZZZ", %{"player_id" => "x"})
  end

  test "joining without a player_id is rejected" do
    {:ok, %{code: code}} = Rooms.create_room("Samir")
    assert {:error, %{reason: "player_id_required"}} = join_room("room:" <> code, %{})
  end

  test "an already-joined player is pushed the new player list when someone connects" do
    {:ok, %{code: code, player_id: id}} = Rooms.create_room("Samir")
    {:ok, _reply, _socket} = join_room("room:" <> code, %{"player_id" => id})

    {:ok, %{player_id: id2}} = Rooms.join_room(code, "Priya")
    {:ok, _reply, _socket} = join_room("room:" <> code, %{"player_id" => id2})

    assert_push "room_updated", %{
      room: %{players: [%{name: "Samir", connected: true}, %{name: "Priya", connected: true}]}
    }
  end

  describe "messages from the browser" do
    setup do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
      {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")
      {:ok, _, host_socket} = join_room("room:" <> code, %{"player_id" => host})
      {:ok, _, p2_socket} = join_room("room:" <> code, %{"player_id" => p2})
      {:ok, _, p3_socket} = join_room("room:" <> code, %{"player_id" => p3})
      %{code: code, host: host_socket, p2: p2_socket, p3: p3_socket, p2_id: p2, p3_id: p3}
    end

    test "host updates settings", %{host: socket} do
      ref = push(socket, "update_settings", %{"rounds" => 4})
      assert_reply ref, :ok
      assert_push "room_updated", %{room: %{settings: %{rounds: 4}}}
    end

    test "a non-host is refused", %{p2: socket} do
      ref = push(socket, "update_settings", %{"rounds" => 4})
      assert_reply ref, :error, %{reason: "not_host"}
    end

    test "ready is required before the host can start", %{host: socket, p2: p2, p3: p3} do
      ref = push(socket, "start", %{})
      assert_reply ref, :error, %{reason: "not_all_ready"}

      assert_reply push(p2, "set_ready", %{"ready" => true}), :ok
      assert_reply push(p3, "set_ready", %{"ready" => true}), :ok

      ref = push(socket, "start", %{})
      assert_reply ref, :ok
      assert_push "room_updated", %{room: %{phase: :playing}}
    end

    test "the host can't mark themselves ready", %{host: socket} do
      assert_reply push(socket, "set_ready", %{"ready" => true}), :error, %{reason: "host_cannot"}
    end

    test "host removes a player; that player's channel is told and closes", %{
      host: host,
      p2_id: p2_id
    } do
      assert_reply push(host, "kick", %{"player_id" => p2_id}), :ok
      assert_push "kicked", %{}
      assert_push "room_updated", %{room: %{players: [_, _]}}
    end

    test "a non-host can't remove anyone", %{p2: socket, p3_id: p3_id} do
      assert_reply push(socket, "kick", %{"player_id" => p3_id}), :error, %{reason: "not_host"}
    end

    test "leave frees the seat", %{code: code, p2: socket} do
      ref = push(socket, "leave", %{})
      assert_reply ref, :ok
      # earlier connects also pushed updates (3 players); only the post-leave one has exactly 2
      assert_push "room_updated", %{room: %{players: [_, _]}}
      assert {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
      assert map_size(room.players) == 2
    end
  end
end
