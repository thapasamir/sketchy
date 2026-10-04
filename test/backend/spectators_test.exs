defmodule Backend.Rooms.SpectatorsTest do
  # Someone who arrives after the game has started watches, and plays from the next round.
  # These are the pure rules; the flow in a real room is in `spectator_flow_test.exs`.
  use ExUnit.Case, async: true

  alias Backend.Rooms.{Dealer, Room, Voting}

  @now 1_000_000

  defp deal(imposter \\ "p1", order \\ ~w(p0 p1 p2)) do
    %{
      imposter_id: imposter,
      imposter_history: [imposter],
      entry: %{category: "Things", word: "Giraffe", difficulty: "easy", hints: ["tall"]},
      hint: "tall",
      used_words: ["Giraffe"],
      turn_order: order
    }
  end

  # three players, round 1 of 3 in the drawing phase, and a latecomer "Late" (p9) watching
  defp drawing_with_spectator do
    room =
      Enum.reduce(0..2, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

    room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
    {:ok, room} = Room.update_settings(room, "p0", %{laps: 1})
    {:ok, room} = Room.set_ready(room, "p1", true)
    {:ok, room} = Room.set_ready(room, "p2", true)
    {:ok, room} = Room.start_game(room, "p0", deal())
    {:ok, room} = Room.end_reveal(room, @now, 30_000)
    {:ok, room} = Room.join(room, "p9", "Late")
    Room.set_connected(room, "p9", true)
  end

  defp voting_with_spectator do
    drawing_with_spectator()
    |> Stream.iterate(&Room.next_turn(&1, @now, 30_000, 45_000))
    |> Enum.find(&(&1.phase == :voting))
  end

  describe "a spectator is not in the round" do
    test "they are not a contestant, and everyone else is" do
      room = drawing_with_spectator()
      ids = room |> Room.contestants() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      assert ids == ~w(p0 p1 p2)
    end

    test "they are not dealt a card (no word, no imposter role)" do
      room = drawing_with_spectator()
      assert Room.secret_for(room, "p9") == nil
      assert %{role: "crew"} = Room.secret_for(room, "p0")
    end

    test "the public room marks them as spectating" do
      public = Room.to_public(drawing_with_spectator())
      assert Enum.find(public.players, &(&1.id == "p9")).spectator
      refute Enum.find(public.players, &(&1.id == "p0")).spectator
    end

    test "they never get a turn to draw" do
      room = drawing_with_spectator()
      turns = Stream.iterate(room, &Room.next_turn(&1, @now, 30_000)) |> Enum.take(5)
      assert Enum.all?(turns, &(&1.game.turn == nil or &1.game.turn.player_id != "p9"))
      refute Room.drawer?(room, "p9")
    end

    test "they cannot draw" do
      room = drawing_with_spectator()

      assert {:error, :not_your_turn} =
               Room.draw(room, "p9", %{
                 "type" => "start",
                 "id" => "a",
                 "size" => 1,
                 "x" => 0.5,
                 "y" => 0.5
               })
    end

    test "they have no colour, so they cannot be mistaken for a player" do
      room = drawing_with_spectator()
      assert Enum.find(Room.to_public(room).players, &(&1.id == "p9")).color == nil
    end
  end

  describe "voting" do
    test "a spectator cannot vote, and cannot be voted for" do
      room = voting_with_spectator()
      assert {:error, :spectating} = Voting.vote(room, "p9", "p1")
      assert {:error, :not_a_member} = Voting.vote(room, "p0", "p9")
    end

    test "the others can still vote for each other" do
      assert {:ok, _} = Voting.vote(voting_with_spectator(), "p0", "p1")
    end

    test "a spectator does not hold up the vote" do
      room = voting_with_spectator()
      {:ok, room} = Voting.vote(room, "p0", "p1")
      {:ok, room} = Voting.vote(room, "p1", "p2")
      refute Voting.all_voted?(room)
      {:ok, room} = Voting.vote(room, "p2", "p1")
      assert Voting.all_voted?(room)
    end

    test "a spectator is not counted among the voters in the public room" do
      {:ok, room} = Voting.vote(voting_with_spectator(), "p0", "p1")
      assert Room.to_public(room, @now).vote.voted == ["p0"]
    end
  end

  describe "scoring" do
    test "a spectator earns nothing, whoever wins the round" do
      {:ok, room} = Voting.close(voting_with_spectator(), @now, 20_000)
      assert room.phase == :result
      assert room.scores == %{"p1" => 2}

      # the crew caught the imposter instead: points go to the crew who played, not the watcher
      {:ok, room} = Voting.vote(voting_with_spectator(), "p0", "p1")
      {:ok, room} = Voting.vote(room, "p2", "p1")
      {:ok, room} = Voting.close(room, @now, 20_000)
      {:ok, room} = Voting.give_up(room)
      assert room.scores == %{"p0" => 1, "p2" => 1}
      refute Map.has_key?(room.scores, "p9")
    end

    test "the final standings leave them out" do
      {:ok, room} = Voting.close(voting_with_spectator(), @now, 20_000)
      {:ok, room} = Room.finish_game(room)
      assert Room.to_public(room).final.winner_ids == ["p1"]
    end
  end

  describe "the next round: a spectator joins in" do
    defp result_with_spectator do
      {:ok, room} = Voting.close(voting_with_spectator(), @now, 20_000)
      room
    end

    test "promoted players are players, with a colour nobody else has" do
      room = Room.promote_spectators(result_with_spectator())
      refute Room.spectator?(room, "p9")
      colors = Map.values(room.game.colors)
      assert length(colors) == 4
      assert length(Enum.uniq(colors)) == 4
    end

    test "the existing players keep their colours" do
      before = result_with_spectator()
      room = Room.promote_spectators(before)
      for id <- ~w(p0 p1 p2), do: assert(room.game.colors[id] == before.game.colors[id])
    end

    test "they are dealt in: a card, a place in the turn order, and a chance to be the imposter" do
      room = Room.promote_spectators(result_with_spectator())
      deal = Dealer.deal(room)
      assert "p9" in deal.turn_order
      assert length(deal.turn_order) == 4

      {:ok, room} = Room.next_round(room, deal)
      assert Room.secret_for(room, "p9") != nil
    end

    test "before they are promoted, the deal leaves them out" do
      deal = Dealer.deal(result_with_spectator())
      refute "p9" in deal.turn_order
      assert deal.imposter_id != "p9"
    end

    test "they start on no points" do
      room = Room.promote_spectators(result_with_spectator())
      assert Enum.find(Room.to_public(room).players, &(&1.id == "p9")).score == 0
    end

    test "the imposter picked over a few rounds can be the newcomer too" do
      room = Room.promote_spectators(result_with_spectator())

      picks =
        for _ <- 1..200,
            do: Dealer.deal(%{room | game: %{room.game | imposter_history: []}}).imposter_id

      assert "p9" in picks
    end

    test "promoting with no game does nothing" do
      room = Room.new("ABCD", "p0")
      assert Room.promote_spectators(room) == room
    end

    test "promoting when nobody is watching changes nothing" do
      {:ok, room} = Voting.close(voting_with_spectator(), @now, 20_000)
      once = Room.promote_spectators(room)
      assert Room.promote_spectators(once) == once
    end
  end

  describe "playing again" do
    test "someone who was watching becomes a player in the lobby, and has to say they are ready" do
      {:ok, room} = Voting.close(voting_with_spectator(), @now, 20_000)
      {:ok, room} = Room.finish_game(room)
      {:ok, room} = Room.play_again(room, "p0")

      refute Room.spectator?(room, "p9")
      refute room.players["p9"].ready?
      assert room.players["p1"].ready?
    end
  end

  describe "the host" do
    test "when the host leaves, a player is chosen as host before a spectator" do
      room = drawing_with_spectator()

      room = %{
        room
        | players: Map.update!(room.players, "p9", &%{&1 | joined_at: ~U[2000-01-01 00:00:00Z]})
      }

      assert Room.remove_player(room, "p0").host_id in ~w(p1 p2)
    end
  end

  describe "chat" do
    test "a spectator can chat when chat is open (they have no secret to give away)" do
      assert Backend.Rooms.Chat.open?(:voting)
      assert Room.member?(voting_with_spectator(), "p9")
    end
  end
end
