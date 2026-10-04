defmodule Backend.ImposterLeftTest do
  # What happens when the imposter walks out in the middle of a round: there is nobody left to
  # catch, so the round ends at once and the crew win it. (An imposter who is merely *away* may
  # come back, so the round carries on for them.)
  # (config/test.exs: reveal 200ms, turn 1.5s, vote 1.5s, guess 1s, a result stays up 800ms.)
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.{Room, RoomServer, Voting}

  defp channel, do: spawn(fn -> Process.sleep(:infinity) end)

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  defp state(code) do
    {:ok, room} = RoomServer.get_state(code)
    room
  end

  # `n` players in a started game (1 lap, 3 rounds); this test process is subscribed. The game is
  # at the reveal.
  defp reveal(n \\ 3) do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")

    others =
      for i <- 2..n do
        {:ok, %{player_id: id}} = Rooms.join_room(code, "Player#{i}")
        id
      end

    players = [host | others]
    pids = Map.new(players, fn id -> {id, channel()} end)
    for {id, pid} <- pids, do: {:ok, _} = Rooms.connect(code, id, pid)

    {:ok, _} = Rooms.update_settings(code, host, %{"laps" => 1})
    Rooms.subscribe(code)
    for id <- others, do: {:ok, _} = Rooms.set_ready(code, id, true)
    {:ok, _} = Rooms.start_game(code, host)
    %{code: code, host: host, players: players, pids: pids}
  end

  defp drawing(n \\ 3) do
    %{code: code} = game = reveal(n)
    assert_receive {:room_updated, %{phase: :drawing}}, 2000
    flush()
    Map.put(game, :imposter, state(code).game.imposter_id)
  end

  defp finish_all_turns(code) do
    case state(code) do
      %{phase: :drawing, game: %{turn: %{player_id: id}}} ->
        :ok = Rooms.finish_turn(code, id)
        finish_all_turns(code)

      _ ->
        :ok
    end
  end

  defp voting(n \\ 3) do
    %{code: code} = game = drawing(n)
    finish_all_turns(code)
    assert state(code).phase == :voting
    flush()
    game
  end

  defp guessing do
    %{code: code, players: players, imposter: imposter} = game = voting()

    for voter <- players do
      target = if voter == imposter, do: Enum.find(players, &(&1 != imposter)), else: imposter
      :ok = Rooms.vote(code, voter, target)
    end

    assert state(code).phase == :guess
    flush()
    game
  end

  defp crew(%{players: players, imposter: imposter}), do: Enum.reject(players, &(&1 == imposter))

  describe "the rule" do
    defp room_in(phase) do
      room =
        Enum.reduce(0..2, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

      room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
      {:ok, room} = Room.set_ready(room, "p1", true)
      {:ok, room} = Room.set_ready(room, "p2", true)

      deal = %{
        imposter_id: "p1",
        imposter_history: ["p1"],
        entry: %{category: "Things", word: "Giraffe", difficulty: "easy", hints: ["tall"]},
        hint: "tall",
        used_words: ["Giraffe"],
        turn_order: ~w(p0 p1 p2)
      }

      {:ok, room} = Room.start_game(room, "p0", deal)
      %{room | phase: phase}
    end

    test "in any phase of a round it ends the round: the crew win, with a point each" do
      for phase <- [:reveal, :drawing, :voting, :guess] do
        room = Room.remove_player(room_in(phase), "p1")
        assert {:ok, room} = Voting.imposter_left(room)
        assert room.phase == :result, "in #{phase}"
        assert %{outcome: :imposter_left, imposter_id: "p1", accused: nil} = room.game.result
        assert room.scores == %{"p0" => 1, "p2" => 1}
      end
    end

    test "the result still names who the imposter was (they have left the room)" do
      {:ok, room} = Voting.imposter_left(Room.remove_player(room_in(:drawing), "p1"))
      assert Room.to_public(room).result.names["p1"] == "Player1"
    end

    test "not outside a round" do
      for phase <- [:lobby, :result, :final] do
        assert {:error, :not_in_round} = Voting.imposter_left(room_in(phase))
      end
    end
  end

  describe "in a real room" do
    test "during the drawing the round ends at once, with the crew winning" do
      %{code: code, imposter: imposter} = game = drawing()
      crew = crew(game)

      :ok = Rooms.leave(code, imposter)

      room = state(code)
      assert room.phase == :result
      assert %{outcome: :imposter_left, imposter_id: ^imposter} = room.game.result
      assert room.scores == Map.new(crew, &{&1, 1})
    end

    test "during the reveal, before anyone has drawn" do
      %{code: code} = reveal()
      imposter = state(code).game.imposter_id
      assert state(code).phase == :reveal

      :ok = Rooms.leave(code, imposter)

      assert state(code).phase == :result
      assert %{outcome: :imposter_left} = state(code).game.result
    end

    test "during the vote, even after some votes are in" do
      %{code: code, imposter: imposter} = game = voting()
      [a, b] = crew(game)
      :ok = Rooms.vote(code, a, b)

      :ok = Rooms.leave(code, imposter)

      assert state(code).phase == :result
      assert %{outcome: :imposter_left} = state(code).game.result
    end

    test "while the caught imposter is guessing" do
      %{code: code, imposter: imposter} = guessing()

      :ok = Rooms.leave(code, imposter)

      room = state(code)
      assert room.phase == :result
      assert %{outcome: :imposter_left} = room.game.result
    end

    test "everyone is told at once" do
      %{code: code, imposter: imposter} = drawing()
      :ok = Rooms.leave(code, imposter)
      assert_receive {:room_updated, %{phase: :result}}
    end

    test "a stroke the imposter had begun is closed for everyone" do
      %{code: code} = game = drawing()
      imposter = game.imposter

      # make the imposter the one drawing, mid-stroke
      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      :sys.replace_state(pid, fn s -> put_in(s.room.game.turn.player_id, imposter) end)

      :ok =
        Rooms.draw(
          code,
          imposter,
          %{"type" => "start", "id" => "a", "size" => 1, "x" => 0.3, "y" => 0.3},
          self()
        )

      flush()
      :ok = Rooms.leave(code, imposter)
      assert_receive {:draw_event, nil, %{type: "end", id: "a"}}
    end

    test "when a crew member leaves, the round carries on" do
      %{code: code} = game = drawing()
      [leaver | _] = crew(game)
      # (the leaver must not be the one drawing, or the pen just moves on: that is fine too)
      :ok = Rooms.leave(code, leaver)

      assert state(code).phase == :drawing
    end

    test "when the imposter is only away, the round carries on (they may be back)" do
      %{code: code, imposter: imposter, pids: pids} = drawing()
      Process.exit(pids[imposter], :kill)
      assert_receive {:room_updated, %{players: %{^imposter => %{connected?: false}}}}, 1000

      assert state(code).phase in [:drawing, :voting]
      assert state(code).game.result == nil
    end

    test "an imposter who leaves after the round is over changes nothing" do
      %{code: code, imposter: imposter, players: players} = voting()
      innocent = Enum.find(players, &(&1 != imposter))
      other = Enum.find(players, &(&1 != innocent))

      for voter <- players do
        :ok = Rooms.vote(code, voter, if(voter == innocent, do: other, else: innocent))
      end

      assert state(code).game.result.outcome == :escaped
      scores = state(code).scores

      :ok = Rooms.leave(code, imposter)

      assert state(code).game.result.outcome == :escaped
      assert state(code).scores == scores
    end

    test "the wait after the result still happens, then the game goes on (or ends)" do
      %{code: code, imposter: imposter} = drawing(3)
      :ok = Rooms.leave(code, imposter)
      assert state(code).phase == :result

      # two people left: not enough to play another round
      assert_receive {:room_updated, %{phase: :final}}, 3000
    end

    test "with enough players left, the next round starts as usual, without them" do
      %{code: code, imposter: imposter} = drawing(4)
      :ok = Rooms.leave(code, imposter)

      assert_receive {:room_updated, %{phase: :reveal, game: %{round: 2}}}, 3000
      room = state(code)
      refute room.game.imposter_id == imposter
      refute Map.has_key?(room.players, imposter)
      assert map_size(room.players) == 3
    end

    test "no timer from the abandoned round is left to fire" do
      %{code: code, imposter: imposter} = drawing(4)
      :ok = Rooms.leave(code, imposter)

      # the 1.5s turn timer would have moved the pen on; it must not touch the finished round
      Process.sleep(500)
      room = state(code)
      assert room.phase in [:result, :reveal]
      assert room.game.round in [1, 2]
    end
  end
end
