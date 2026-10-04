defmodule Backend.RoundFlowTest do
  # From the end of the drawing to the result, in a real room process.
  # (config/test.exs: the vote lasts 1.5s, the caught imposter's guess 1s.)
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.{Room, RoomServer}

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

  # hand the pen on until the drawing is over, however many laps that takes
  defp finish_all_turns(code) do
    case state(code) do
      %{phase: :drawing, game: %{turn: %{player_id: id}}} ->
        :ok = Rooms.finish_turn(code, id)
        finish_all_turns(code)

      _ ->
        :ok
    end
  end

  # a room that has just finished drawing: it is the voting phase
  defp voting_room do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
    {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")

    pids = Map.new([host, p2, p3], fn id -> {id, channel()} end)
    for {id, pid} <- pids, do: {:ok, _} = Rooms.connect(code, id, pid)

    Rooms.subscribe(code)
    {:ok, _} = Rooms.set_ready(code, p2, true)
    {:ok, _} = Rooms.set_ready(code, p3, true)
    {:ok, _} = Rooms.start_game(code, host)
    assert_receive {:room_updated, %{phase: :drawing}}, 2000

    finish_all_turns(code)

    room = state(code)
    assert room.phase == :voting
    flush()

    imposter = room.game.imposter_id
    crew = Enum.reject([host, p2, p3], &(&1 == imposter))
    %{code: code, players: [host, p2, p3], pids: pids, imposter: imposter, crew: crew}
  end

  # everyone votes for `target`, except `target` themselves, who votes for someone else
  defp everyone_votes_for(%{code: code, players: players}, target) do
    other = Enum.find(players, &(&1 != target))

    for voter <- players do
      :ok = Rooms.vote(code, voter, if(voter == target, do: other, else: target))
    end
  end

  describe "voting" do
    test "the room tells everyone the vote has opened" do
      %{code: code} = voting_room()
      assert %{phase: :voting, game: %{vote_ends_at: at}} = state(code)
      assert at > System.system_time(:millisecond)
    end

    test "when everyone has voted the vote closes at once, not when the time runs out" do
      %{code: code, crew: [a, _b]} = game = voting_room()
      started = System.monotonic_time(:millisecond)

      everyone_votes_for(game, a)

      assert state(code).phase in [:guess, :result]
      assert System.monotonic_time(:millisecond) - started < 500
    end

    test "the vote closes by itself when the time runs out, whoever didn't vote" do
      %{code: code, players: [host | _], imposter: imposter} = game = voting_room()
      # one vote, for someone who is not the imposter: the crew got it wrong
      target = Enum.find(game.players, &(&1 != host and &1 != imposter))
      :ok = Rooms.vote(code, host, target)
      assert state(code).phase == :voting

      assert_receive {:room_updated, %{phase: :result}}, 3000
      assert %{outcome: :escaped, accused: ^target} = state(code).game.result
    end

    test "nobody voting at all ends the round with the imposter escaping" do
      %{code: code, imposter: imposter} = voting_room()
      assert_receive {:room_updated, %{phase: :result}}, 3000
      assert state(code).scores == %{imposter => 2}
    end

    test "a player who is away does not hold the vote up" do
      %{code: code, players: [absent | here], pids: pids} = voting_room()
      Process.exit(pids[absent], :kill)
      assert_receive {:room_updated, %{players: %{^absent => %{connected?: false}}}}, 1000

      [a, b] = here
      :ok = Rooms.vote(code, a, b)
      assert state(code).phase == :voting
      :ok = Rooms.vote(code, b, a)

      assert state(code).phase in [:guess, :result]
    end

    test "someone leaving can be the last one the vote was waiting for" do
      %{code: code, players: [a, b, c]} = voting_room()
      :ok = Rooms.vote(code, a, b)
      :ok = Rooms.vote(code, b, a)
      assert state(code).phase == :voting

      :ok = Rooms.leave(code, c)
      assert state(code).phase in [:guess, :result]
    end

    test "refusals" do
      %{code: code, players: [a, b, _]} = game = voting_room()
      assert {:error, :cannot_vote_self} = Rooms.vote(code, a, a)
      assert {:error, :not_a_member} = Rooms.vote(code, a, "ghost")
      assert {:error, :not_a_member} = Rooms.vote(code, "ghost", a)
      assert {:error, :not_guessing} = Rooms.guess(code, game.imposter, "anything")
      assert :ok = Rooms.vote(code, a, b)
    end

    test "a vote can be changed until the vote closes" do
      %{code: code, players: [a, b, c]} = voting_room()
      :ok = Rooms.vote(code, a, b)
      :ok = Rooms.vote(code, a, c)
      assert state(code).game.votes == %{a => c}
    end

    test "nobody can vote outside the vote" do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      assert {:error, :not_voting} = Rooms.vote(code, host, host)
    end
  end

  describe "catching the imposter" do
    test "accusing a crew member lets the imposter off, at once, with 2 points" do
      %{code: code, crew: [innocent, _], imposter: imposter} = game = voting_room()
      everyone_votes_for(game, innocent)

      room = state(code)
      assert room.phase == :result
      assert %{outcome: :escaped, accused: ^innocent, imposter_id: ^imposter} = room.game.result
      assert room.scores == %{imposter => 2}
    end

    test "accusing the imposter gives them a guess, and nobody else can make it" do
      %{code: code, imposter: imposter, crew: [crew | _]} = game = voting_room()
      everyone_votes_for(game, imposter)

      assert state(code).phase == :guess
      assert {:error, :not_imposter} = Rooms.guess(code, crew, state(code).game.entry.word)
      assert state(code).phase == :guess
    end

    test "a right guess: the imposter gets a point, the crew too" do
      %{code: code, imposter: imposter, crew: crew} = game = voting_room()
      everyone_votes_for(game, imposter)
      word = state(code).game.entry.word

      assert :ok = Rooms.guess(code, imposter, String.upcase(word))

      room = state(code)
      assert room.phase == :result
      assert %{outcome: :guessed} = room.game.result
      assert room.scores == Map.new(crew, &{&1, 1}) |> Map.put(imposter, 1)
    end

    test "a wrong guess: the imposter stays caught" do
      %{code: code, imposter: imposter, crew: crew} = game = voting_room()
      everyone_votes_for(game, imposter)

      assert :ok = Rooms.guess(code, imposter, "definitely not it")

      room = state(code)
      assert %{outcome: :caught, guess: "definitely not it"} = room.game.result
      assert room.scores == Map.new(crew, &{&1, 1})
    end

    test "there is one guess only" do
      %{code: code, imposter: imposter} = game = voting_room()
      everyone_votes_for(game, imposter)
      :ok = Rooms.guess(code, imposter, "nope")
      assert {:error, :not_guessing} = Rooms.guess(code, imposter, state(code).game.entry.word)
      assert state(code).game.result.outcome == :caught
    end

    test "a blank guess is refused and the imposter can still guess" do
      %{code: code, imposter: imposter} = game = voting_room()
      everyone_votes_for(game, imposter)

      assert {:error, :invalid_guess} = Rooms.guess(code, imposter, "   ")
      assert state(code).phase == :guess
      assert :ok = Rooms.guess(code, imposter, "something")
    end

    test "no guess in time: the imposter stays caught" do
      %{code: code, imposter: imposter} = game = voting_room()
      everyone_votes_for(game, imposter)
      flush()

      assert_receive {:room_updated, %{phase: :result}}, 3000
      assert %{outcome: :caught, guess: nil} = state(code).game.result
    end

    test "when the imposter leaves while everyone is voting, the round ends at once and the crew win" do
      %{code: code, imposter: imposter, crew: [a, b]} = voting_room()
      :ok = Rooms.vote(code, a, b)

      :ok = Rooms.leave(code, imposter)

      room = state(code)
      assert room.phase == :result
      assert %{outcome: :imposter_left} = room.game.result
      assert room.scores == %{a => 1, b => 1}
    end
  end

  describe "timers" do
    # After a result the room runs its own "next round" timer; what matters is that the vote and
    # guess timers that were running before it can no longer fire.
    test "closing early cancels the vote timer: it does nothing later" do
      %{code: code, crew: [innocent, _]} = game = voting_room()
      everyone_votes_for(game, innocent)
      assert state(code).phase == :result

      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      # past the 1.5s the vote would have lasted: the room has moved on cleanly, and is alive
      Process.sleep(1700)
      assert Process.alive?(pid)
      assert state(code).phase in [:reveal, :drawing]
    end

    test "a guess cancels the guess timer" do
      %{code: code, imposter: imposter} = game = voting_room()
      everyone_votes_for(game, imposter)
      :ok = Rooms.guess(code, imposter, "nope")

      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      # past the 1s the guess would have lasted
      Process.sleep(1200)
      assert Process.alive?(pid)
      assert state(code).phase in [:reveal, :drawing]
    end
  end

  describe "the result" do
    test "reveals the imposter and the word to everyone, only at the end" do
      %{code: code, imposter: imposter} = game = voting_room()
      before_result = Room.to_public(state(code)) |> inspect()
      refute before_result =~ state(code).game.entry.word

      everyone_votes_for(game, hd(game.crew))

      public = Room.to_public(state(code))
      assert public.phase == :result
      assert public.result.imposter_id == imposter
      assert public.result.word == state(code).game.entry.word
    end

    test "the drawing is still there to look at" do
      %{code: code} = game = voting_room()
      everyone_votes_for(game, hd(game.crew))
      assert state(code).phase == :result
      assert is_list(Room.strokes_public(state(code)))
    end
  end
end
