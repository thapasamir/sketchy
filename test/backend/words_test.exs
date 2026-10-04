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

  test "categories are listed in alphabetical order" do
    assert Words.categories() == Enum.sort(Words.categories())
  end

  describe "choosing categories" do
    test "only words from the chosen categories are dealt" do
      chosen = ["Animals", "Food"]
      picks = for _ <- 1..400, do: Words.pick([], %{categories: chosen}).category
      assert picks |> Enum.uniq() |> Enum.sort() == chosen
    end

    test "one category is fine" do
      assert for(_ <- 1..100, do: Words.pick([], %{categories: ["Animals"]}).category)
             |> Enum.uniq() == ["Animals"]
    end

    test "each chosen category gets an equal share, however many words it has" do
      chosen = ["Holidays and Celebrations", "Animals"]

      counts =
        Enum.frequencies(for _ <- 1..2000, do: Words.pick([], %{categories: chosen}).category)

      # 1000 each, give or take about 22
      for {_category, n} <- counts, do: assert(n in 850..1150)
    end

    test ":all means every category" do
      seen = for(_ <- 1..3000, do: Words.pick([], %{categories: :all}).category) |> Enum.uniq()
      assert length(seen) == 16
    end

    test "a category name that doesn't exist leaves nothing, so a word is dealt from everything" do
      assert %{word: _} = Words.pick([], %{categories: ["Not A Category"]})
    end
  end

  describe "choosing how hard" do
    test "easy: only easy words" do
      assert for(_ <- 1..500, do: Words.pick([], %{difficulty: :easy}).difficulty) |> Enum.uniq() ==
               ["easy"]
    end

    test "medium: easy and medium, never hard" do
      seen =
        for(_ <- 1..1500, do: Words.pick([], %{difficulty: :medium}).difficulty)
        |> Enum.uniq()
        |> Enum.sort()

      assert seen == ["easy", "medium"]
    end

    test "all: every level turns up" do
      seen =
        for(_ <- 1..4000, do: Words.pick([], %{difficulty: :all}).difficulty)
        |> Enum.uniq()
        |> Enum.sort()

      assert seen == ["easy", "hard", "medium"]
    end

    test "with no filter at all, everything is possible (as before)" do
      assert %{word: _} = Words.pick([], %{})
    end
  end

  describe "choosing both" do
    test "the words satisfy both choices" do
      filter = %{categories: ["Animals", "Food"], difficulty: :easy}

      for _ <- 1..300 do
        entry = Words.pick([], filter)
        assert entry.category in ["Animals", "Food"]
        assert entry.difficulty == "easy"
      end
    end

    test "words already used are still skipped inside the choice" do
      filter = %{categories: ["Animals"], difficulty: :easy}
      used = for _ <- 1..20, do: Words.pick([], filter).word
      later = for _ <- 1..300, do: Words.pick(used, filter).word
      assert later |> Enum.filter(&(&1 in used)) == []
    end

    test "when the choice has been used up, words repeat rather than the round failing, and the choice still holds" do
      filter = %{categories: ["Animals"], difficulty: :easy}
      everything = for _ <- 1..3000, into: MapSet.new(), do: Words.pick([], filter).word
      entry = Words.pick(MapSet.to_list(everything), filter)
      assert entry.category == "Animals" and entry.difficulty == "easy"
    end
  end

  describe "pool_size/1: how many words a choice leaves" do
    test "everything, with no filter" do
      assert Words.pool_size() == Words.count()
      assert Words.pool_size(%{categories: :all, difficulty: :all}) == Words.count()
    end

    test "fewer words when the choice is narrower" do
      all = Words.pool_size()
      medium = Words.pool_size(%{difficulty: :medium})
      easy = Words.pool_size(%{difficulty: :easy})
      assert easy < medium and medium < all
    end

    test "one category is a part of the whole" do
      assert Words.pool_size(%{categories: ["Animals"]}) in 100..250

      assert Words.pool_size(%{categories: ["Animals", "Food"]}) >
               Words.pool_size(%{categories: ["Animals"]})
    end

    test "a choice that matches nothing is zero" do
      assert Words.pool_size(%{categories: ["Not A Category"]}) == 0
    end
  end

  test "every category has easy words, so 'easy only' never leaves a category empty" do
    for category <- Words.categories(),
        do: assert(Words.pool_size(%{categories: [category], difficulty: :easy}) >= 20, category)
  end
end
