defmodule Backend.Rooms.Imposter do
  @moduledoc """
  Fair, unpredictable choice of who is the imposter. Pure: no processes, no state of its own.

  Plain "pick someone at random each round" is fair on average but streaky: with 4 players you
  can be imposter three rounds running, or never. This uses a *shuffle bag* instead:

    * every player is in the bag; each round one is drawn at random and not put back
    * when the bag is empty, everyone goes back in (a new cycle)
    * at the start of a new cycle the previous imposter is held out, so nobody is imposter in
      two rounds in a row

  Within a cycle every player is imposter exactly once, and each draw is uniformly random among
  the players who haven't had a turn, so nobody can predict who is next.

  `history` is the list of who has been imposter in the current cycle, newest first.
  """

  @doc "Returns `{imposter_id, new_history}` for the given candidate player ids."
  def pick([], _history), do: raise(ArgumentError, "cannot pick an imposter from nobody")

  def pick(candidates, history) do
    # people who left, or aren't candidates now, shouldn't count against anyone
    history = Enum.filter(history, &(&1 in candidates))

    case candidates -- history do
      [] -> next_cycle(candidates, history)
      waiting -> draw(waiting, history)
    end
  end

  defp next_cycle(candidates, [last | _]) do
    # everyone has had a turn: start over, but not with the person who was just imposter
    case candidates -- [last] do
      [] -> draw(candidates, [])
      pool -> draw(pool, [])
    end
  end

  defp draw(pool, history) do
    id = Enum.random(pool)
    {id, [id | history]}
  end
end
