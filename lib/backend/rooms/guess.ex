defmodule Backend.Rooms.Guess do
  @moduledoc """
  Decides whether the imposter's guess counts as the secret word. Pure functions.

  The imposter is typing a word from memory, under time pressure, so the check forgives what a
  person would: capital letters, extra spaces, punctuation, accents, a leading "the", and a
  small typo in a longer word. It does not forgive a different word.
  """

  @max_length 60

  @doc "Is `guess` close enough to `word`?"
  def matches?(guess, word), do: closeness(guess, word) != :no

  @doc """
  How close `guess` is to `word`: `{:yes, edits}` (0 is exact) if it counts as the word, else
  `:no`. Lets a caller choose the best of several candidates.
  """
  def closeness(guess, word) when is_binary(guess) and is_binary(word) do
    # spaces are ignored entirely: "Whack-a-Mole", "whack a mole" and "whackamole" are one answer
    guess = guess |> normalize() |> squeeze()
    word = word |> normalize() |> squeeze()

    if guess == "" do
      :no
    else
      edits = levenshtein(guess, word)
      if edits <= allowed_typos(word), do: {:yes, edits}, else: :no
    end
  end

  def closeness(_guess, _word), do: :no

  @doc "Is this something we would even look at? (a word or two, not an essay)"
  def valid?(guess),
    do: is_binary(guess) and String.trim(guess) != "" and String.length(guess) <= @max_length

  # "Fire  Extinguisher!" -> "fire extinguisher", "Café" -> "cafe", "The Moon" -> "moon"
  def normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, "")
    |> String.split()
    |> drop_article()
    |> Enum.join(" ")
  end

  defp squeeze(text), do: String.replace(text, " ", "")

  defp drop_article([article, _ | _] = words) when article in ~w(a an the), do: tl(words)
  defp drop_article(words), do: words

  # short words must be exact ("cat" vs "cap" are different answers); longer ones get a typo
  defp allowed_typos(word) do
    case String.length(word) do
      n when n >= 10 -> 2
      n when n >= 5 -> 1
      _ -> 0
    end
  end

  # the number of single-letter edits (insert, delete, change) between two strings
  defp levenshtein(a, b) do
    a = String.graphemes(a)
    b = String.graphemes(b)
    first_row = Enum.to_list(0..length(b))

    a
    |> Enum.with_index(1)
    |> Enum.reduce(first_row, fn {char_a, i}, previous ->
      b
      |> Enum.zip(Enum.zip(previous, tl(previous)))
      |> Enum.reduce([i], fn {char_b, {diagonal, above}}, [left | _] = row ->
        cost = if char_a == char_b, do: 0, else: 1
        [min(min(above + 1, left + 1), diagonal + cost) | row]
      end)
      |> Enum.reverse()
    end)
    |> List.last()
  end
end
