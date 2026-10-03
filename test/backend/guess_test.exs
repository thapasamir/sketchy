defmodule Backend.Rooms.GuessTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.Guess

  describe "normalize/1" do
    test "ignores case, spacing, punctuation and accents" do
      assert Guess.normalize("  Fire   EXTINGUISHER!! ") == "fire extinguisher"
      assert Guess.normalize("Café") == "cafe"
      assert Guess.normalize("rock-n-roll") == "rocknroll"
    end

    test "drops a leading article, but not when it is the whole answer" do
      assert Guess.normalize("The Moon") == "moon"
      assert Guess.normalize("an apple") == "apple"
      assert Guess.normalize("the") == "the"
    end
  end

  describe "matches?/2" do
    test "the right word, however it is typed" do
      assert Guess.matches?("giraffe", "Giraffe")
      assert Guess.matches?("  GIRAFFE ", "Giraffe")
      assert Guess.matches?("fire extinguisher", "Fire Extinguisher")
      assert Guess.matches?("the giraffe", "Giraffe")
    end

    test "a small typo is forgiven in a longer word" do
      assert Guess.matches?("girafe", "Giraffe")
      assert Guess.matches?("giraffee", "Giraffe")
      assert Guess.matches?("girraffe", "Giraffe")
      assert Guess.matches?("fire extinguiser", "Fire Extinguisher")
    end

    test "two typos only in a long word" do
      assert Guess.matches?("fire extinguiser!", "Fire Extinguisher")
      assert Guess.matches?("fyre extinguiser", "Fire Extinguisher")
      refute Guess.matches?("fyre extingwiser", "Fire Extinguisher")
      refute Guess.matches?("girrafee", "Giraffe")
    end

    test "short words must be exact: a different short word is a different answer" do
      refute Guess.matches?("cap", "Cat")
      refute Guess.matches?("cow", "Cat")
      refute Guess.matches?("bus", "Bun")
      assert Guess.matches?("cat", "Cat")
    end

    test "medium words get one typo" do
      assert Guess.matches?("pizzza", "Pizza")
      assert Guess.matches?("piza", "Pizza")
      refute Guess.matches?("pizzaax", "Pizza")
    end

    test "a different word is wrong, even a similar one" do
      refute Guess.matches?("elephant", "Giraffe")
      refute Guess.matches?("zebra", "Giraffe")
      refute Guess.matches?("horse", "Hearse")
      refute Guess.matches?("bandage", "Bandana")
    end

    test "nothing, or not a string, is never a match" do
      refute Guess.matches?("", "Giraffe")
      refute Guess.matches?("   ", "Giraffe")
      refute Guess.matches?("!!!", "Giraffe")
      refute Guess.matches?(nil, "Giraffe")
      refute Guess.matches?(42, "Giraffe")
    end
  end

  test "valid?/1 accepts a word or two and rejects blanks and essays" do
    assert Guess.valid?("giraffe")
    assert Guess.valid?("fire extinguisher")
    refute Guess.valid?("")
    refute Guess.valid?("   ")
    refute Guess.valid?(String.duplicate("a", 61))
    refute Guess.valid?(nil)
  end
end
