defmodule Backend.Rooms.VotingTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.{Room, Voting}

  @now 1_000_000
  @vote_ms 30_000
  @guess_ms 20_000

  # 4 connected players: p0 (host), p1 (the imposter), p2, p3. The word is "Giraffe".
  defp drawing do
    room =
      Enum.reduce(0..3, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

    room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))

    room =
      Enum.reduce(1..3, room, fn i, room ->
        {:ok, room} = Room.set_ready(room, "p#{i}", true)
        room
      end)

    deal = %{
      imposter_id: "p1",
      imposter_history: ["p1"],
      entry: %{category: "Animals", word: "Giraffe", difficulty: "easy", hints: ["tall"]},
      hint: "tall",
      used_words: ["Giraffe"],
      turn_order: ["p0", "p1", "p2", "p3"]
    }

    {:ok, room} = Room.start_game(room, "p0", deal)
    {:ok, room} = Room.end_reveal(room, @now, 30_000)
    room
  end

  defp voting do
    drawing()
    |> Stream.iterate(&Room.next_turn(&1, @now, 30_000, @vote_ms))
    |> Enum.find(&(&1.phase == :voting))
  end

  defp votes(room, pairs) do
    Enum.reduce(pairs, room, fn {voter, target}, room ->
      {:ok, room} = Voting.vote(room, to_string(voter), target)
      room
    end)
  end

  # the imposter (p1) is caught and it is time to guess
  defp guessing do
    {:ok, room} = voting() |> votes(p0: "p1", p2: "p1", p3: "p1") |> Voting.close(@now, @guess_ms)
    room
  end

  describe "opening the vote" do
    test "after the last turn nobody is drawing and the vote is open and timed" do
      room = voting()
      assert room.phase == :voting
      assert room.game.turn == nil
      assert room.game.votes == %{}
      assert %{ms_left: @vote_ms, voted: []} = Room.to_public(room, @now).vote
    end

    test "the time left counts down and never goes below zero" do
      assert Room.to_public(voting(), @now + 10_000).vote.ms_left == 20_000
      assert Room.to_public(voting(), @now + 999_999).vote.ms_left == 0
    end
  end

  describe "voting" do
    test "records a vote, and a new vote replaces the old one" do
      room = voting() |> votes(p0: "p2")
      assert Voting.my_vote(room, "p0") == "p2"
      room = votes(room, p0: "p3")
      assert Voting.my_vote(room, "p0") == "p3"
      assert map_size(room.game.votes) == 1
    end

    test "the imposter votes like everyone else" do
      assert {:ok, _} = Voting.vote(voting(), "p1", "p2")
    end

    test "you cannot vote for yourself" do
      assert {:error, :cannot_vote_self} = Voting.vote(voting(), "p0", "p0")
    end

    test "only for someone who is in the room, and only by someone who is" do
      assert {:error, :not_a_member} = Voting.vote(voting(), "p0", "ghost")
      assert {:error, :not_a_member} = Voting.vote(voting(), "ghost", "p0")
      assert {:error, :not_a_member} = Voting.vote(voting(), "p0", nil)
      assert {:error, :not_a_member} = Voting.vote(voting(), "p0", 42)
    end

    test "only while voting is open" do
      assert {:error, :not_voting} = Voting.vote(drawing(), "p0", "p1")
      assert {:error, :not_voting} = Voting.vote(guessing(), "p0", "p1")
      assert {:error, :not_voting} = Voting.vote(Room.new("ABCD", "p0"), "p0", "p1")
    end

    test "you can know your own vote, and only during the vote" do
      room = voting() |> votes(p0: "p2")
      assert Voting.my_vote(room, "p0") == "p2"
      assert Voting.my_vote(room, "p3") == nil
      assert Voting.my_vote(guessing(), "p0") == nil
      assert Voting.my_vote(drawing(), "p0") == nil
    end

    test "everyone can see WHO has voted, never FOR whom" do
      room = voting() |> votes(p0: "p1", p2: "p1")
      assert %{voted: voted} = Room.to_public(room, @now).vote
      assert Enum.sort(voted) == ["p0", "p2"]
      refute Map.has_key?(Room.to_public(room, @now).vote, :votes)
      refute inspect(Room.to_public(room, @now).vote) =~ "target"
    end
  end

  describe "has everyone voted?" do
    test "not until every connected player has" do
      room = voting() |> votes(p0: "p1", p1: "p2", p2: "p1")
      refute Voting.all_voted?(room)
      assert room |> votes(p3: "p1") |> Voting.all_voted?()
    end

    test "a player who is away does not hold the vote up" do
      room = voting() |> Room.set_connected("p3", false) |> votes(p0: "p1", p1: "p2", p2: "p1")
      assert Voting.all_voted?(room)
    end

    test "nobody connected is not 'everyone voted'" do
      room = Enum.reduce(0..3, voting(), &Room.set_connected(&2, "p#{&1}", false))
      refute Voting.all_voted?(room)
    end

    test "false outside the vote" do
      refute Voting.all_voted?(drawing())
      refute Voting.all_voted?(guessing())
    end
  end

  describe "closing the vote" do
    test "the most votes is accused; if that is the imposter they get to guess" do
      {:ok, room} =
        voting() |> votes(p0: "p1", p2: "p1", p3: "p2") |> Voting.close(@now, @guess_ms)

      assert room.phase == :guess
      assert room.game.accused == "p1"
      assert %{ms_left: @guess_ms, guesser_id: "p1"} = Room.to_public(room, @now).guess
    end

    test "if the crew accuses one of their own, the imposter has got away" do
      {:ok, room} =
        voting() |> votes(p0: "p2", p1: "p2", p3: "p2") |> Voting.close(@now, @guess_ms)

      assert room.phase == :result
      assert %{outcome: :escaped, accused: "p2"} = room.game.result
      assert room.scores == %{"p1" => 2}
    end

    test "a tie accuses nobody, and the imposter gets away" do
      {:ok, room} =
        voting() |> votes(p0: "p1", p2: "p1", p1: "p2", p3: "p2") |> Voting.close(@now, @guess_ms)

      assert room.phase == :result
      assert %{outcome: :escaped, accused: nil} = room.game.result
    end

    test "nobody voting is nobody accused" do
      {:ok, room} = Voting.close(voting(), @now, @guess_ms)
      assert %{outcome: :escaped, accused: nil, votes: votes} = room.game.result
      assert votes == %{}
    end

    test "a lone vote is enough when nobody else voted" do
      {:ok, room} = voting() |> votes(p2: "p1") |> Voting.close(@now, @guess_ms)
      assert room.phase == :guess
    end

    test "if the imposter has left, the crew wins" do
      room = voting() |> Room.remove_player("p1") |> votes(p0: "p2", p2: "p3")
      {:ok, room} = Voting.close(room, @now, @guess_ms)

      assert room.phase == :result
      assert %{outcome: :imposter_left} = room.game.result
      assert room.scores == %{"p0" => 1, "p2" => 1, "p3" => 1}
    end

    test "only an open vote can be closed" do
      assert {:error, :not_voting} = Voting.close(drawing(), @now, @guess_ms)
      assert {:error, :not_voting} = Voting.close(guessing(), @now, @guess_ms)
    end
  end

  describe "the caught imposter's guess" do
    test "the right word wins them a point, and the crew still scores for the catch" do
      {:ok, room} = Voting.guess(guessing(), "p1", "Giraffe")
      assert room.phase == :result
      assert %{outcome: :guessed, guess: "Giraffe"} = room.game.result
      assert room.scores == %{"p0" => 1, "p2" => 1, "p3" => 1, "p1" => 1}
    end

    test "the guess is forgiving: case, spacing, a small typo" do
      for guess <- ["giraffe", "  GIRAFFE  ", "the giraffe", "girafe"] do
        assert {:ok, %{game: %{result: %{outcome: :guessed}}}} =
                 Voting.guess(guessing(), "p1", guess)
      end
    end

    test "a wrong word: the imposter stays caught, the crew scores" do
      {:ok, room} = Voting.guess(guessing(), "p1", "Elephant")
      assert %{outcome: :caught, guess: "Elephant"} = room.game.result
      assert room.scores == %{"p0" => 1, "p2" => 1, "p3" => 1}
    end

    test "only the imposter can guess" do
      assert {:error, :not_imposter} = Voting.guess(guessing(), "p0", "Giraffe")
      assert {:error, :not_imposter} = Voting.guess(guessing(), "ghost", "Giraffe")
    end

    test "blank, huge or non-text guesses are refused and cost nothing" do
      room = guessing()
      assert {:error, :invalid_guess} = Voting.guess(room, "p1", "   ")
      assert {:error, :invalid_guess} = Voting.guess(room, "p1", String.duplicate("a", 100))
      assert {:error, :invalid_guess} = Voting.guess(room, "p1", nil)
      assert room.phase == :guess
    end

    test "there is only one guess: after it, the round is over" do
      {:ok, room} = Voting.guess(guessing(), "p1", "Elephant")
      assert {:error, :not_guessing} = Voting.guess(room, "p1", "Giraffe")
    end

    test "no guessing before the imposter is caught" do
      assert {:error, :not_guessing} = Voting.guess(voting(), "p1", "Giraffe")
      assert {:error, :not_guessing} = Voting.guess(drawing(), "p1", "Giraffe")
    end

    test "running out of time leaves them caught, with no guess" do
      {:ok, room} = Voting.give_up(guessing())
      assert %{outcome: :caught, guess: nil} = room.game.result
      assert room.scores == %{"p0" => 1, "p2" => 1, "p3" => 1}
      assert {:error, :not_guessing} = Voting.give_up(room)
    end
  end

  describe "scores" do
    test "points are added to what players already have" do
      room = %{guessing() | scores: %{"p0" => 5, "p1" => 2}}
      {:ok, room} = Voting.guess(room, "p1", "Giraffe")
      assert room.scores == %{"p0" => 6, "p1" => 3, "p2" => 1, "p3" => 1}
    end

    test "the public player list carries scores (zero if none yet)" do
      {:ok, room} = Voting.guess(guessing(), "p1", "Elephant")
      scores = Map.new(Room.to_public(room).players, &{&1.id, &1.score})
      assert scores == %{"p0" => 1, "p1" => 0, "p2" => 1, "p3" => 1}
    end
  end

  describe "the result" do
    test "shows everyone what happened: who, the word, the votes, the points" do
      {:ok, room} =
        voting() |> votes(p0: "p1", p2: "p1", p3: "p2") |> Voting.close(@now, @guess_ms)

      {:ok, room} = Voting.guess(room, "p1", "Elephant")
      result = Room.to_public(room).result

      assert result.imposter_id == "p1"
      assert result.word == "Giraffe"
      assert result.category == "Animals"
      assert result.outcome == :caught
      assert result.accused == "p1"
      assert result.votes == %{"p0" => "p1", "p2" => "p1", "p3" => "p2"}
      assert result.tally == %{"p1" => 2, "p2" => 1}
      assert result.names["p1"] == "Player1"
      assert result.points == %{"p0" => 1, "p2" => 1, "p3" => 1}
    end

    test "a player who left is still named in the result" do
      room = voting() |> votes(p0: "p1", p2: "p1", p3: "p1")
      {:ok, room} = Voting.close(room, @now, @guess_ms)
      room = Room.remove_player(room, "p3")
      {:ok, room} = Voting.give_up(room)
      assert Room.to_public(room).result.names["p3"] == "Player3"
    end
  end

  describe "keeping the secret until the end" do
    test "while voting, the public room has neither the word nor who the imposter is" do
      room = voting() |> votes(p0: "p1")
      public = inspect(Room.to_public(room, @now))
      refute public =~ "Giraffe"
      refute public =~ "imposter"
      assert Room.to_public(room, @now).result == nil
      assert Room.to_public(room, @now).guess == nil
    end

    test "while the imposter guesses, the word is still hidden" do
      public = guessing() |> Room.to_public(@now) |> inspect()
      refute public =~ "Giraffe"
      assert Room.to_public(guessing(), @now).result == nil
    end

    test "the vote and guess details exist only in their own phase" do
      assert Room.to_public(drawing(), @now) |> Map.take([:vote, :guess, :result]) == %{
               vote: nil,
               guess: nil,
               result: nil
             }

      assert Room.to_public(guessing(), @now).vote == nil
    end
  end

  describe "someone leaving mid-vote" do
    test "their vote, and votes for them, stop counting" do
      room = voting() |> votes(p0: "p3", p2: "p3", p3: "p1", p1: "p0")
      room = Room.remove_player(room, "p3")

      assert room.game.votes == %{"p1" => "p0"}
    end
  end
end
