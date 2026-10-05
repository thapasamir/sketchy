defmodule Backend.Avatar do
  @moduledoc """
  A player's face: which eyes, which mouth, which hat (or none). Pure functions.

  The face is drawn on top of the player's assigned colour and shape, which the game still chooses
  (that is how you tell drawings apart). A face is only three small numbers, each an index into a
  fixed set of drawings kept in the browser, so there is nothing for anyone to upload, and the
  server can check one completely: any number outside the set is refused.

  The counts here must match the browser's (assets/js/lib/avatar.js; a test compares them).
  """

  @counts %{eyes: 8, mouth: 8, hat: 8}

  @type t :: %{eyes: non_neg_integer(), mouth: non_neg_integer(), hat: non_neg_integer()}

  @doc "How many choices there are of each part. Hat 0 is no hat."
  def counts, do: @counts

  @doc """
  Check a face from a browser (`%{"eyes" => 2, "mouth" => 0, "hat" => 5}`) or from inside the
  server (atom keys). Returns `{:ok, face}` or `:error`.
  """
  def parse(%{} = params) do
    with {:ok, eyes} <- part(params, :eyes),
         {:ok, mouth} <- part(params, :mouth),
         {:ok, hat} <- part(params, :hat) do
      {:ok, %{eyes: eyes, mouth: mouth, hat: hat}}
    end
  end

  def parse(_), do: :error

  defp part(params, key) do
    value = Map.get(params, key, Map.get(params, Atom.to_string(key)))

    if is_integer(value) and value >= 0 and value < Map.fetch!(@counts, key),
      do: {:ok, value},
      else: :error
  end

  @doc "Like `parse/1`, but a face that doesn't check out is simply no face: `nil`."
  def parse_or_nil(params) do
    case parse(params) do
      {:ok, face} -> face
      :error -> nil
    end
  end

  @doc """
  A face for someone who hasn't chosen one, always the same for the same `seed` (a player's id), so
  it doesn't change between one update and the next.
  """
  def from_seed(seed) do
    %{
      eyes: :erlang.phash2({seed, :eyes}, @counts.eyes),
      mouth: :erlang.phash2({seed, :mouth}, @counts.mouth),
      hat: :erlang.phash2({seed, :hat}, @counts.hat)
    }
  end
end
