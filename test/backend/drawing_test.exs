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

  # 3 connected players in the reveal phase; the game is `rounds` rounds long, `laps` goes each
  defp revealing(rounds \\ 2, laps \\ 1) do
    room =
      Enum.reduce(0..2, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "Player#{&1}"))

    room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
    {:ok, room} = Room.update_settings(room, "p0", %{rounds: rounds, laps: laps})
    {:ok, room} = Room.set_ready(room, "p1", true)
    {:ok, room} = Room.set_ready(room, "p2", true)
    {:ok, room} = Room.start_game(room, "p0", deal())
    room
  end

  # drawing, and it is p2's turn (first in the turn order)
  defp drawing(rounds \\ 2, laps \\ 1) do
    {:ok, room} = Room.end_reveal(revealing(rounds, laps), @now, @turn_ms)
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

  describe "laps" do
    test "two laps: everyone draws twice, in the same order" do
      room = drawing(2, 2)
      assert [room.game.turn.player_id | drawers(room)] == ~w(p2 p0 p1 p2 p0 p1)
    end

    test "one lap: everyone draws once" do
      room = drawing(2, 1)
      assert [room.game.turn.player_id | drawers(room)] == ~w(p2 p0 p1)
    end

    test "the turn says which lap it is, and how many there are" do
      room = drawing(2, 2)
      assert %{lap: 1, laps: 2} = Room.to_public(room, @now).turn

      room = Enum.reduce(1..3, room, fn _, room -> Room.next_turn(room, @now, @turn_ms) end)
      assert %{lap: 2, laps: 2, player_id: "p2"} = Room.to_public(room, @now).turn
    end

    test "every turn has its own number, even when the same player draws twice running" do
      room = drawing(2, 2)
      # the two others are away, so p2 is the only one left to draw, lap after lap
      room = room |> Room.set_connected("p0", false) |> Room.set_connected("p1", false)
      next = Room.next_turn(room, @now, @turn_ms)

      assert next.game.turn.player_id == room.game.turn.player_id
      assert next.game.turn.n == room.game.turn.n + 1
      assert Room.to_public(next, @now).turn.n == Room.to_public(room, @now).turn.n + 1
    end

    test "leaving removes a player from every lap" do
      # p2 is drawing now; with p1 gone the rest of the two laps is p0, then p2 and p0 again
      room = Room.remove_player(drawing(2, 2), "p1")
      assert drawers(room) == ~w(p0 p2 p0)
    end

    test "an away player is skipped in every lap" do
      room = drawing(2, 2) |> Room.set_connected("p0", false)
      assert drawers(room) == ~w(p1 p2 p1)
    end

    test "the laps are fixed when the round starts (the room's setting is not read mid-round)" do
      room = drawing(2, 2)
      assert room.game.laps == 2
    end
  end

  describe "the laps setting" do
    defp players_in_room(n, laps) do
      room = Enum.reduce(1..n, Room.new("ABCD", "p1"), &Room.add_player(&2, "p#{&1}", "N#{&1}"))
      {:ok, room} = Room.update_settings(room, "p1", %{laps: laps})
      room
    end

    test "auto: two laps for 3 or 4 players, one for 5 or more" do
      assert Room.laps_for(players_in_room(3, :auto)) == 2
      assert Room.laps_for(players_in_room(4, :auto)) == 2
      assert Room.laps_for(players_in_room(5, :auto)) == 1
      assert Room.laps_for(players_in_room(8, :auto)) == 1
    end

    test "that keeps a word to about 5 to 8 turns whatever the group size" do
      turns = for n <- 3..8, do: n * Room.laps_for(players_in_room(n, :auto))
      assert turns == [6, 8, 5, 6, 7, 8]
    end

    test "the host can fix it at 1 or 2, whatever the group size" do
      assert Room.laps_for(players_in_room(3, 1)) == 1
      assert Room.laps_for(players_in_room(8, 2)) == 2
    end

    test "it is the default" do
      assert Room.new("ABCD", "p1").settings.laps == :auto
    end

    test "only auto, 1 or 2 are allowed" do
      room = players_in_room(3, :auto)

      for bad <- [0, 3, -1, "2", "auto", nil, 1.5, :three] do
        assert {:error, :invalid_settings} = Room.update_settings(room, "p1", %{laps: bad})
      end

      for good <- [:auto, 1, 2],
          do: assert({:ok, _} = Room.update_settings(room, "p1", %{laps: good}))
    end

    test "the public room says what auto comes to right now" do
      assert Room.to_public(players_in_room(4, :auto)).laps_now == 2
      assert Room.to_public(players_in_room(6, :auto)).laps_now == 1
      assert Room.to_public(players_in_room(6, 2)).laps_now == 2
      assert Room.to_public(players_in_room(4, :auto)).settings.laps == :auto
    end

    test "changing it asks everyone to say ready again" do
      room = players_in_room(3, :auto)
      {:ok, room} = Room.set_ready(room, "p2", true)
      {:ok, room} = Room.update_settings(room, "p1", %{laps: 1})
      refute room.players["p2"].ready?
    end
  end

  describe "colours" do
    test "everyone gets their own colour" do
      colors = drawing().game.colors |> Map.values()
      assert length(colors) == 3
      assert length(Enum.uniq(colors)) == 3
    end

    test "the public player list carries the colours" do
      assert Enum.all?(Room.to_public(drawing()).players, &is_binary(&1.color))
    end

    test "the lobby already shows the colour and shape each person will have, in join order" do
      lobby =
        Enum.reduce(0..2, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "N#{&1}"))

      players = Room.to_public(lobby).players
      assert Enum.map(players, & &1.color) |> Enum.uniq() |> length() == 3
      assert Enum.all?(players, &is_binary(&1.shape))
      assert [%{color: "#ff48b0", shape: "circle"} | _] = players
    end

    test "and nobody changes colour when the game starts" do
      lobby =
        Enum.reduce(0..2, Room.new("ABCD", "p0"), &Room.add_player(&2, "p#{&1}", "N#{&1}"))

      lobby = Enum.reduce(Map.keys(lobby.players), lobby, &Room.set_connected(&2, &1, true))
      {:ok, lobby} = Room.set_ready(lobby, "p1", true)
      {:ok, lobby} = Room.set_ready(lobby, "p2", true)

      before = Room.to_public(lobby).players |> Map.new(&{&1.id, {&1.color, &1.shape}})
      {:ok, started} = Room.start_game(lobby, "p0", deal())
      after_start = Room.to_public(started).players |> Map.new(&{&1.id, {&1.color, &1.shape}})

      assert before == after_start
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

      # and each colour has its own shape, so colour is never the only way to tell people apart
      shapes = Room.to_public(room).players |> Enum.map(& &1.shape)
      assert Enum.all?(shapes, &is_binary/1)
      assert shapes |> Enum.uniq() |> length() == 8
    end

    test "a shape belongs to its colour, and no colour means no shape" do
      assert Room.shape_for("#ff48b0") == "circle"
      assert Room.shape_for("#1fb5b5") == "cross"
      assert Room.shape_for(nil) == nil
      assert Room.shape_for("#000000") == nil
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

      for size <- [0, 6, -1, "2", nil, 2.5],
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

    test "a whole game's drawing is capped, however it is split into strokes" do
      fill = fn room, id ->
        {:ok, room, _} = start(room, "p2", id)

        # 1 + 37 * 80 + 39 = 3,000 points, a full stroke
        room =
          Enum.reduce(1..37, room, fn _, room ->
            {:ok, room, _} = points(room, "p2", id, List.duplicate([0.1, 0.1], 80))
            room
          end)

        {:ok, room, _} = points(room, "p2", id, List.duplicate([0.1, 0.1], 39))
        {:ok, room, _} = finish(room, "p2", id)
        room
      end

      # 20 full strokes is the 60,000-point cap
      room = Enum.reduce(1..20, drawing(), fn i, room -> fill.(room, "s#{i}") end)
      assert {:error, :canvas_full} = start(room, "p2", "one-more")
    end

    test "points come back exactly as they went in" do
      {:ok, room, _} = start(drawing(), "p2", "a", 0.0, 1.0)
      {:ok, room, _} = points(room, "p2", "a", [[0.1235, 0.9999], [1.0, 0.0]])

      assert [%{points: points}] = Room.strokes_public(room)
      assert points == [[0.0, 1.0], [0.1235, 0.9999], [1.0, 0.0]]
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
