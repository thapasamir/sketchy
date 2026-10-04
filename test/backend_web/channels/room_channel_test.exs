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

      assert %{player_id: _, order: [_, _, _], ms_left: ms} = room.turn
      assert %{round: 1, rounds: 3} = room
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

    test "chat is closed while drawing", ctx do
      ref = push(ctx.sockets[ctx.drawer], "chat", %{"text" => "it's a giraffe"})
      assert_reply ref, :error, %{reason: "chat_closed"}
      refute_push "chat", _, 100
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

  describe "voting" do
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

      # play out the drawing: each drawer hands the pen on until it runs out (however many laps)
      finish_all_turns(sockets, code)

      {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
      assert room.phase == :voting
      flush_votes_mailbox()

      imposter = room.game.imposter_id
      [crew_a, crew_b] = Enum.reject([host, p2, p3], &(&1 == imposter))

      %{
        code: code,
        sockets: sockets,
        imposter: imposter,
        crew_a: crew_a,
        crew_b: crew_b,
        word: room.game.entry.word
      }
    end

    defp finish_all_turns(sockets, code) do
      case Backend.Rooms.RoomServer.get_state(code) do
        {:ok, %{phase: :drawing, game: %{turn: %{player_id: id}}}} ->
          assert_reply push(sockets[id], "finish_turn", %{}), :ok
          finish_all_turns(sockets, code)

        _ ->
          :ok
      end
    end

    defp flush_votes_mailbox do
      receive do
        _ -> flush_votes_mailbox()
      after
        50 -> :ok
      end
    end

    test "a vote is accepted, and the room says who has voted but not for whom", ctx do
      assert_reply push(ctx.sockets[ctx.crew_a], "vote", %{"target_id" => ctx.imposter}), :ok

      assert_push "room_updated", %{room: %{vote: %{voted: voted} = vote}}
      assert voted == [ctx.crew_a]
      refute Map.has_key?(vote, :votes)
    end

    test "your own vote is told to you when you come back", ctx do
      assert_reply push(ctx.sockets[ctx.crew_a], "vote", %{"target_id" => ctx.imposter}), :ok

      assert {:ok, %{vote: vote}, _} =
               join_room("room:" <> ctx.code, %{"player_id" => ctx.crew_a})

      assert vote == ctx.imposter

      assert {:ok, %{vote: nil}, _} = join_room("room:" <> ctx.code, %{"player_id" => ctx.crew_b})
    end

    test "bad votes are refused with a reason", ctx do
      ref = push(ctx.sockets[ctx.crew_a], "vote", %{"target_id" => ctx.crew_a})
      assert_reply ref, :error, %{reason: "cannot_vote_self"}

      ref = push(ctx.sockets[ctx.crew_a], "vote", %{"target_id" => "ghost"})
      assert_reply ref, :error, %{reason: "not_a_member"}
    end

    test "catching the imposter, their guess, and the result that shows the word", ctx do
      for voter <- Map.keys(ctx.sockets) do
        target = if voter == ctx.imposter, do: ctx.crew_a, else: ctx.imposter
        assert_reply push(ctx.sockets[voter], "vote", %{"target_id" => target}), :ok
      end

      assert_push "room_updated", %{room: %{phase: :guess, guess: %{guesser_id: guesser}}}
      assert guesser == ctx.imposter

      ref = push(ctx.sockets[ctx.crew_a], "guess", %{"text" => ctx.word})
      assert_reply ref, :error, %{reason: "not_imposter"}

      assert_reply push(ctx.sockets[ctx.imposter], "guess", %{"text" => ctx.word}), :ok

      assert_push "room_updated", %{
        room: %{phase: :result, result: %{outcome: :guessed, word: word, imposter_id: id}}
      }

      assert word == ctx.word
      assert id == ctx.imposter
    end

    defp end_round_innocent(ctx) do
      # the crew accuses one of their own: the round is over at once
      for voter <- Map.keys(ctx.sockets) do
        target = if voter == ctx.crew_a, do: ctx.crew_b, else: ctx.crew_a
        assert_reply push(ctx.sockets[voter], "vote", %{"target_id" => target}), :ok
      end

      assert_push "room_updated", %{room: %{phase: :result}}
    end

    test "the host can start the next round straight away; nobody else can", ctx do
      ref = push(ctx.sockets[ctx.crew_a], "next_round", %{})
      assert_reply ref, :error, %{reason: "not_result"}

      end_round_innocent(ctx)
      {:ok, room} = Backend.Rooms.RoomServer.get_state(ctx.code)
      host_socket = ctx.sockets[room.host_id]
      guest = Enum.find(Map.keys(ctx.sockets), &(&1 != room.host_id))

      ref = push(ctx.sockets[guest], "next_round", %{})
      assert_reply ref, :error, %{reason: "not_host"}

      assert_reply push(host_socket, "next_round", %{}), :ok
      assert_push "room_updated", %{room: %{phase: :reveal, round: 2, rounds: 3}}
    end

    test "the result tells everyone how long until the next round", ctx do
      end_round_innocent(ctx)
      assert_push "room_updated", %{room: %{phase: :result, result: %{ms_left: ms}}}
      assert is_integer(ms) and ms > 0
    end

    test "playing again is refused until the game is over", ctx do
      {:ok, room} = Backend.Rooms.RoomServer.get_state(ctx.code)
      ref = push(ctx.sockets[room.host_id], "play_again", %{})
      assert_reply ref, :error, %{reason: "not_finished"}
    end

    test "chat is open for the vote, and the secret word is hidden in it", ctx do
      assert_reply push(ctx.sockets[ctx.crew_a], "chat", %{"text" => "is it a #{ctx.word}?"}), :ok

      # three sockets in this process, so three pushes of the one message
      for _ <- 1..3 do
        assert_push "chat", %{text: text}
        refute text =~ ~r/#{Regex.escape(ctx.word)}/i
        assert text =~ "is it a "
      end
    end

    test "the room says chat is open while voting", ctx do
      assert_reply push(ctx.sockets[ctx.crew_a], "vote", %{"target_id" => ctx.imposter}), :ok
      assert_push "room_updated", %{room: %{phase: :voting, chat_open: true}}
    end

    test "while voting, the word is nowhere in what the room pushes", ctx do
      assert_reply push(ctx.sockets[ctx.crew_a], "vote", %{"target_id" => ctx.imposter}), :ok
      assert_push "room_updated", %{room: room}
      refute inspect(room) =~ ctx.word
    end
  end

  describe "chat" do
    setup do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")

      sockets =
        for id <- [host, p2], into: %{} do
          {:ok, _, socket} = join_room("room:" <> code, %{"player_id" => id})
          {id, socket}
        end

      %{code: code, host: host, p2: p2, sockets: sockets}
    end

    test "a message is pushed to every socket in the room, sender included", ctx do
      assert_reply push(ctx.sockets[ctx.host], "chat", %{"text" => "hello"}), :ok

      # both sockets belong to this one test process, so both pushes arrive here
      assert_push "chat", %{text: "hello", name: "Host", player_id: _, id: _, at: _}
      assert_push "chat", %{text: "hello", name: "Host"}
    end

    test "the speaker's name is the room's, whatever the browser claims", ctx do
      assert_reply push(ctx.sockets[ctx.p2], "chat", %{"text" => "hi", "name" => "Host"}), :ok
      assert_push "chat", %{name: "Two"}
    end

    test "blank, too long, and malformed messages are refused with a reason", ctx do
      ref = push(ctx.sockets[ctx.host], "chat", %{"text" => "   "})
      assert_reply ref, :error, %{reason: "empty"}

      Process.sleep(200)
      ref = push(ctx.sockets[ctx.host], "chat", %{"text" => String.duplicate("a", 201)})
      assert_reply ref, :error, %{reason: "too_long"}

      ref = push(ctx.sockets[ctx.host], "chat", %{})
      assert_reply ref, :error, %{reason: "empty"}

      ref = push(ctx.sockets[ctx.host], "chat", %{"text" => 42})
      assert_reply ref, :error, %{reason: "empty"}
      refute_push "chat", _, 100
    end

    test "speaking too fast is refused", ctx do
      assert_reply push(ctx.sockets[ctx.host], "chat", %{"text" => "one"}), :ok
      ref = push(ctx.sockets[ctx.host], "chat", %{"text" => "two"})
      assert_reply ref, :error, %{reason: "too_fast"}
    end

    test "the room says that chat is open, in the lobby", ctx do
      {:ok, reply, _} = join_room("room:" <> ctx.code, %{"player_id" => ctx.host})
      assert reply.room.chat_open
    end

    test "joining later shows nothing that was said before (the server keeps no chat)", ctx do
      assert_reply push(ctx.sockets[ctx.host], "chat", %{"text" => "you won't see this"}), :ok
      assert_push "chat", _
      assert_push "chat", _

      {:ok, reply, _} = join_room("room:" <> ctx.code, %{"player_id" => ctx.p2})
      refute inspect(reply) =~ "you won't see this"
      refute_push "chat", _, 100
    end
  end
end
