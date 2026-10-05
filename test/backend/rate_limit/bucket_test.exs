defmodule Backend.RateLimit.BucketTest do
  use ExUnit.Case, async: true

  alias Backend.RateLimit.Bucket

  # take n messages at `now`, returning the bucket and the results
  defp take_many(bucket, n, now) do
    Enum.map_reduce(1..n, bucket, fn _, b ->
      {status, b} = Bucket.take(b, now)
      {status, b}
    end)
  end

  test "a fresh bucket allows a burst up to its capacity, then refuses" do
    {results, _} = take_many(Bucket.new(5, 1, 0), 8, 0)
    assert Enum.take(results, 5) == List.duplicate(:ok, 5)
    assert Enum.drop(results, 5) == List.duplicate(:refused, 3)
  end

  test "it fills again with time" do
    {_, empty} = take_many(Bucket.new(5, 2, 0), 5, 0)
    assert {:refused, _} = Bucket.take(empty, 0)
    # half a second at 2 a second: one token
    assert {:ok, again} = Bucket.take(empty, 500)
    assert {:refused, _} = Bucket.take(again, 500)
    # two more seconds: four
    {results, _} = take_many(again, 5, 2_500)
    assert Enum.count(results, &(&1 == :ok)) == 4
  end

  test "it never holds more than its capacity, however long it is left" do
    {results, _} = take_many(Bucket.new(3, 10, 0), 6, 1_000_000)
    assert Enum.count(results, &(&1 == :ok)) == 3
  end

  test "a steady pace below the refill rate is never refused" do
    # 5 a second, bucket refills 8 a second
    {results, _} =
      Enum.map_reduce(0..200, Bucket.new(20, 8, 0), fn i, b ->
        {status, b} = Bucket.take(b, i * 200)
        {status, b}
      end)

    assert Enum.all?(results, &(&1 == :ok))
  end

  test "a steady pace above the refill rate is refused in the end" do
    # 20 a second against 8 a second
    {results, _} =
      Enum.map_reduce(0..400, Bucket.new(20, 8, 0), fn i, b ->
        {status, b} = Bucket.take(b, i * 50)
        {status, b}
      end)

    assert :refused in results
    assert Enum.count(results, &(&1 == :ok)) < 250
  end

  test "a refused message does not use a token" do
    {_, empty} = take_many(Bucket.new(1, 1, 0), 1, 0)
    {:refused, b} = Bucket.take(empty, 0)
    {:refused, b} = Bucket.take(b, 0)
    assert {:ok, _} = Bucket.take(b, 1_000)
  end

  describe "abusive?/3" do
    test "not for someone who is only occasionally refused" do
      {_, b} = take_many(Bucket.new(1, 1, 0), 10, 0)
      refute Bucket.abusive?(b, 0)
    end

    test "yes once it has been refused 40 times within 10 seconds" do
      {_, b} = take_many(Bucket.new(1, 0.1, 0), 41, 0)
      assert b.refused == 40
      assert Bucket.abusive?(b, 0)
    end

    test "the limit can be changed" do
      {_, b} = take_many(Bucket.new(1, 0.1, 0), 6, 0)
      assert Bucket.abusive?(b, 0, 5)
      refute Bucket.abusive?(b, 0, 6)
    end

    test "not if the refusals were spread over more than 10 seconds" do
      b = Bucket.new(1, 0, 0)
      {_, b} = Bucket.take(b, 0)

      b =
        Enum.reduce(0..45, b, fn i, b ->
          {_, b} = Bucket.take(b, i * 1_000)
          b
        end)

      refute Bucket.abusive?(b, 45_000)
    end

    test "a quiet spell forgives what came before" do
      {_, b} = take_many(Bucket.new(1, 0, 0), 30, 0)
      assert b.refused > 20
      {:refused, b} = Bucket.take(b, 60_000)
      assert b.refused == 1
    end
  end
end
