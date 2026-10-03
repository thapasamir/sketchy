defmodule Backend.Rooms.DrawingTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.Room

  @now 1_000_000
  @turn_ms 30_000

  defp deal do
    %{
      imposter_id: "p1",
      imposter_history: ["p1"],
      entry: %{category: "Animals", word: "Giraffe", difficulty: "easy", hints: ["tall"]},
      hint: "tall",
      used_words: ["Giraffe"],
      turn_order: ["p2", "p0", "p1"]
    }
  end

  # 3 connected players in the reveal phase; the game is `rounds` rounds long
  defp revealing(rounds \\ 2) do
    room =
      Enum.reduce(0..2, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

    room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
    {:ok, room} = Room.update_settings(room, "p0", %{rounds: rounds})
    {:ok, room} = Room.set_ready(room, "p1", true)
    {:ok, room} = Room.set_ready(room, "p2", true)
    {:ok, room} = Room.start_game(room, "p0", deal())
    room
  end

  # drawing, and it is p2's turn (first in the turn order)
  defp drawing(rounds \\ 2) do
    {:ok, room} = Room.end_reveal(revealing(rounds), @now, @turn_ms)
    room
  end

  defp start(room, who, id, x \\ 0.5, y \\ 0.5, size \\ 2) do
    Room.draw(room, who, %{"type" => "start", "id" => id, "size" => size, "x" => x, "y" => y})
  end

  defp points(room, who, id, pts),
    do: Room.draw(room, who, %{"type" => "points", "id" => id, "points" => pts})

  defp finish(room, who, id), do: Room.draw(room, who, %{"type" => "end", "id" => id})

  defp drawers(room, acc \\ []) do
    case Room.next_turn(room, @now, @turn_ms) do
      %{phase: :voting} -> Enum.reverse(acc)
      next -> drawers(next, [next.game.turn.player_id | acc])
    end
  end

  describe "turns" do
    test "the first turn starts when the reveal ends, with the first player in the order" do
      room = drawing()
      assert room.phase == :drawing
      assert %{player_id: "p2", ends_at: ends_at} = room.game.turn
      assert ends_at == @now + @turn_ms
      assert Room.drawer?(room, "p2")
      refute Room.drawer?(room, "p0")
    end

    test "in a round everyone draws exactly once, in the order dealt" do
      room = drawing()
      assert [room.game.turn.player_id | drawers(room)] == ~w(p2 p0 p1)
    end

    test "how many rounds the game has makes no difference to a round's drawing" do
      assert drawers(drawing(2)) == drawers(drawing(4))
    end

    test "after the last turn the room moves on to voting, with nobody drawing" do
      room = Enum.reduce(1..2, drawing(2), fn _, room -> Room.next_turn(room, @now, @turn_ms) end)
      assert room.phase == :drawing
      room = Room.next_turn(room, @now, @turn_ms)
      assert room.phase == :voting
      assert room.game.turn == nil
      refute Room.drawer?(room, "p2")
    end

    test "a player who is away when their turn comes is skipped" do
      room = drawing(2) |> then(&Room.set_connected(&1, "p0", false))
      assert drawers(room) == ~w(p1)
    end

    test "a player who left is never given a turn" do
      room = Room.remove_player(drawing(2), "p1")
      assert drawers(room) == ~w(p0)
    end

    test "a turn knows how long is left, never below zero" do
      room = drawing()
      assert Room.turn_ms_left(room, @now + 10_000) == 20_000
      assert Room.turn_ms_left(room, @now + 99_999_999) == 0
      assert Room.turn_ms_left(revealing(), @now) == 0
    end

    test "the public view shows whose turn it is and the time left, and no secrets" do
      public = Room.to_public(drawing(), @now + 5_000)
      assert %{player_id: "p2", order: ~w(p2 p0 p1), ms_left: 25_000} = public.turn
      assert %{round: 1, rounds: 2} = public
      assert Room.to_public(revealing()).turn == nil
      refute inspect(public) =~ "Giraffe"
    end
  end

  describe "colours" do
    test "everyone gets their own colour" do
      colors = drawing().game.colors |> Map.values()
      assert length(colors) == 3
      assert length(Enum.uniq(colors)) == 3
    end

    test "the public player list carries the colours (and has none in the lobby)" do
      assert Enum.all?(Room.to_public(drawing()).players, &is_binary(&1.color))
      lobby = Room.new("ABCD", "p0") |> Room.add_player("p0", "A")
      assert [%{color: nil}] = Room.to_public(lobby).players
    end

    test "all 8 seats can have a different colour" do
      room = Enum.reduce(0..7, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "N#{&1}"))
      room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))

      room =
        Enum.reduce(1..7, room, fn i, room ->
          {:ok, room} = Room.set_ready(room, "p#{i}", true)
          room
        end)

      {:ok, room} = Room.start_game(room, "p0", %{deal() | turn_order: Map.keys(room.players)})
      assert room.game.colors |> Map.values() |> Enum.uniq() |> length() == 8
    end
  end

  describe "drawing: who may draw" do
    test "only the current drawer" do
      room = drawing()
      assert {:ok, _room, _event} = start(room, "p2", "a")
      assert {:error, :not_your_turn} = start(room, "p0", "a")
      assert {:error, :not_your_turn} = start(room, "stranger", "a")
    end

    test "not in the reveal, and not once the drawing is over" do
      assert {:error, :not_your_turn} = start(revealing(), "p2", "a")

      over = Enum.reduce(1..6, drawing(2), fn _, room -> Room.next_turn(room, @now, @turn_ms) end)
      assert over.phase == :voting
      assert {:error, :not_your_turn} = start(over, "p2", "a")
    end

    test "when the turn moves on, the old drawer can no longer draw and the new one can" do
      {:ok, room, _} = start(drawing(), "p2", "a")
      room = Room.next_turn(room, @now, @turn_ms)

      assert {:error, :not_your_turn} = points(room, "p2", "a", [[0.1, 0.1]])
      assert {:ok, _room, _} = start(room, "p0", "b")
    end

    test "a stroke left open by the last drawer cannot be continued by the next one" do
      {:ok, room, _} = start(drawing(), "p2", "a")
      room = Room.next_turn(room, @now, @turn_ms)
      assert {:error, :no_such_stroke} = points(room, "p0", "a", [[0.1, 0.1]])
    end
  end

  describe "drawing: strokes" do
    test "a stroke starts with the drawer's colour and the event shown to others is cleaned" do
      room = drawing()
      {:ok, room, event} = start(room, "p2", "a", 0.25, 0.75, 3)
      color = room.game.colors["p2"]

      assert event == %{
               type: "start",
               id: "a",
               player_id: "p2",
               color: color,
               size: 3,
               points: [[0.25, 0.75]]
             }
    end

    test "the colour is the server's choice: a colour sent by the browser is ignored" do
      room = drawing()

      {:ok, _room, event} =
        Room.draw(room, "p2", %{
          "type" => "start",
          "id" => "a",
          "size" => 1,
          "x" => 0,
          "y" => 0,
          "color" => "#000"
        })

      assert event.color == room.game.colors["p2"]
    end

    test "points are appended in order, and shown to others cleaned" do
      {:ok, room, _} = start(drawing(), "p2", "a", 0.1, 0.1)
      {:ok, room, e1} = points(room, "p2", "a", [[0.2, 0.2], [0.3, 0.3]])
      {:ok, room, _} = points(room, "p2", "a", [[0.4, 0.4]])

      assert e1 == %{type: "points", id: "a", points: [[0.2, 0.2], [0.3, 0.3]]}
      assert [%{points: pts}] = Room.strokes_public(room)
      assert pts == [[0.1, 0.1], [0.2, 0.2], [0.3, 0.3], [0.4, 0.4]]
    end

    test "coordinates are clamped into the canvas and rounded" do
      {:ok, _room, event} = start(drawing(), "p2", "a", -5, 99, 1)
      assert event.points == [[0.0, 1.0]]

      {:ok, room, _} = start(drawing(), "p2", "a", 0.5, 0.5)
      {:ok, _room, e} = points(room, "p2", "a", [[0.123456789, 1]])
      assert e.points == [[0.1235, 1.0]]
    end

    test "garbage is refused, and the drawing is unchanged" do
      room = drawing()
      bad_size = fn size -> start(room, "p2", "a", 0.5, 0.5, size) end

      for size <- [0, 4, -1, "2", nil, 2.5],
          do: assert({:error, :invalid_event} = bad_size.(size))

      assert {:error, :invalid_event} = start(room, "p2", "", 0.5, 0.5)
      assert {:error, :invalid_event} = start(room, "p2", String.duplicate("x", 41), 0.5, 0.5)
      assert {:error, :invalid_event} = start(room, "p2", 5, 0.5, 0.5)
      assert {:error, :invalid_event} = start(room, "p2", "a", "left", 0.5)
      assert {:error, :invalid_event} = start(room, "p2", "a", nil, nil)
      assert {:error, :invalid_event} = Room.draw(room, "p2", %{"type" => "nonsense"})
      assert {:error, :invalid_event} = Room.draw(room, "p2", %{})
      assert Room.strokes_public(room) == []
    end

    test "points must be pairs of numbers, in batches of at most 80" do
      {:ok, room, _} = start(drawing(), "p2", "a")
      assert {:error, :invalid_event} = points(room, "p2", "a", [[0.1, 0.1], ["x", 0.2]])
      assert {:error, :invalid_event} = points(room, "p2", "a", [[0.1]])
      assert {:error, :invalid_event} = points(room, "p2", "a", [])
      assert {:error, :invalid_event} = points(room, "p2", "a", "lots")
      assert {:error, :invalid_event} = points(room, "p2", "a", List.duplicate([0.1, 0.1], 81))
      assert {:ok, _room, _} = points(room, "p2", "a", List.duplicate([0.1, 0.1], 80))
    end

    test "one stroke cannot grow forever" do
      {:ok, room, _} = start(drawing(), "p2", "a")

      room =
        Enum.reduce(1..37, room, fn _, room ->
          {:ok, room, _} = points(room, "p2", "a", List.duplicate([0.1, 0.1], 80))
          room
        end)

      assert {:error, :stroke_too_long} = points(room, "p2", "a", List.duplicate([0.1, 0.1], 80))
    end

    test "points need a stroke that was started and is still open" do
      room = drawing()
      assert {:error, :no_such_stroke} = points(room, "p2", "ghost", [[0.1, 0.1]])

      {:ok, room, _} = start(room, "p2", "a")
      assert {:error, :no_such_stroke} = points(room, "p2", "other", [[0.1, 0.1]])

      {:ok, room, %{type: "end"}} = finish(room, "p2", "a")
      assert {:error, :no_such_stroke} = points(room, "p2", "a", [[0.1, 0.1]])
      assert {:error, :no_such_stroke} = finish(room, "p2", "a")
    end

    test "a drawer is limited in strokes per turn, and the next drawer starts fresh" do
      room =
        Enum.reduce(1..30, drawing(), fn i, room ->
          {:ok, room, _} = start(room, "p2", "s#{i}")
          room
        end)

      assert {:error, :too_many_strokes} = start(room, "p2", "one-too-many")

      room = Room.next_turn(room, @now, @turn_ms)
      assert {:ok, _room, _} = start(room, "p0", "mine")
    end
  end

  describe "undo" do
    test "takes back the drawer's last stroke, even one still being drawn" do
      {:ok, room, _} = start(drawing(), "p2", "a")
      {:ok, room, _} = finish(room, "p2", "a")
      {:ok, room, _} = start(room, "p2", "b")

      assert {:ok, room, %{type: "undo", id: "b"}} = Room.undo(room, "p2")
      assert [%{id: "a"}] = Room.strokes_public(room)
      assert {:error, :no_such_stroke} = points(room, "p2", "b", [[0.1, 0.1]])
      assert {:ok, room, %{id: "a"}} = Room.undo(room, "p2")
      assert {:error, :nothing_to_undo} = Room.undo(room, "p2")
    end

    test "never takes back an earlier drawer's work" do
      {:ok, room, _} = start(drawing(), "p2", "a")
      {:ok, room, _} = finish(room, "p2", "a")
      room = Room.next_turn(room, @now, @turn_ms)

      assert {:error, :nothing_to_undo} = Room.undo(room, "p0")
      assert [%{id: "a"}] = Room.strokes_public(room)
    end

    test "only the drawer can undo" do
      {:ok, room, _} = start(drawing(), "p2", "a")
      assert {:error, :not_your_turn} = Room.undo(room, "p0")
    end
  end

  describe "the picture" do
    test "keeps every player's strokes, oldest first, each in its player's colour" do
      {:ok, room, _} = start(drawing(), "p2", "a", 0.1, 0.1)
      {:ok, room, _} = finish(room, "p2", "a")
      room = Room.next_turn(room, @now, @turn_ms)
      {:ok, room, _} = start(room, "p0", "b", 0.9, 0.9)

      assert [first, second] = Room.strokes_public(room)
      assert %{id: "a", player_id: "p2"} = first
      assert %{id: "b", player_id: "p0"} = second
      assert first.color == room.game.colors["p2"]
      assert second.color == room.game.colors["p0"]
      assert first.color != second.color
    end

    test "there is no picture before the game" do
      assert Room.strokes_public(Room.new("ABCD", "p0")) == []
    end

    test "the picture is never part of the public room (it is streamed separately)" do
      {:ok, room, _} = start(drawing(), "p2", "a", 0.123, 0.456)
      refute Map.has_key?(Room.to_public(room), :strokes)
      refute inspect(Room.to_public(room)) =~ "0.123"
    end
  end
end
