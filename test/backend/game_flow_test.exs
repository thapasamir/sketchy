defmodule Backend.GameFlowTest do
  # Whole games in a real room process: round after round, the final, and playing again.
  # (config/test.exs: reveal 200ms, a turn 1.5s, vote 1.5s, guess 1s, a result stays up 800ms.)
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

  # a started game of `rounds` rounds, at the first drawing turn
  defp new_game(rounds) do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
    {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")

    pids = Map.new([host, p2, p3], fn id -> {id, channel()} end)
    for {id, pid} <- pids, do: {:ok, _} = Rooms.connect(code, id, pid)

    # settings first: changing them clears everyone's "ready"
    {:ok, _} = Rooms.update_settings(code, host, %{"rounds" => rounds})
    Rooms.subscribe(code)
    {:ok, _} = Rooms.set_ready(code, p2, true)
    {:ok, _} = Rooms.set_ready(code, p3, true)
    {:ok, _} = Rooms.start_game(code, host)
    assert_receive {:room_updated, %{phase: :drawing}}, 2000
    flush()

    %{code: code, host: host, players: [host, p2, p3], pids: pids}
  end

  # everyone hands the pen on, then the crew accuses one of their own: the round ends at once
  # (the imposter gets away: +2 for them). Anyone who has dropped is skipped, as in a real game.
  defp play_round(%{code: code}) do
    finish_all_turns(code)

    room = state(code)
    imposter = room.game.imposter_id
    here = for {id, %{connected?: true}} <- room.players, do: id
    innocent = Enum.find(here, &(&1 != imposter))
    other = Enum.find(here, &(&1 != innocent))

    for voter <- here do
      :ok = Rooms.vote(code, voter, if(voter == innocent, do: other, else: innocent))
    end

    assert state(code).phase == :result
    imposter
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

  defp await_round(n),
    do: assert_receive({:room_updated, %{phase: :reveal, game: %{round: ^n}}}, 3000)

  # (old broadcasts pile up in the mailbox, so match the round's own message)
  defp await_drawing(n),
    do: assert_receive({:room_updated, %{phase: :drawing, game: %{round: ^n}}}, 3000)

  test "a game starts at round 1 of however many the setting says" do
    %{code: code} = new_game(2)
    assert state(code).game.round == 1
    assert state(code).settings.rounds == 2
  end

  describe "going from round to round" do
    test "the next round starts by itself when the result has been shown" do
      game = new_game(3)
      play_round(game)
      assert state(game.code).phase == :result

      await_round(2)
      assert state(game.code).phase == :reveal
    end

    test "a new word, a clean canvas, a new vote, and the scores kept" do
      game = new_game(3)
      code = game.code

      Rooms.draw(
        code,
        state(code).game.turn.player_id,
        %{"type" => "start", "id" => "a", "size" => 2, "x" => 0.5, "y" => 0.5},
        self()
      )

      first_word = state(code).game.entry.word
      imposter1 = play_round(game)
      scores = state(code).scores
      assert scores == %{imposter1 => 2}

      await_round(2)
      room = state(code)
      assert room.game.entry.word != first_word
      assert Room.strokes_public(room) == []
      assert room.game.votes == %{}
      assert room.game.result == nil
      assert room.scores == scores
    end

    test "the imposter is never the same player two rounds running" do
      game = new_game(4)

      imposters =
        for round <- 1..3 do
          imposter = play_round(game)

          if round < 3 do
            await_round(round + 1)
            await_drawing(round + 1)
          end

          imposter
        end

      assert imposters |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a != b end)
    end

    test "the new round has its own drawing order and can be drawn in" do
      game = new_game(3)
      play_round(game)
      await_round(2)
      await_drawing(2)

      room = state(game.code)
      drawer = room.game.turn.player_id
      assert room.game.round == 2

      assert :ok =
               Rooms.draw(
                 game.code,
                 drawer,
                 %{"type" => "start", "id" => "r2", "size" => 1, "x" => 0.2, "y" => 0.2},
                 self()
               )

      assert [%{id: "r2"}] = Room.strokes_public(state(game.code))
    end

    test "each round everyone is dealt a secret again" do
      game = new_game(3)
      play_round(game)
      await_round(2)
      room = state(game.code)

      secrets = for id <- game.players, do: Room.secret_for(room, id)
      assert Enum.count(secrets, &(&1.role == "imposter")) == 1
    end

    test "the host can skip the wait" do
      game = new_game(3)
      play_round(game)
      started = System.monotonic_time(:millisecond)

      assert :ok = Rooms.next_round(game.code, game.host)

      assert state(game.code).phase == :reveal
      assert state(game.code).game.round == 2
      assert System.monotonic_time(:millisecond) - started < 500
    end

    test "skipping does not make the old timer start a second extra round later" do
      game = new_game(4)
      play_round(game)
      :ok = Rooms.next_round(game.code, game.host)

      # the 800ms result timer would have fired in here
      Process.sleep(1000)
      assert state(game.code).game.round == 2
    end

    test "nobody else can skip, and nobody can skip outside a result" do
      game = new_game(3)
      assert {:error, :not_result} = Rooms.next_round(game.code, game.host)

      play_round(game)
      [_, p2, _] = game.players
      assert {:error, :not_host} = Rooms.next_round(game.code, p2)
      assert state(game.code).phase == :result
    end

    test "too few players left to carry on: it ends there" do
      game = new_game(4)
      [_, p2, p3] = game.players
      play_round(game)

      Process.exit(game.pids[p2], :kill)
      Process.exit(game.pids[p3], :kill)

      assert_receive {:room_updated, %{phase: :final}}, 3000
    end
  end

  describe "the end of the game" do
    test "after the last round's result come the final standings" do
      game = new_game(2)
      i1 = play_round(game)
      await_round(2)
      await_drawing(2)
      i2 = play_round(game)

      assert_receive {:room_updated, %{phase: :final}}, 3000
      room = state(game.code)

      assert room.phase == :final
      assert room.game.round == 2
      expected = Enum.frequencies([i1, i2]) |> Map.new(fn {id, n} -> {id, n * 2} end)
      assert room.scores == expected
      assert Room.to_public(room).final.rounds_played == 2
    end

    test "no timer is left running at the final" do
      game = new_game(2)
      play_round(game)
      await_round(2)
      await_drawing(2)
      play_round(game)
      assert_receive {:room_updated, %{phase: :final}}, 3000

      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, game.code)
      assert :sys.get_state(pid).phase_timer == nil
    end

    test "nothing can be done to the finished game except playing again" do
      game = new_game(2)
      play_round(game)
      await_round(2)
      await_drawing(2)
      play_round(game)
      assert_receive {:room_updated, %{phase: :final}}, 3000

      assert {:error, :not_result} = Rooms.next_round(game.code, game.host)

      assert {:error, :not_voting} = Rooms.vote(game.code, game.host, hd(tl(game.players)))

      assert {:error, :not_your_turn} =
               Rooms.draw(
                 game.code,
                 game.host,
                 %{"type" => "start", "id" => "x", "size" => 1, "x" => 0, "y" => 0},
                 self()
               )
    end
  end

  describe "playing again" do
    defp finished_game do
      game = new_game(2)
      play_round(game)
      await_round(2)
      await_drawing(2)
      play_round(game)
      assert_receive {:room_updated, %{phase: :final}}, 3000
      flush()
      game
    end

    test "the host takes everyone back to the lobby with fresh scores" do
      game = finished_game()
      assert :ok = Rooms.play_again(game.code, game.host)

      room = state(game.code)
      assert room.phase == :lobby
      assert room.game == nil
      assert room.scores == %{}
      assert map_size(room.players) == 3
      assert_receive {:room_updated, %{phase: :lobby}}
    end

    test "only the host, and only when the game is over" do
      game = new_game(2)
      assert {:error, :not_finished} = Rooms.play_again(game.code, game.host)

      game = finished_game()
      [_, p2, _] = game.players
      assert {:error, :not_host} = Rooms.play_again(game.code, p2)
      assert state(game.code).phase == :final
    end

    test "players are still ready, so another game can start at once, from round 1" do
      game = finished_game()
      :ok = Rooms.play_again(game.code, game.host)

      assert {:ok, _} = Rooms.start_game(game.code, game.host)
      assert_receive {:room_updated, %{phase: :drawing}}, 2000
      assert state(game.code).game.round == 1
    end

    test "the new game's word history starts again too" do
      game = finished_game()
      :ok = Rooms.play_again(game.code, game.host)
      {:ok, _} = Rooms.start_game(game.code, game.host)

      assert length(state(game.code).game.used_words) == 1
    end

    test "someone who dropped during the game has the usual grace period, then is removed" do
      game = new_game(2)
      [_, p2, _] = game.players
      play_round(game)
      await_round(2)
      await_drawing(2)
      Process.exit(game.pids[p2], :kill)
      assert_receive {:room_updated, %{players: %{^p2 => %{connected?: false}}}}, 1000
      play_round(game)
      assert_receive {:room_updated, %{phase: :final}}, 3000

      :ok = Rooms.play_again(game.code, game.host)
      assert map_size(state(game.code).players) == 3

      # the test grace period is 300ms
      assert_receive {:room_updated, %{players: players}} when map_size(players) == 2, 2000
      refute Map.has_key?(state(game.code).players, p2)
    end

    test "the lobby works again: settings can be changed" do
      game = finished_game()
      :ok = Rooms.play_again(game.code, game.host)
      assert {:ok, _} = Rooms.update_settings(game.code, game.host, %{"rounds" => 4})
      assert state(game.code).settings.rounds == 4
    end
  end
end
