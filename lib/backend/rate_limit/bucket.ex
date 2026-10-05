defmodule Backend.RateLimit.Bucket do
  @moduledoc """
  A token bucket: how fast one connection may send messages. Pure data, no processes.

  The bucket holds up to `capacity` tokens and gets `refill_per_s` more every second. Each message
  takes one. Out of tokens means "too fast". Because it fills while you're quiet, a short burst is
  fine (a drawer's flurry of points) while a steady flood is not.

  `take/2` also counts the refusals: `abusive?/2` says when a connection has been refused so often,
  so quickly, that it should be dropped rather than refused again.
  """

  defstruct [:capacity, :refill_per_s, :tokens, :at, refused: 0, since: nil]

  @type t :: %__MODULE__{}

  @doc "A full bucket. `now` is in milliseconds."
  def new(capacity, refill_per_s, now) do
    %__MODULE__{capacity: capacity, refill_per_s: refill_per_s, tokens: capacity * 1.0, at: now}
  end

  @doc "Take one token. Returns `{:ok, bucket}` or `{:refused, bucket}`."
  def take(%__MODULE__{} = bucket, now) do
    bucket = refill(bucket, now)

    if bucket.tokens >= 1 do
      {:ok, %{bucket | tokens: bucket.tokens - 1}}
    else
      since = bucket.since || now
      # a long quiet spell forgives earlier refusals
      refused = if now - since > 10_000, do: 1, else: bucket.refused + 1
      since = if refused == 1, do: now, else: since
      {:refused, %{bucket | refused: refused, since: since}}
    end
  end

  @doc "Has this connection been refused `limit` times within 10 seconds?"
  def abusive?(%__MODULE__{refused: refused, since: since}, now, limit \\ 40),
    do: refused >= limit and since != nil and now - since <= 10_000

  defp refill(%__MODULE__{tokens: tokens, at: at} = bucket, now) do
    gained = max(now - at, 0) / 1000 * bucket.refill_per_s
    %{bucket | tokens: min(bucket.capacity * 1.0, tokens + gained), at: now}
  end
end
