defmodule Backend.Rooms.Voting do
  @moduledoc """
  What happens after the drawing: everyone votes for who they think the imposter is; if the
  imposter was caught they get one guess at the word; then the round is scored.

  Pure functions over a `Backend.Rooms.Room`, like the rest of the room rules. Time (`now`) and
  durations are passed in. The phases:

      :voting  ->  :guess  ->  :result      (the imposter was caught)
      :voting  ->  :result                  (they got away)

  Scores: the crew gets 1 point each for catching the imposter; an imposter who gets away gets 2;
  one who is caught but then guesses the word gets 1.
  """

  alias Backend.Rooms.Guess

  @crew_catch 1
  @imposter_escape 2
  @imposter_guess 1

  @doc "The drawing is over: open the voting. Called by the room when the last turn ends."
  def open(room, now, vote_ms) do
    game = %{room.game | votes: %{}, vote_ends_at: now + vote_ms}
    %{room | phase: :voting, game: %{game | queue: [], turn: nil, open_stroke: nil}}
  end

  @doc "`voter_id` votes for `target_id`; voting again just changes the vote."
  def vote(room, voter_id, target_id) do
    cond do
      room.phase != :voting ->
        {:error, :not_voting}

      not is_binary(target_id) or not Map.has_key?(room.players, target_id) ->
        {:error, :not_a_member}

      not Map.has_key?(room.players, voter_id) ->
        {:error, :not_a_member}

      # someone who is only watching can't vote, and can't be voted for: they weren't in the round
      room.players[voter_id].spectator? ->
        {:error, :spectating}

      room.players[target_id].spectator? ->
        {:error, :not_a_member}

      voter_id == target_id ->
        {:error, :cannot_vote_self}

      true ->
        {:ok, put_in(room.game.votes[voter_id], target_id)}
    end
  end

  @doc "Who `player_id` is currently voting for (only while voting is open)."
  def my_vote(%{phase: :voting, game: %{votes: votes}}, player_id), do: votes[player_id]
  def my_vote(_room, _player_id), do: nil

  @doc "Has everyone who is here voted? Away players and spectators don't hold the vote up."
  def all_voted?(%{phase: :voting} = room) do
    here = for {id, %{connected?: true, spectator?: false}} <- room.players, do: id
    here != [] and Enum.all?(here, &Map.has_key?(room.game.votes, &1))
  end

  def all_voted?(_room), do: false

  @doc """
  Voting is over. Most votes is accused; a tie, or no votes, accuses nobody. If the accused is
  the imposter they get a guess (`guess_ms` to make it); otherwise the imposter got away.
  """
  def close(%{phase: :voting} = room, now, guess_ms) do
    accused = accused(room.game.votes)
    imposter = room.game.imposter_id
    room = put_in(room.game.accused, accused)

    cond do
      not Map.has_key?(room.players, imposter) -> finish(room, :imposter_left, nil)
      accused == imposter -> {:ok, begin_guess(room, now, guess_ms)}
      true -> finish(room, :escaped, nil)
    end
  end

  def close(_room, _now, _guess_ms), do: {:error, :not_voting}

  defp begin_guess(room, now, guess_ms) do
    room = %{room | phase: :guess}
    put_in(room.game.guess_ends_at, now + guess_ms)
  end

  @doc "The caught imposter guesses the word. One guess only."
  def guess(%{phase: :guess} = room, player_id, text) do
    cond do
      player_id != room.game.imposter_id -> {:error, :not_imposter}
      not Guess.valid?(text) -> {:error, :invalid_guess}
      Guess.matches?(text, room.game.entry.word) -> finish(room, :guessed, String.trim(text))
      true -> finish(room, :caught, String.trim(text))
    end
  end

  def guess(_room, _player_id, _text), do: {:error, :not_guessing}

  @doc "The guess time ran out: the imposter stays caught."
  def give_up(%{phase: :guess} = room), do: finish(room, :caught, nil)
  def give_up(_room), do: {:error, :not_guessing}

  @doc """
  The imposter left the room before the round was over. Nobody can be caught any more, so the
  round ends on the spot and the crew win it. (If they are merely away, the round carries on:
  they may be back.)
  """
  def imposter_left(%{phase: phase} = room) when phase in [:reveal, :drawing, :voting, :guess],
    do: finish(room, :imposter_left, nil)

  def imposter_left(_room), do: {:error, :not_in_round}

  defp accused(votes) do
    case votes |> Map.values() |> Enum.frequencies() |> Enum.sort_by(fn {_id, n} -> -n end) do
      [{_, n}, {_, n} | _] -> nil
      [{id, _} | _] -> id
      [] -> nil
    end
  end

  # the round is over: work out the points, keep them, and record what happened for everyone to see
  defp finish(room, outcome, guess) do
    game = room.game
    imposter = game.imposter_id
    # the crew: everyone who played the round (not a spectator), other than the imposter
    crew = for {id, _player} <- Backend.Rooms.Room.contestants(room), id != imposter, do: id

    points =
      case outcome do
        :escaped -> %{imposter => @imposter_escape}
        :guessed -> Map.put(Map.new(crew, &{&1, @crew_catch}), imposter, @imposter_guess)
        _caught -> Map.new(crew, &{&1, @crew_catch})
      end

    result = %{
      outcome: outcome,
      imposter_id: imposter,
      # names as they were during the round, so a player who has since left still shows up
      names: game.names,
      word: game.entry.word,
      category: game.entry.category,
      accused: game.accused,
      guess: guess,
      votes: game.votes,
      tally: Enum.frequencies(Map.values(game.votes)),
      points: points
    }

    scores = Map.merge(room.scores, points, fn _id, old, new -> old + new end)
    {:ok, %{room | phase: :result, scores: scores, game: %{game | result: result}}}
  end

  @doc "Someone left during the vote: their vote, and votes for them, no longer count."
  def forget(%{game: %{votes: votes}} = room, player_id) do
    votes =
      votes |> Map.delete(player_id) |> Map.reject(fn {_voter, target} -> target == player_id end)

    put_in(room.game.votes, votes)
  end

  def forget(room, _player_id), do: room

  @doc "The voting / guessing / result part of the public room, or nil."
  def public(%{phase: :voting, game: game} = room, now) do
    %{
      ms_left: max(game.vote_ends_at - now, 0),
      # who has voted, never for whom
      voted: game.votes |> Map.keys() |> Enum.filter(&Map.has_key?(room.players, &1))
    }
  end

  def public(%{phase: :guess, game: game}, now) do
    %{ms_left: max(game.guess_ends_at - now, 0), guesser_id: game.imposter_id}
  end

  # `ms_left` is how long until the next round starts by itself (nil if no wait is running)
  def public(%{phase: :result, game: game}, now) do
    Map.put(game.result, :ms_left, game.next_at && max(game.next_at - now, 0))
  end

  def public(_room, _now), do: nil
end
