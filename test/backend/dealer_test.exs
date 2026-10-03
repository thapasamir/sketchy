defmodule Backend.Rooms.DealerTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.{Dealer, Room}

  defp room(connected: connected) do
    room = Room.new("ABCD", "p0")

    Enum.reduce(0..3, room, fn i, room ->
      room
      |> Room.add_player("p#{i}", "Player#{i}")
      |> Room.set_connected("p#{i}", "p#{i}" in connected)
    end)
  end

  test "deals one imposter, a word, and one of that word's hints" do
    deal = Dealer.deal(room(connected: ["p0", "p1", "p2", "p3"]))

    assert deal.imposter_id in ["p0", "p1", "p2", "p3"]
    assert deal.hint in deal.entry.hints
    assert deal.used_words == [deal.entry.word]
    assert deal.imposter_history == [deal.imposter_id]
  end

  test "an away player is never made the imposter" do
    for _ <- 1..200 do
      assert Dealer.deal(room(connected: ["p0", "p1", "p2"])).imposter_id != "p3"
    end
  end

  test "later rounds don't repeat the imposter or the word" do
    first_room = room(connected: ["p0", "p1", "p2", "p3"])
    first = Dealer.deal(first_room)
    game = %{imposter_history: first.imposter_history, used_words: first.used_words}

    for _ <- 1..100 do
      next = Dealer.deal(%{first_room | game: game})
      assert next.imposter_id != first.imposter_id
      assert next.entry.word != first.entry.word
    end
  end
end
