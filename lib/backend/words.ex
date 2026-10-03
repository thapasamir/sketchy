defmodule Backend.Words do
  @moduledoc """
  The word list, loaded once when the app starts and kept in memory.

  It lives in `:persistent_term`: a built-in store for data that is written once and read very
  often. Reading it copies nothing, so every room reads the same single in-memory copy (about 1 MB),
  instead of each room process getting its own. The tradeoff is that updating it is expensive, which
  is fine for a list that only changes on deploy.

  Everything else asks this module (`pick/1`), so moving the list to a database later is a change
  in this one file.
  """

  @key {__MODULE__, :by_category}

  @doc "Read priv/words.json into memory. Called once from the application's start."
  def load!(path \\ default_path()) do
    by_category =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&to_entry/1)
      |> Enum.group_by(& &1.category)

    :persistent_term.put(@key, by_category)
    :ok
  end

  def categories, do: Map.keys(by_category())

  def count, do: by_category() |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

  @doc """
  Pick a random entry, skipping the words in `exclude` (so a room doesn't see a word twice).

  The category is chosen first, then a word inside it. That gives every category an equal chance
  no matter how many words it has, so a small category (Holidays) isn't drowned out by big ones.
  If every word has been excluded, the exclusion is ignored rather than failing.
  """
  def pick(exclude \\ []) do
    exclude = MapSet.new(exclude)
    data = by_category()

    fresh =
      for {category, entries} <- data,
          unused = Enum.reject(entries, &MapSet.member?(exclude, &1.word)),
          unused != [],
          do: {category, unused}

    case fresh do
      [] -> data |> Map.values() |> Enum.random() |> Enum.random()
      _ -> fresh |> Enum.random() |> elem(1) |> Enum.random()
    end
  end

  defp by_category, do: :persistent_term.get(@key)

  defp default_path, do: Application.app_dir(:backend, "priv/words.json")

  defp to_entry(%{"category" => c, "word" => w, "difficulty" => d, "hints" => h}) do
    %{category: c, word: w, difficulty: d, hints: h}
  end
end
