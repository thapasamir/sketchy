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
      assert_push "room_updated", %{room: %{phase: :reveal}}
    end

    test "the imposter is pushed a hint, never the word (the real per-socket check is in the browser test)",
         %{
           host: host,
           p2: p2,
           p3: p3,
           code: code
         } do
      assert_reply push(p2, "set_ready", %{"ready" => true}), :ok
      assert_reply push(p3, "set_ready", %{"ready" => true}), :ok
      assert_reply push(host, "start", %{}), :ok

      {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
      imposter_id = room.game.imposter_id
      word = room.game.entry.word

      # all three sockets share this test process, so look at every secret that was pushed
      secrets = for secret <- collect_secrets(), do: secret
      assert Enum.count(secrets, &(&1.role == "imposter")) == 1

      for %{role: "imposter"} = secret <- secrets do
        refute inspect(secret) =~ word
        assert Map.has_key?(secret, :hint)
      end

      assert imposter_id in Map.keys(room.players)
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

  defp collect_secrets(acc \\ []) do
    receive do
      %Phoenix.Socket.Message{event: "room_updated", payload: %{secret: %{} = secret}} ->
        collect_secrets([secret | acc])
    after
      200 -> acc |> Enum.uniq()
    end
  end

  describe "drawing" do
    setup do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
      {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")

      sockets =
        for id <- [host, p2, p3], into: %{} do
          {:ok, _, socket} = join_room("room:" <> code, %{"player_id" => id})
          {id, socket}
        end

      assert_reply push(sockets[p2], "set_ready", %{"ready" => true}), :ok
      assert_reply push(sockets[p3], "set_ready", %{"ready" => true}), :ok
      assert_reply push(sockets[host], "start", %{}), :ok
      assert_push "room_updated", %{room: %{phase: :drawing}}, 2000
      # the other two sockets get the same push; then forget the lobby's and the reveal's too
      Process.sleep(50)
      flush_mailbox()

      {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
      drawer = room.game.turn.player_id
      guest = Enum.find(Map.keys(sockets), &(&1 != drawer))
      %{code: code, sockets: sockets, drawer: drawer, guest: guest, ids: Map.keys(sockets)}
    end

    defp flush_mailbox do
      receive do
        _ -> flush_mailbox()
      after
        0 -> :ok
      end
    end

    defp start_stroke(id),
      do: %{"type" => "start", "id" => id, "size" => 2, "x" => 0.3, "y" => 0.4}

    test "the drawer's strokes are pushed to the OTHER players, not back to the drawer", ctx do
      push(ctx.sockets[ctx.drawer], "draw", start_stroke("a"))

      # two other players, two pushes (all three sockets report to this one test process)
      assert_push "draw", %{
        type: "start",
        id: "a",
        player_id: _,
        color: "#" <> _,
        points: [[0.3, 0.4]]
      }

      assert_push "draw", %{type: "start", id: "a"}
      refute_push "draw", _, 100
    end

    test "a successful stroke is not acknowledged (it would double the traffic)", ctx do
      ref = push(ctx.sockets[ctx.drawer], "draw", start_stroke("a"))
      refute_reply ref, _, 100
    end

    test "someone who is not drawing is told so, and nothing is shown to anyone", ctx do
      ref = push(ctx.sockets[ctx.guest], "draw", start_stroke("a"))
      assert_reply ref, :error, %{reason: "not_your_turn"}
      refute_push "draw", _, 100
    end

    test "nonsense is refused", ctx do
      ref = push(ctx.sockets[ctx.drawer], "draw", %{"type" => "start", "size" => 99})
      assert_reply ref, :error, %{reason: "invalid_event"}
      ref = push(ctx.sockets[ctx.drawer], "draw", %{})
      assert_reply ref, :error, %{reason: "invalid_event"}
    end

    test "undo is answered with the stroke that was removed, and shown to the others", ctx do
      push(ctx.sockets[ctx.drawer], "draw", start_stroke("a"))
      assert_push "draw", %{id: "a"}
      assert_push "draw", %{id: "a"}

      ref = push(ctx.sockets[ctx.drawer], "undo", %{})
      assert_reply ref, :ok, %{type: "undo", id: "a"}
      assert_push "draw", %{type: "undo", id: "a"}
    end

    test "a guest cannot undo", ctx do
      ref = push(ctx.sockets[ctx.guest], "undo", %{})
      assert_reply ref, :error, %{reason: "not_your_turn"}
    end

    test "finishing a turn hands the pen to the next player", ctx do
      assert_reply push(ctx.sockets[ctx.drawer], "finish_turn", %{}), :ok
      assert_push "room_updated", %{room: %{turn: %{player_id: next}}}
      assert next != ctx.drawer

      ref = push(ctx.sockets[ctx.drawer], "finish_turn", %{})
      assert_reply ref, :error, %{reason: "not_your_turn"}
    end

    test "the room update names whose turn it is and carries colours, but not the picture", ctx do
      assert_reply push(ctx.sockets[ctx.drawer], "finish_turn", %{}), :ok
      assert_push "room_updated", %{room: room}

      assert %{player_id: _, lap: 1, laps: 3, ms_left: ms} = room.turn
      assert ms > 0
      assert Enum.all?(room.players, &is_binary(&1.color))
      refute Map.has_key?(room, :strokes)
    end

    test "someone who joins mid-game is given the picture so far", ctx do
      push(ctx.sockets[ctx.drawer], "draw", start_stroke("a"))

      push(ctx.sockets[ctx.drawer], "draw", %{
        "type" => "points",
        "id" => "a",
        "points" => [[0.5, 0.5]]
      })

      # a refresh: the same player joins again on a new socket
      assert {:ok, reply, _socket} = join_room("room:" <> ctx.code, %{"player_id" => ctx.guest})

      assert [%{id: "a", player_id: drawer, points: [[0.3, 0.4], [0.5, 0.5]], color: "#" <> _}] =
               reply.strokes

      assert drawer == ctx.drawer
    end

    test "sync gives back the picture exactly as the server has it", ctx do
      push(ctx.sockets[ctx.drawer], "draw", start_stroke("a"))

      ref = push(ctx.sockets[ctx.drawer], "sync", %{})
      assert_reply ref, :ok, %{strokes: [%{id: "a", points: [[0.3, 0.4]]}]}
    end

    test "sync is for members only", ctx do
      {:ok, %{code: other_code, player_id: stranger}} = Rooms.create_room("Elsewhere")
      {:ok, _, socket} = join_room("room:" <> other_code, %{"player_id" => stranger})

      # a member of ANOTHER room gets that room's (empty) picture, never this one's
      push(ctx.sockets[ctx.drawer], "draw", start_stroke("a"))
      ref = push(socket, "sync", %{})
      assert_reply ref, :ok, %{strokes: []}
    end

    test "before the game there is no picture", _ctx do
      {:ok, %{code: code, player_id: id}} = Rooms.create_room("Solo")
      assert {:ok, %{strokes: []}, _} = join_room("room:" <> code, %{"player_id" => id})
    end
  end
end
