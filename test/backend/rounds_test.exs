defmodule Backend.Rooms.RoundsTest do
  # The pure rules for moving between rounds, the final standings and playing again.
  use ExUnit.Case, async: true

  alias Backend.Rooms.{Room, Voting}

  @now 1_000_000

  defp deal(imposter, word, order \\ ~w(p0 p1 p2 p3)) do
    %{
      imposter_id: imposter,
      imposter_history: [imposter],
      entry: %{category: "Things", word: word, difficulty: "easy", hints: ["a hint"]},
      hint: "a hint",
      used_words: [word],
      turn_order: order
    }
  end

  # round 1 of `rounds` is over (the imposter p1 got away): the result is showing
  defp result_room(rounds \\ 3) do
    room =
      Enum.reduce(0..3, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

    room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
    {:ok, room} = Room.update_settings(room, "p0", %{rounds: rounds})

    room =
      Enum.reduce(1..3, room, fn i, room ->
        {:ok, room} = Room.set_ready(room, "p#{i}", true)
        room
      end)

    {:ok, room} = Room.start_game(room, "p0", deal("p1", "Giraffe"))
    {:ok, room} = Room.end_reveal(room, @now, 30_000)

    room =
      Stream.iterate(room, &Room.next_turn(&1, @now, 30_000)) |> Enum.find(&(&1.phase == :voting))

    {:ok, room} = Voting.close(room, @now, 20_000)
    assert room.phase == :result
    room
  end

  describe "continue?/1" do
    test "yes, while there are rounds left and enough players" do
      assert Room.continue?(result_room(3))
    end

    test "no on the last round" do
      room = result_room(3)
      refute Room.continue?(put_in(room.game.round, 3))
      refute Room.continue?(put_in(result_room(2).game.round, 2))
    end

    test "no when fewer than 3 players are still connected" do
      room = result_room() |> Room.set_connected("p2", false)
      assert Room.continue?(room)
      room = Room.set_connected(room, "p3", false)
      refute Room.continue?(room)
    end

    test "players who left count too" do
      refute result_room()
             |> Room.remove_player("p3")
             |> Room.remove_player("p2")
             |> Room.continue?()
    end

    test "no outside the result" do
      refute Room.continue?(Room.new("ABCD", "p0"))
    end
  end

  describe "next_round/2" do
    test "deals the new round: another word and imposter, round 2, back to the reveal" do
      {:ok, room} = Room.next_round(result_room(), deal("p3", "Bicycle", ~w(p2 p3 p0 p1)))

      assert room.phase == :reveal
      assert room.game.round == 2
      assert room.game.imposter_id == "p3"
      assert room.game.entry.word == "Bicycle"
      assert room.game.turn_order == ~w(p2 p3 p0 p1)
      assert %{role: "imposter"} = Room.secret_for(room, "p3")
      assert %{role: "crew", word: "Bicycle"} = Room.secret_for(room, "p0")
    end

    test "everything from the last round is cleared" do
      before = result_room()
      {:ok, room} = Room.next_round(before, deal("p3", "Bicycle"))
      game = room.game

      assert game.strokes == []
      assert game.open_stroke == nil
      assert game.votes == %{}
      assert game.accused == nil
      assert game.result == nil
      assert game.turn == nil
      assert game.queue == []
      assert game.turn_n == 0
      assert game.vote_ends_at == nil and game.guess_ends_at == nil and game.next_at == nil
      assert Room.strokes_public(room) == []
      assert Room.to_public(room).result == nil
    end

    test "scores, colours and the no-repeat history carry over" do
      before = result_room()

      {:ok, room} =
        Room.next_round(before, %{
          deal("p3", "Bicycle")
          | imposter_history: ~w(p1 p3),
            used_words: ["Bicycle", "Giraffe"]
        })

      assert room.scores == before.scores
      assert room.scores == %{"p1" => 2}
      assert room.game.colors == before.game.colors
      assert room.game.imposter_history == ~w(p1 p3)
      assert room.game.used_words == ["Bicycle", "Giraffe"]
    end

    test "the new round can be drawn: the reveal ends in a fresh turn order" do
      {:ok, room} = Room.next_round(result_room(), deal("p3", "Bicycle", ~w(p2 p3 p0 p1)))
      {:ok, room} = Room.end_reveal(room, @now, 30_000)

      assert room.phase == :drawing
      assert room.game.turn.player_id == "p2"
      # 4 players on auto: two laps, the first turn already started
      assert room.game.laps == 2

      assert room.game.queue == [
               {1, "p3"},
               {1, "p0"},
               {1, "p1"},
               {2, "p2"},
               {2, "p3"},
               {2, "p0"},
               {2, "p1"}
             ]

      assert room.game.turn.n == 1
    end

    test "a player who left is not in the new round's names" do
      room = Room.remove_player(result_room(), "p3")
      {:ok, room} = Room.next_round(room, deal("p1", "Bicycle", ~w(p0 p1 p2)))
      refute Map.has_key?(room.game.names, "p3")
    end

    test "only after a result" do
      assert {:error, :not_result} = Room.next_round(Room.new("ABCD", "p0"), deal("p1", "x"))
      {:ok, room} = Room.next_round(result_room(), deal("p3", "Bicycle"))
      assert {:error, :not_result} = Room.next_round(room, deal("p2", "Kite"))
    end

    test "the round counter is public" do
      {:ok, room} = Room.next_round(result_room(3), deal("p3", "Bicycle"))
      assert %{round: 2, rounds: 3} = Room.to_public(room)
    end
  end

  describe "the wait after a result" do
    test "the public result says how long until the next round, once the wait has begun" do
      room = result_room()
      assert Room.to_public(room, @now).result.ms_left == nil

      room = put_in(room.game.next_at, @now + 12_000)
      assert Room.to_public(room, @now + 2_000).result.ms_left == 10_000
      assert Room.to_public(room, @now + 99_000).result.ms_left == 0
    end

    test "only the host may skip it, and only at a result" do
      assert :ok = Room.check_can_skip(result_room(), "p0")
      assert {:error, :not_host} = Room.check_can_skip(result_room(), "p2")
      assert {:error, :not_result} = Room.check_can_skip(Room.new("ABCD", "p0"), "p0")
    end
  end

  describe "the end of the game" do
    defp final_room(scores) do
      {:ok, room} = Room.finish_game(%{result_room() | scores: scores})
      room
    end

    test "finish_game moves to the final standings, only from a result" do
      assert final_room(%{}).phase == :final
      assert {:error, :not_result} = Room.finish_game(Room.new("ABCD", "p0"))
      assert {:error, :not_result} = Room.finish_game(final_room(%{}))
    end

    test "the winner is whoever has the top score" do
      public = Room.to_public(final_room(%{"p0" => 2, "p1" => 5, "p2" => 3}))
      assert public.final == %{winner_ids: ["p1"], rounds_played: 1}
    end

    test "a tie shares the win" do
      public = Room.to_public(final_room(%{"p0" => 4, "p1" => 4, "p2" => 1}))
      assert public.final.winner_ids == ["p0", "p1"]
    end

    test "nobody wins a game where nobody scored" do
      assert Room.to_public(final_room(%{})).final.winner_ids == []
      assert Room.to_public(final_room(%{"p0" => 0})).final.winner_ids == []
    end

    test "someone who has left cannot win" do
      {:ok, room} = Room.finish_game(%{result_room() | scores: %{"p0" => 9, "p2" => 3}})
      room = Room.remove_player(room, "p0")
      assert Room.to_public(room).final.winner_ids == []
    end

    test "there are final standings only in the final phase" do
      assert Room.to_public(result_room()).final == nil
      assert Room.to_public(Room.new("ABCD", "p0")).final == nil
    end
  end

  describe "play_again/2" do
    test "back to the lobby, scores wiped, the game forgotten" do
      {:ok, room} = Room.play_again(final_room(%{"p0" => 3, "p1" => 2}), "p0")

      assert room.phase == :lobby
      assert room.game == nil
      assert room.scores == %{}
      assert map_size(room.players) == 4
      assert Enum.all?(Room.to_public(room).players, &(&1.score == 0 and is_binary(&1.color)))
      assert Room.secret_for(room, "p1") == nil
    end

    test "players stay ready, so the host can start straight away" do
      {:ok, room} = Room.play_again(final_room(%{}), "p0")
      assert room.players["p1"].ready?
      assert {:ok, %{phase: :reveal}} = Room.start_game(room, "p0", deal("p2", "Kite"))
    end

    test "a new game starts at round 1 with a clean history" do
      {:ok, room} = Room.play_again(final_room(%{}), "p0")
      {:ok, room} = Room.start_game(room, "p0", deal("p2", "Kite"))
      assert room.game.round == 1
      assert room.game.used_words == ["Kite"]
    end

    test "only the host" do
      assert {:error, :not_host} = Room.play_again(final_room(%{}), "p2")
    end

    test "only when the game is over" do
      assert {:error, :not_finished} = Room.play_again(result_room(), "p0")
      assert {:error, :not_finished} = Room.play_again(Room.new("ABCD", "p0"), "p0")
    end
  end
end
