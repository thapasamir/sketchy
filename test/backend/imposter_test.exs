defmodule Backend.Rooms.ImposterTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.Imposter

  @players ["a", "b", "c", "d", "e"]

  # run n rounds the way a room does: feed each pick's history into the next one
  defp rounds(candidates, n, history \\ []) do
    {picks, _history} =
      Enum.map_reduce(1..n, history, fn _, history -> Imposter.pick(candidates, history) end)

    picks
  end

  test "in a full cycle everyone is imposter exactly once" do
    for _ <- 1..200 do
      assert Enum.sort(rounds(@players, 5)) == Enum.sort(@players)
    end
  end

  test "the same person is never imposter two rounds in a row, even across cycles" do
    for _ <- 1..200 do
      picks = rounds(@players, 40)
      assert Enum.all?(Enum.chunk_every(picks, 2, 1, :discard), fn [x, y] -> x != y end)
    end
  end

  test "every cycle is a fresh shuffle: each player gets exactly one turn per 5 rounds" do
    for _ <- 1..100 do
      picks = rounds(@players, 25)
      assert picks |> Enum.chunk_every(5) |> Enum.all?(&(Enum.sort(&1) == Enum.sort(@players)))
    end
  end

  test "the first pick is uniformly random (no favorite)" do
    counts =
      Enum.frequencies(for _ <- 1..5000, do: elem(Imposter.pick(@players, []), 0))

    # expected 1000 each; the standard deviation is ~28, so +-200 is a wildly loose bound
    for player <- @players, do: assert(counts[player] in 800..1200)
  end

  test "the order within a cycle is not predictable" do
    orders = for _ <- 1..200, into: MapSet.new(), do: rounds(@players, 5)
    # 120 possible orders; a fixed or lazily rotating order would give 1 or 5
    assert MapSet.size(orders) > 60
  end

  test "someone who left no longer counts against anyone" do
    # "a" was imposter, then left; "b","c" remain
    {pick, history} = Imposter.pick(["b", "c"], ["a"])
    assert pick in ["b", "c"]
    assert history == [pick]
  end

  test "a player who joins mid-cycle gets their turn this cycle" do
    # a and b have had a turn; c is new
    {pick, _history} = Imposter.pick(["a", "b", "c"], ["b", "a"])
    assert pick == "c"
  end

  test "two players simply alternate" do
    picks = rounds(["a", "b"], 10)
    assert Enum.chunk_every(picks, 2) |> Enum.all?(&(Enum.sort(&1) == ["a", "b"]))
    assert Enum.all?(Enum.chunk_every(picks, 2, 1, :discard), fn [x, y] -> x != y end)
  end

  test "one player is always the imposter, and nobody is an error" do
    assert {"solo", _} = Imposter.pick(["solo"], [])
    assert {"solo", _} = Imposter.pick(["solo"], ["solo"])
    assert_raise ArgumentError, fn -> Imposter.pick([], []) end
  end
end
