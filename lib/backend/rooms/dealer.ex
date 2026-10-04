defmodule Backend.Rooms.Dealer do
  @moduledoc """
  Deals a round: picks the secret word and the imposter. All the randomness lives here, so
  `Room` stays a pure function of its inputs (tests can hand it a fixed deal).
  """

  alias Backend.Rooms.{Imposter, Room}
  alias Backend.Words

  @doc "A deal for `room`: `%{imposter_id, imposter_history, entry, hint, used_words, turn_order}`."
  def deal(%Room{} = room) do
    # Only people playing the round are dealt in (not spectators). An away player can't see their
    # card, so they are never chosen as the imposter when others are present.
    contestants = Room.contestants(room)
    connected = for {id, p} <- contestants, p.connected?, do: id
    candidates = if connected == [], do: Enum.map(contestants, &elem(&1, 0)), else: connected

    history = if room.game, do: room.game.imposter_history, else: []
    used = if room.game, do: room.game.used_words, else: []

    {imposter_id, history} = Imposter.pick(candidates, history)
    # the host's choice of categories and difficulty
    entry = Words.pick(used, Room.word_filter(room))

    %{
      imposter_id: imposter_id,
      imposter_history: history,
      entry: entry,
      hint: Enum.random(entry.hints),
      used_words: [entry.word | used],
      # who draws in which order this round
      turn_order: contestants |> Enum.map(&elem(&1, 0)) |> Enum.shuffle()
    }
  end
end
