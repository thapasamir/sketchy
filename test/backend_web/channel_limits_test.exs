defmodule BackendWeb.ChannelLimitsTest do
  use ExUnit.Case, async: true

  alias BackendWeb.ChannelLimits

  defp send_n(limits, event, n, now) do
    Enum.map_reduce(1..n, limits, fn _, l ->
      {status, l} = ChannelLimits.take(l, event, now)
      {status, l}
    end)
  end

  test "messages come in three kinds" do
    assert ChannelLimits.kind("draw") == :draw
    assert ChannelLimits.kind("sync") == :sync

    for event <- ~w(vote chat react start set_ready update_settings kick whatever),
        do: assert(ChannelLimits.kind(event) == :general)
  end

  test "a drawer's burst of points is allowed" do
    {results, _} = send_n(ChannelLimits.new(0), "draw", 100, 0)
    assert Enum.all?(results, &(&1 == :ok))
  end

  test "ordinary messages are allowed a few at a time, not a flood" do
    {results, _} = send_n(ChannelLimits.new(0), "vote", 40, 0)
    assert Enum.count(results, &(&1 == :ok)) == 20
    assert :refused in results
  end

  test "asking for the whole picture is allowed rarely" do
    {results, _} = send_n(ChannelLimits.new(0), "sync", 10, 0)
    assert Enum.count(results, &(&1 == :ok)) == 5
  end

  test "the kinds are counted separately: drawing does not use up votes" do
    {_, limits} = send_n(ChannelLimits.new(0), "draw", 120, 0)
    assert {:ok, _} = ChannelLimits.take(limits, "vote", 0)
  end

  test "a flood in one kind does not stop the others" do
    {_, limits} = send_n(ChannelLimits.new(0), "vote", 60, 0)
    assert {:ok, _} = ChannelLimits.take(limits, "draw", 0)
  end

  test "a connection that keeps being refused is called abusive, once it has been 40 times" do
    {results, _} = send_n(ChannelLimits.new(0), "vote", 20 + 45, 0)
    refusals = Enum.filter(results, &(&1 != :ok))
    assert Enum.take(refusals, 39) == List.duplicate(:refused, 39)
    assert :abusive in refusals
  end

  test "a person using the room normally is never refused" do
    # a vote, a ready, a message and a reaction each second, for a minute
    {results, _} =
      Enum.map_reduce(0..60, ChannelLimits.new(0), fn second, limits ->
        Enum.map_reduce(~w(vote set_ready chat react), limits, fn event, l ->
          ChannelLimits.take(l, event, second * 1_000)
        end)
      end)

    assert results |> List.flatten() |> Enum.all?(&(&1 == :ok))
  end
end
