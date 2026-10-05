defmodule BackendWeb.ChannelLimits do
  @moduledoc """
  How fast one connection may send messages to a room. Pure functions over data kept in the
  channel's assigns; the channel decides what to do with the answer.

  Messages are of three kinds, each with its own token bucket (see `Backend.RateLimit.Bucket`):

    * `:draw` - the drawer's points arrive about 25 times a second, in bursts, so this allows a lot;
    * `:sync` - asking for the whole picture again is the most expensive thing a client can ask for,
      so it is allowed rarely;
    * `:general` - everything else (votes, ready, settings, chat, reactions), which a person
      does a few times a second at most.

  A connection that keeps being refused, quickly, is not slowed down any more: it is dropped.
  """

  alias Backend.RateLimit.Bucket

  # {capacity, refilled per second}
  @shapes %{
    draw: {120, 80},
    sync: {5, 0.5},
    general: {20, 8}
  }

  @doc "A fresh set of full buckets."
  def new(now \\ System.monotonic_time(:millisecond)) do
    Map.new(@shapes, fn {kind, {capacity, per_s}} -> {kind, Bucket.new(capacity, per_s, now)} end)
  end

  @doc "Which kind of message an event is."
  def kind("draw"), do: :draw
  def kind("sync"), do: :sync
  def kind(_event), do: :general

  @doc """
  Count a message. Returns `{:ok, limits}`, `{:refused, limits}` (too fast: refuse this one),
  or `{:abusive, limits}` (so much too fast, so often, that the connection should be closed).
  """
  def take(limits, event, now \\ System.monotonic_time(:millisecond)) do
    kind = kind(event)

    case Bucket.take(Map.fetch!(limits, kind), now) do
      {:ok, bucket} ->
        {:ok, Map.put(limits, kind, bucket)}

      {:refused, bucket} ->
        status = if Bucket.abusive?(bucket, now), do: :abusive, else: :refused
        {status, Map.put(limits, kind, bucket)}
    end
  end
end
