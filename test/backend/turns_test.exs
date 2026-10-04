defmodule Backend.TurnsTest do
  # The turn machinery in a real room process: timers, hand-offs, a drawer who drops.
  # (config/test.exs: reveal 200ms, a turn 1.5s, a vanished drawer is waited for 150ms.)
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.{Room, RoomServer}

  # each player gets their own stand-in "channel" process, so one can be killed on its own
  defp channel do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp new_game do
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
    flush()

    %{code: code, host: host, players: [host, p2, p3], pids: pids}
  end

  # drop every message waiting in the mailbox (the lobby's broadcasts, mostly)
  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  # wait for a broadcast in which someone other than `old` has the pen
  defp await_new_drawer(old, timeout) do
    receive do
      {:room_updated, %{game: %{turn: %{player_id: id}}}} when id != old -> id
      {:room_updated, _same_drawer} -> await_new_drawer(old, timeout)
    after
      timeout -> nil
    end
  end

  # hand the pen on until the drawing is over (3 players on auto = two laps = 6 turns)
  defp finish_all_turns(code) do
    case state(code) do
      %{phase: :drawing, game: %{turn: %{player_id: id}}} ->
        :ok = Rooms.finish_turn(code, id)
        finish_all_turns(code)

      _ ->
        :ok
    end
  end

  defp state(code) do
    {:ok, room} = RoomServer.get_state(code)
    room
  end

  defp drawer(code), do: state(code).game.turn.player_id

  # the next player in line after the current drawer
  defp not_drawer(%{code: code, players: players}), do: Enum.find(players, &(&1 != drawer(code)))

  defp stroke(id), do: %{"type" => "start", "id" => id, "size" => 2, "x" => 0.5, "y" => 0.5}

  test "after the reveal the first player in the turn order has the pen" do
    %{code: code} = game = new_game()
    room = state(code)

    assert room.phase == :drawing
    assert room.game.turn.player_id == hd(room.game.turn_order)
    assert room.game.turn.player_id in game.players
    # 3 players on auto draw twice each: 6 turns, minus the one that has started
    assert room.game.laps == 2
    assert length(room.game.queue) == 5
  end

  test "the drawer's strokes reach the other channels; strangers' are refused" do
    %{code: code} = game = new_game()
    me = drawer(code)

    assert :ok = Rooms.draw(code, me, stroke("a"), self())
    assert_receive {:draw_event, origin, %{type: "start", id: "a", player_id: ^me}}
    assert origin == self()

    assert {:error, :not_your_turn} = Rooms.draw(code, not_drawer(game), stroke("b"), self())
    refute_receive {:draw_event, _, %{id: "b"}}, 50
  end

  test "strokes are kept in the room, so a latecomer or a refresh gets the picture" do
    %{code: code} = new_game()
    me = drawer(code)
    :ok = Rooms.draw(code, me, stroke("a"), self())

    :ok =
      Rooms.draw(code, me, %{"type" => "points", "id" => "a", "points" => [[0.6, 0.6]]}, self())

    assert [%{id: "a", player_id: ^me, points: [[0.5, 0.5], [0.6, 0.6]]}] =
             Room.strokes_public(state(code))
  end

  test "drawing does not re-broadcast the whole room" do
    %{code: code} = new_game()
    :ok = Rooms.draw(code, drawer(code), stroke("a"), self())
    refute_receive {:room_updated, _}, 100
  end

  test "the drawer can end their turn early, and nobody else can" do
    %{code: code} = game = new_game()
    first = drawer(code)

    assert {:error, :not_your_turn} = Rooms.finish_turn(code, not_drawer(game))
    assert :ok = Rooms.finish_turn(code, first)

    assert_receive {:room_updated, %{phase: :drawing, game: %{turn: %{player_id: next}}}}
    refute next == first
    assert drawer(code) == next
  end

  test "when the time runs out the pen passes on by itself" do
    %{code: code} = new_game()
    first = drawer(code)

    assert_receive {:room_updated, %{game: %{turn: %{player_id: next}}}}, 4000
    refute next == first
    assert drawer(code) == next
  end

  test "a stroke still open when the turn ends is closed for everyone" do
    %{code: code} = new_game()
    me = drawer(code)
    :ok = Rooms.draw(code, me, stroke("a"), self())
    flush()

    :ok = Rooms.finish_turn(code, me)

    # origin is nil: this "end" goes to every channel, including the drawer's own
    assert_receive {:draw_event, nil, %{type: "end", id: "a"}}
    assert state(code).game.open_stroke == nil
  end

  test "a stroke that was already finished is not closed twice" do
    %{code: code} = new_game()
    me = drawer(code)
    :ok = Rooms.draw(code, me, stroke("a"), self())
    :ok = Rooms.draw(code, me, %{"type" => "end", "id" => "a"}, self())
    flush()

    :ok = Rooms.finish_turn(code, me)
    refute_receive {:draw_event, _, %{type: "end"}}, 100
  end

  test "an early finish cancels the old timer: the new turn gets its full time" do
    %{code: code} = new_game()
    :ok = Rooms.finish_turn(code, drawer(code))
    second = drawer(code)

    # the first turn's 1.5s timer would fire about now if it had not been cancelled
    Process.sleep(1200)
    assert drawer(code) == second
  end

  test "after the last turn the room moves to voting, with the vote timed instead" do
    %{code: code, pids: _} = new_game()
    room = state(code)

    finish_all_turns(code)

    assert state(code).phase == :voting
    assert state(code).game.turn == nil
    [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
    assert {_token, _timer} = :sys.get_state(pid).phase_timer

    assert {:error, :not_your_turn} =
             Rooms.draw(code, hd(room.game.turn_order), stroke("z"), self())
  end

  test "the picture survives into voting" do
    %{code: code} = new_game()
    :ok = Rooms.draw(code, drawer(code), stroke("a"), self())

    finish_all_turns(code)

    assert [%{id: "a"}] = Room.strokes_public(state(code))
  end

  test "undo takes back the drawer's last stroke and tells the others" do
    %{code: code} = new_game()
    me = drawer(code)
    :ok = Rooms.draw(code, me, stroke("a"), self())

    assert {:ok, %{type: "undo", id: "a"}} = Rooms.undo(code, me, self())
    assert_receive {:draw_event, _, %{type: "undo", id: "a"}}
    assert Room.strokes_public(state(code)) == []
    assert {:error, :nothing_to_undo} = Rooms.undo(code, me, self())
  end

  describe "a drawer who drops" do
    test "the turn moves on soon, not after the whole turn", %{} do
      %{code: code, pids: pids} = new_game()
      first = drawer(code)

      Process.exit(pids[first], :kill)
      assert next = await_new_drawer(first, 1000)
      assert next != first
    end

    test "a quick refresh (they come back in time) keeps the turn, with the time that was left" do
      %{code: code, pids: pids} = new_game()
      first = drawer(code)

      Process.exit(pids[first], :kill)
      Process.sleep(50)
      {:ok, _} = Rooms.connect(code, first, channel())

      # past the 150ms the dropped drawer was given, and well inside the turn's 1.5s
      Process.sleep(300)
      assert drawer(code) == first
      assert state(code).players[first].connected?
    end

    test "someone else dropping does not disturb the turn" do
      %{code: code, pids: pids} = new_game()
      first = drawer(code)
      other = Enum.find(Map.keys(pids), &(&1 != first))

      Process.exit(pids[other], :kill)
      Process.sleep(400)
      assert drawer(code) == first
    end

    test "a player who is away when their turn comes is skipped" do
      %{code: code, pids: pids} = new_game()
      first = drawer(code)

      [_, second, third] = [
        first | state(code).game.queue |> Enum.map(&elem(&1, 1)) |> Enum.take(2)
      ]

      Process.exit(pids[second], :kill)
      # wait for the room to notice before the pen moves
      assert_receive {:room_updated, %{players: %{^second => %{connected?: false}}}}, 1000

      :ok = Rooms.finish_turn(code, first)
      assert drawer(code) == third
    end
  end

  test "a drawer who leaves for good passes the pen on, and has no later turns" do
    %{code: code} = new_game()
    first = drawer(code)

    :ok = Rooms.leave(code, first)

    room = state(code)
    assert room.game.turn.player_id != first
    refute Enum.any?(room.game.queue, fn {_lap, id} -> id == first end)
  end

  test "a non-drawer who leaves is only removed from the queue" do
    %{code: code} = game = new_game()
    first = drawer(code)
    leaver = not_drawer(game)

    :ok = Rooms.leave(code, leaver)

    assert drawer(code) == first
    refute Enum.any?(state(code).game.queue, fn {_lap, id} -> id == leaver end)
  end
end
