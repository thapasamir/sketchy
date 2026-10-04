defmodule Backend.Rooms.ChatTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.{Chat, Guess}

  describe "open?/1: when people may talk" do
    test "while waiting, during the vote, and once the word is out" do
      for phase <- [:lobby, :voting, :result, :final], do: assert(Chat.open?(phase))
    end

    test "not while cards are read, while people draw, or while the caught imposter guesses" do
      for phase <- [:reveal, :drawing, :guess], do: refute(Chat.open?(phase))
    end

    test "an unknown phase is closed" do
      refute Chat.open?(:nonsense)
    end
  end

  describe "clean/1" do
    test "trims and collapses spaces, tabs and line breaks" do
      assert {:ok, "hello there friend"} = Chat.clean("  hello \t there\n\n friend  ")
    end

    test "leaves ordinary text, punctuation and emoji alone" do
      assert {:ok, "It's Dan, obviously!! 🙂 (1/2)"} = Chat.clean("It's Dan, obviously!! 🙂 (1/2)")
    end

    test "removes control characters and invisible formatting (like right-to-left overrides)" do
      # each of these becomes a space (rather than gluing the two words together)
      assert {:ok, "a b"} = Chat.clean("a\u0000b")
      assert {:ok, "a b"} = Chat.clean("a\u202Eb")
      assert {:ok, "a b"} = Chat.clean("a​b")
    end

    test "an empty or blank message is refused" do
      for blank <- ["", "   ", "\n\t", "​​"], do: assert({:error, :empty} = Chat.clean(blank))
    end

    test "not text is refused" do
      for bad <- [nil, 42, %{}, :atom, ["a"]], do: assert({:error, :empty} = Chat.clean(bad))
    end

    test "200 characters is the limit" do
      assert {:ok, _} = Chat.clean(String.duplicate("a", 200))
      assert {:error, :too_long} = Chat.clean(String.duplicate("a", 201))
    end

    test "the limit counts characters, not bytes" do
      assert {:ok, _} = Chat.clean(String.duplicate("é", 200))
      assert {:ok, _} = Chat.clean(String.duplicate("🙂", 200))
    end

    test "HTML is not interpreted here (it is shown as text by the page); it passes through unchanged" do
      assert {:ok, "<script>alert(1)</script>"} = Chat.clean("<script>alert(1)</script>")
    end
  end

  describe "mask/2: hiding the secret word" do
    test "the word is replaced letter for letter, the rest left alone" do
      assert Chat.mask("it's a giraffe!", "Giraffe") == "it's a *******!"
    end

    test "whatever the capitals" do
      assert Chat.mask("GIRAFFE", "Giraffe") == "*******"
      assert Chat.mask("GiRaFfE time", "giraffe") == "******* time"
    end

    test "every time it appears" do
      assert Chat.mask("giraffe, giraffe, GIRAFFE", "Giraffe") == "*******, *******, *******"
    end

    test "with a small typo, as the imposter's own guess is forgiven" do
      assert Chat.mask("is it a girafe?", "Giraffe") == "is it a ******?"
      assert Chat.mask("giraffes", "Giraffe") == "********"
    end

    test "a multi-word answer is hidden whole, however it is spaced or joined" do
      for text <- [
            "grab the fire extinguisher now",
            "grab the Fire   Extinguisher now",
            "grab the fire-extinguisher now"
          ] do
        masked = Chat.mask(text, "Fire Extinguisher")
        refute masked =~ ~r/fire/i
        refute masked =~ ~r/extinguisher/i
        assert masked =~ "grab the "
        assert masked =~ " now"
      end
    end

    test "an answer with hyphens or apostrophes is hidden however it is written" do
      for text <- [
            "whack-a-mole!",
            "Whack-A-Mole!",
            "whack a mole!",
            "whackamole!",
            "WHACK A MOLE!"
          ] do
        masked = Chat.mask(text, "Whack-a-Mole")
        refute masked =~ ~r/[a-z]/i, "#{inspect(text)} became #{inspect(masked)}"
        assert masked =~ "!"
      end

      for text <- ["my t-shirt", "my t shirt", "my tshirt"] do
        refute Chat.mask(text, "T-Shirt") =~ ~r/shirt/i
        assert Chat.mask(text, "T-Shirt") =~ "my "
      end

      refute Chat.mask("rock n roll", "Rock 'n' Roll") =~ ~r/roll/i
      refute Chat.mask("ice-cream", "Ice-Cream") =~ ~r/cream/i
    end

    test "separate occurrences leave the punctuation between them alone" do
      assert Chat.mask("giraffe, giraffe", "Giraffe") == "*******, *******"
    end

    test "one word of a multi-word answer on its own is just a word (not hidden)" do
      assert Chat.mask("fire drill", "Fire Extinguisher") == "fire drill"

      assert Chat.mask("the extinguisher is red", "Fire Extinguisher") ==
               "the extinguisher is red"
    end

    test "accents and a leading article don't hide it" do
      assert Chat.mask("I love CAFÉ", "Café") == "I love ****"
      assert Chat.mask("the moon is out", "The Moon") == "the **** is out"
    end

    test "other words are untouched, including ones that merely look alike" do
      assert Chat.mask("I think it's Dan", "Giraffe") == "I think it's Dan"
      assert Chat.mask("a graph of a gate", "Giraffe") == "a graph of a gate"
    end

    test "a short answer must match exactly (cat is not cap, nor category)" do
      assert Chat.mask("my cat is not a cap, a category", "Cat") ==
               "my *** is not a cap, a category"
    end

    test "punctuation and emoji around it survive" do
      assert Chat.mask("Giraffe!!! 🙂", "Giraffe") == "*******!!! 🙂"
    end

    test "no secret, nothing to hide" do
      assert Chat.mask("hello", "") == "hello"
      assert Chat.mask("hello", nil) == "hello"
      assert Chat.mask("hello", "!!!") == "hello"
      assert Chat.mask("", "Giraffe") == ""
    end

    test "the length of the message is unchanged" do
      text = "pretty sure it's a giraffe, or a Giraffe? 🙂"
      assert String.length(Chat.mask(text, "Giraffe")) == String.length(text)
    end
  end

  describe "every real answer" do
    # the actual word list the game deals from
    @words "priv/words.json"
           |> File.read!()
           |> Jason.decode!()
           |> Enum.map(& &1["word"])
           |> Enum.uniq()

    # the ways someone might write the answer: as is, shouting, hyphens and spaces swapped, or run together
    defp spellings(word) do
      [
        word,
        String.upcase(word),
        String.replace(word, [" ", "-"], "-"),
        String.replace(word, [" ", "-"], " "),
        String.replace(word, [" ", "-", "'"], "")
      ]
      |> Enum.uniq()
    end

    test "is hidden completely in a sentence, in every spelling, and the sentence around it is untouched" do
      for word <- @words, spelling <- spellings(word) do
        masked = Chat.mask("pretty sure it is a #{spelling} ok", word)

        assert String.starts_with?(masked, "pretty sure it is a "),
               "#{inspect(word)} (as #{inspect(spelling)}) damaged the words before it: #{inspect(masked)}"

        assert String.ends_with?(masked, " ok"),
               "#{inspect(word)} (as #{inspect(spelling)}) damaged the words after it: #{inspect(masked)}"

        middle =
          masked
          |> String.replace_prefix("pretty sure it is a ", "")
          |> String.replace_suffix(" ok", "")

        refute middle =~ ~r/[\p{L}\p{N}]/u,
               "#{inspect(word)} (as #{inspect(spelling)}) was not hidden: #{inspect(masked)}"
      end
    end

    test "is recognised as the answer when the imposter guesses it, in every spelling" do
      for word <- @words, spelling <- spellings(word) do
        assert Guess.matches?(spelling, word),
               "#{inspect(spelling)} should be accepted for #{inspect(word)}"
      end
    end

    test "is not hidden when it is not there" do
      for word <- @words do
        assert Chat.mask("I have no idea what this could be", word) ==
                 "I have no idea what this could be"
      end
    end
  end
end
