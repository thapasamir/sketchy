defmodule Backend.Rooms.Chat do
  @moduledoc """
  The rules for room chat. Pure functions.

  Chat is only relayed: the server checks a message, passes it to everyone in the room, and keeps
  nothing. Each browser remembers its own conversation. What the server does check:

    * the text is cleaned and kept short (`clean/1`),
    * while the secret word is still secret, the word is masked (`mask/2`), so that someone saying
      it, by accident or to help a friend, doesn't hand it to the imposter.
  """

  alias Backend.Rooms.Guess

  @max_length 200

  # A word, as a person reads it: letters and digits, where an apostrophe or hyphen in the middle
  # keeps it one word ("S'mores", "T-Shirt", "Whack-a-Mole"). A space ends it.
  @word ~r/([\p{L}\p{N}]+(?:['\x{2019}\-][\p{L}\p{N}]+)*)/u

  # Chat is open when talking can't give the game away: while waiting, while arguing over the
  # vote, and once the word is out. It is closed while the cards are being read, while people
  # draw (the drawings ARE the clues), and while the caught imposter guesses.
  @open_phases [:lobby, :voting, :result, :final]

  def open?(phase), do: phase in @open_phases

  @doc """
  Tidy a message from a browser: no control characters or line breaks, no runs of spaces, no
  leading or trailing space. Returns `{:ok, text}`, or an error for an empty or over-long message.
  """
  def clean(text) when is_binary(text) do
    cleaned =
      text
      |> String.replace(~r/[\p{C}\s]+/u, " ")
      |> String.trim()

    cond do
      cleaned == "" -> {:error, :empty}
      String.length(cleaned) > @max_length -> {:error, :too_long}
      true -> {:ok, cleaned}
    end
  end

  def clean(_), do: {:error, :empty}

  @doc """
  Hide `word` in `text`, replacing each letter with `*`, however it is written: any capitals,
  with or without spaces and hyphens in a multi-word answer, and with a small typo (the same
  forgiveness as the imposter's own guess). Everything else in the message is left as it is.
  """
  def mask(text, word) when is_binary(text) and is_binary(word) do
    # The answer as bare letters ("Whack-a-Mole" -> "whackamole"), and how many separate words it
    # can show up as in a message ("whack a mole" is three).
    key = word |> Guess.normalize() |> String.replace(" ", "")
    answer_words = length(Regex.scan(~r/[\p{L}\p{N}]+/u, word))

    if key == "" do
      text
    else
      # alternating separators and words: ["", "the", " ", "giraffe", "!"]
      pieces = Regex.split(@word, text, include_captures: true)
      pieces |> mask_pieces(key, answer_words) |> Enum.join()
    end
  end

  def mask(text, _word), do: text

  defp mask_pieces(pieces, key, answer_words) do
    indexed = Enum.with_index(pieces)

    # the words (odd positions in `pieces`), in order; the even positions are what lies between them
    word_positions = for {piece, i} <- indexed, rem(i, 2) == 1, do: {i, piece}

    # Every run of words that could be the answer, each scored by how many edits it is from it.
    # Then the best are taken, none overlapping: "a giraffe" is one edit from "giraffe", but
    # "giraffe" on its own is none, so "a" is left alone; "T shirt" is none from "T-Shirt" where
    # "shirt" alone is one, so both words are hidden.
    chosen =
      for(
        start <- 0..max(length(word_positions) - 1, 0),
        size <- 1..(answer_words + 1),
        window = word_positions |> Enum.drop(start) |> Enum.take(size),
        length(window) == size,
        {:yes, edits} <- [
          Guess.closeness(Enum.map_join(window, fn {_i, token} -> token end), key)
        ],
        do: {edits, size, for({i, _token} <- window, do: i)}
      )
      |> Enum.sort()
      |> Enum.reduce({[], MapSet.new()}, fn {_edits, _size, indexes}, {kept, taken} ->
        if Enum.any?(indexes, &MapSet.member?(taken, &1)),
          do: {kept, taken},
          else: {[indexes | kept], MapSet.union(taken, MapSet.new(indexes))}
      end)
      |> elem(0)

    words = chosen |> List.flatten() |> MapSet.new()
    separators = chosen |> Enum.flat_map(&inner_separators/1) |> MapSet.new()

    for {piece, i} <- indexed do
      cond do
        MapSet.member?(words, i) -> String.duplicate("*", String.length(piece))
        # the gap INSIDE an answer written as several words is hidden too
        MapSet.member?(separators, i) -> String.replace(piece, ~r/[^\s]/u, "*")
        true -> piece
      end
    end
  end

  # the pieces between the words of one match (so ", " between two separate matches is left alone)
  defp inner_separators(matched) when length(matched) < 2, do: []

  defp inner_separators(matched) do
    matched
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [a, b] -> Enum.to_list((a + 1)..(b - 1)//2) end)
  end
end
