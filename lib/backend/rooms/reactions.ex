defmodule Backend.Rooms.Reactions do
  @moduledoc """
  Emoji reactions: a quick way to cheer or tease without typing. Pure rules.

  They are safe to allow while people draw because they carry no words. The only thing a browser
  can send is the name of one of a fixed handful of reactions, and anything else is refused, so a
  reaction can never be used to say the secret word or to pass a message to the imposter. (The
  pictures for the names live in the browser.)
  """

  @ids ~w(laugh think sus eyes clap fire)

  # open while there is a drawing to react to, and after it; closed in the lobby and the guess
  @open_phases [:drawing, :voting, :result]

  @doc "The reactions a browser may send."
  def ids, do: @ids

  @doc "Is this one of them? (Anything that isn't text is not.)"
  def valid?(id), do: is_binary(id) and id in @ids

  @doc "Can people react right now?"
  def open?(phase), do: phase in @open_phases
end
