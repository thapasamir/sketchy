defmodule Backend.Rooms.Dealer do
  @moduledoc """
  Deals a round: picks the secret word and the imposter. All the randomness lives here, so
  `Room` stays a pure function of its inputs (tests can hand it a fixed deal).
  """

  alias Backend.Rooms.{Imposter, Room}
  alias Backend.Words

  @doc "A deal for `room`: `%{imposter_id, imposter_history, entry, hint, used_words, turn_order}`."
  def deal(%Room{} = room) do
    # an away player can't see their card, so they are never chosen when others are present
    connected = for {id, p} <- room.players, p.connected?, do: id
    candidates = if connected == [], do: Map.keys(room.players), else: connected

    history = if room.game, do: room.game.imposter_history, else: []
    used = if room.game, do: room.game.used_words, else: []

    {imposter_id, history} = Imposter.pick(candidates, history)
    entry = Words.pick(used)

    %{
      imposter_id: imposter_id,
      imposter_history: history,
      entry: entry,
      hint: Enum.random(entry.hints),
      used_words: [entry.word | used],
      # who draws in which order this round
      turn_order: room.players |> Map.keys() |> Enum.shuffle()
    }
  end
end
