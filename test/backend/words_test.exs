defmodule Backend.WordsTest do
  use ExUnit.Case, async: true

  alias Backend.Words

  test "the word list is loaded in memory at startup" do
    assert Words.count() > 1000
    assert length(Words.categories()) == 16
  end

  test "an entry has everything a round needs" do
    assert %{category: c, word: w, difficulty: d, hints: [_, _, _]} = Words.pick()
    assert is_binary(c) and is_binary(w) and d in ["easy", "medium", "hard"]
  end

  test "words in the exclude list are never picked" do
    banned = for _ <- 1..30, do: Words.pick().word
    picks = for _ <- 1..500, do: Words.pick(banned).word
    assert picks |> Enum.filter(&(&1 in banned)) == []
  end

  test "every category gets an equal chance, however many words it has" do
    counts = Enum.frequencies(for _ <- 1..8000, do: Words.pick().category)

    # 16 categories: ~500 each (sd ~22). The smallest category (about 58 words) and the largest
    # (120) must both land near that, which they would not if we picked from all words equally.
    for {_category, n} <- counts, do: assert(n in 350..650)
    assert map_size(counts) == 16
  end

  test "when everything has been excluded it still returns a word" do
    everything = for _ <- 1..20_000, into: MapSet.new(), do: Words.pick().word
    assert %{word: _} = Words.pick(MapSet.to_list(everything))
  end
end
