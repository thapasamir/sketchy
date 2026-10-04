defmodule Backend.SpectatorFlowTest do
  # Latecomers in a real room: they arrive mid-game, watch, and are dealt in at the next round.
  # (config/test.exs: reveal 200ms, turn 1.5s, vote 1.5s, a result stays up 800ms.)
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

  # a started game of `rounds` rounds (1 lap each), at the first drawing turn
  defp started(rounds \\ 2) do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
    {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")
    pids = Map.new([host, p2, p3], fn id -> {id, channel()} end)
    for {id, pid} <- pids, do: {:ok, _} = Rooms.connect(code, id, pid)

    {:ok, _} = Rooms.update_settings(code, host, %{"rounds" => rounds, "laps" => 1})
    Rooms.subscribe(code)
    {:ok, _} = Rooms.set_ready(code, p2, true)
    {:ok, _} = Rooms.set_ready(code, p3, true)
    {:ok, _} = Rooms.start_game(code, host)
    assert_receive {:room_updated, %{phase: :drawing}}, 2000
    flush()
    %{code: code, host: host, players: [host, p2, p3], pids: pids}
  end

  # someone arrives now: joins, and connects as a browser would
  defp latecomer(%{code: code} = room, name \\ "Late") do
    {:ok, %{player_id: id}} = Rooms.join_room(code, name)
    {:ok, _} = Rooms.connect(code, id, channel())
    Map.put(room, :late, id)
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

  # everyone in the round accuses one of the crew: the round ends at once
  defp end_round(%{code: code, players: players}) do
    finish_all_turns(code)
    imposter = state(code).game.imposter_id
    innocent = Enum.find(players, &(&1 != imposter))
    other = Enum.find(players, &(&1 != innocent))

    for voter <- players do
      :ok = Rooms.vote(code, voter, if(voter == innocent, do: other, else: innocent))
    end

    assert state(code).phase == :result
    imposter
  end

  describe "arriving mid-game" do
    test "joining is allowed during the drawing, and the newcomer is a spectator" do
      room = started() |> latecomer()
      assert Room.spectator?(state(room.code), room.late)
    end

    test "they are not part of the round: no card, no turn, no colour" do
      %{code: code, late: late} = started() |> latecomer()
      room = state(code)
      assert Room.secret_for(room, late) == nil
      refute late in room.game.turn_order
      refute Map.has_key?(room.game.colors, late)
    end

    test "they can watch: they are given the picture so far" do
      %{code: code, late: late} = started() |> latecomer()
      drawer = state(code).game.turn.player_id

      :ok =
        Rooms.draw(
          code,
          drawer,
          %{"type" => "start", "id" => "a", "size" => 1, "x" => 0.4, "y" => 0.4},
          self()
        )

      assert [%{id: "a"}] = Room.strokes_public(state(code))
      assert {:ok, _} = Rooms.fetch_member_room(code, late)
    end

    test "they can join in the vote phase, and during the reveal, and at a result too" do
      game = started()
      finish_all_turns(game.code)
      assert state(game.code).phase == :voting
      game = latecomer(game, "InVote")
      assert Room.spectator?(state(game.code), game.late)

      end_round(%{game | code: game.code})
    end

    test "the room still has a limit: spectators count toward 8" do
      %{code: code} = game = started()
      for n <- 1..5, do: latecomer(game, "Late#{n}")
      assert map_size(state(code).players) == 8
      assert {:error, :room_full} = Rooms.join_room(code, "OneTooMany")
    end

    test "names are still unique" do
      %{code: code} = started()
      assert {:error, :name_taken} = Rooms.join_room(code, "host")
    end

    test "a spectator can leave without upsetting the turns" do
      %{code: code, late: late} = started() |> latecomer()
      turn_before = state(code).game.turn

      :ok = Rooms.leave(code, late)

      assert state(code).game.turn == turn_before
      refute Map.has_key?(state(code).players, late)
    end
  end

  describe "while watching" do
    test "they cannot vote, and cannot be voted for" do
      %{code: code, late: late, host: host} = started() |> latecomer()
      finish_all_turns(code)
      assert state(code).phase == :voting

      assert {:error, :spectating} = Rooms.vote(code, late, host)
      assert {:error, :not_a_member} = Rooms.vote(code, host, late)
    end

    test "they do not hold up the vote: it closes when the players have voted" do
      game = started() |> latecomer()
      assert end_round(game) != nil
      assert state(game.code).phase == :result
    end

    test "they earn no points" do
      game = started() |> latecomer()
      end_round(game)
      refute Map.has_key?(state(game.code).scores, game.late)
    end

    test "they can chat during the vote, like anyone (they hold no secret to leak)" do
      %{code: code, late: late} = started() |> latecomer()
      finish_all_turns(code)
      assert state(code).phase == :voting
      flush()

      assert :ok = Rooms.chat(code, late, "I am just watching")
      assert_receive {:chat, %{text: "I am just watching", name: "Late"}}
    end

    test "chat is closed for them while drawing, like everyone" do
      %{code: code, late: late} = started() |> latecomer()
      assert {:error, :chat_closed} = Rooms.chat(code, late, "hi")
    end
  end

  describe "joining in" do
    test "at the next round they are dealt in, with a colour of their own" do
      game = started(3) |> latecomer()
      end_round(game)

      assert_receive {:room_updated, %{phase: :reveal, game: %{round: 2}}}, 3000

      room = state(game.code)
      refute Room.spectator?(room, game.late)
      assert game.late in room.game.turn_order
      assert length(room.game.turn_order) == 4
      colors = Map.values(room.game.colors)
      assert length(colors) == 4 and length(Enum.uniq(colors)) == 4
    end

    test "they then get a card like everyone else" do
      game = started(3) |> latecomer()
      end_round(game)
      assert_receive {:room_updated, %{phase: :reveal, game: %{round: 2}}}, 3000

      secrets = for id <- [game.late | game.players], do: Room.secret_for(state(game.code), id)
      assert Enum.all?(secrets, &(&1 != nil))
      assert Enum.count(secrets, &(&1.role == "imposter")) == 1
    end

    test "and they take their turn drawing" do
      game = started(3) |> latecomer()
      end_round(game)
      assert_receive {:room_updated, %{phase: :drawing, game: %{round: 2}}}, 3000

      # go round the table: the newcomer is in the queue
      seen =
        Stream.repeatedly(fn ->
          room = state(game.code)

          case room do
            %{phase: :drawing, game: %{turn: %{player_id: id}}} ->
              :ok = Rooms.finish_turn(game.code, id)
              id

            _ ->
              nil
          end
        end)
        |> Enum.take_while(& &1)

      assert game.late in seen
    end

    test "they can be the imposter in a later round, and vote in it" do
      game = started(3) |> latecomer()
      end_round(game)
      assert_receive {:room_updated, %{phase: :drawing, game: %{round: 2}}}, 3000
      finish_all_turns(game.code)

      assert state(game.code).phase == :voting
      assert :ok = Rooms.vote(game.code, game.late, hd(game.players))
    end

    test "someone who arrives at the result also joins in at the next round" do
      %{code: code} = game = started(3)
      end_round(game)
      game = latecomer(game, "AtResult")
      assert Room.spectator?(state(code), game.late)

      assert_receive {:room_updated, %{phase: :reveal, game: %{round: 2}}}, 3000
      refute Room.spectator?(state(code), game.late)
    end

    test "after the final, a spectator is a player in the lobby again" do
      %{code: code, host: host} = game = started(2)
      end_round(game)
      assert_receive {:room_updated, %{phase: :drawing, game: %{round: 2}}}, 3000
      game = latecomer(game, "AtTheEnd")
      end_round(%{game | players: Enum.filter(game.players, &(&1 != game.late))})
      assert_receive {:room_updated, %{phase: :final}}, 3000

      assert :ok = Rooms.play_again(code, host)
      room = state(code)
      refute Room.spectator?(room, game.late)
      refute room.players[game.late].ready?
    end
  end

  test "a room that is too small to carry on still ends: spectators count as people here" do
    %{code: code, host: host, pids: pids, players: [_, p2, p3]} = game = started(3)
    game = latecomer(game)
    end_round(game)

    # the two others leave: only the host and the spectator are left, 2 people: not enough to play on
    Process.exit(pids[p2], :kill)
    Process.exit(pids[p3], :kill)

    assert_receive {:room_updated, %{phase: :final}}, 4000
    assert host in Map.keys(state(code).players)
  end
end
