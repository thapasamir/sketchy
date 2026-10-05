defmodule Backend.RateLimitTest do
  # The limits are an application setting shared by everything, so these tests can't run alongside others.
  use ExUnit.Case, async: false

  # (going over a limit is logged, on purpose: it is expected here)
  @moduletag :capture_log

  import Backend.RateLimitHelper

  alias Backend.RateLimit

  describe "hit/3: a count per caller per window" do
    setup do
      enable()
      # login_user: 10 per 15 minutes
      %{window: 900_000, now: 10 * 900_000 + 5}
    end

    test "up to the count is fine, then refused", %{now: now} do
      for _ <- 1..10, do: assert(:ok = RateLimit.hit(:login_user, "alice", now))
      assert {:error, retry} = RateLimit.hit(:login_user, "alice", now)
      assert retry > 0
    end

    test "it says how long until the window ends", %{now: now, window: window} do
      for _ <- 1..10, do: RateLimit.hit(:login_user, "alice", now)
      assert {:error, retry} = RateLimit.hit(:login_user, "alice", now)
      assert retry == 11 * window - now
    end

    test "a refused request does not extend the wait", %{now: now} do
      for _ <- 1..10, do: RateLimit.hit(:login_user, "alice", now)
      assert {:error, first} = RateLimit.hit(:login_user, "alice", now)
      assert {:error, ^first} = RateLimit.hit(:login_user, "alice", now)
    end

    test "when the window ends the count starts again", %{now: now, window: window} do
      for _ <- 1..11, do: RateLimit.hit(:login_user, "alice", now)
      assert :ok = RateLimit.hit(:login_user, "alice", now + window)
    end

    test "callers are counted separately", %{now: now} do
      for _ <- 1..11, do: RateLimit.hit(:login_user, "alice", now)
      assert {:error, _} = RateLimit.hit(:login_user, "alice", now)
      assert :ok = RateLimit.hit(:login_user, "bob", now)
    end

    test "policies are counted separately", %{now: now} do
      for _ <- 1..11, do: RateLimit.hit(:login_user, "same", now)
      assert {:error, _} = RateLimit.hit(:login_user, "same", now)
      assert :ok = RateLimit.hit(:login, "same", now)
    end

    test "an unknown policy is a mistake, not a pass" do
      assert_raise KeyError, fn -> RateLimit.hit(:no_such_thing, "x") end
    end
  end

  describe "blocked?/3: asking without counting" do
    setup do
      enable()
      # room_miss: 15 per 5 minutes
      %{now: 20 * 300_000 + 1}
    end

    test "not blocked until the count is used up", %{now: now} do
      for _ <- 1..14, do: RateLimit.hit(:room_miss, "ip", now)
      refute RateLimit.blocked?(:room_miss, "ip", now)
      RateLimit.hit(:room_miss, "ip", now)
      assert {:blocked, retry} = RateLimit.blocked?(:room_miss, "ip", now)
      assert retry > 0
    end

    test "asking does not count", %{now: now} do
      for _ <- 1..50, do: RateLimit.blocked?(:room_miss, "ip", now)
      refute RateLimit.blocked?(:room_miss, "ip", now)
      assert :ok = RateLimit.hit(:room_miss, "ip", now)
    end

    test "it ends with the window", %{now: now} do
      for _ <- 1..15, do: RateLimit.hit(:room_miss, "ip", now)
      assert {:blocked, _} = RateLimit.blocked?(:room_miss, "ip", now)
      refute RateLimit.blocked?(:room_miss, "ip", now + 300_000)
    end
  end

  describe "the settings" do
    test "scale multiplies every count, but never below one" do
      enable(0.1)
      assert {6, _} = RateLimit.policy!(:guest)
      assert {1, _} = RateLimit.policy!(:login_user)
      enable(0.0001)
      assert {1, _} = RateLimit.policy!(:guest)
      enable(2)
      assert {120, _} = RateLimit.policy!(:guest)
    end

    test "scale applies when counting" do
      enable(0.1)
      now = 1_000_000
      for _ <- 1..6, do: assert(:ok = RateLimit.hit(:guest, "ip", now))
      assert {:error, _} = RateLimit.hit(:guest, "ip", now)
    end

    test "when the limits are off, nothing is ever refused or blocked" do
      Backend.RateLimitHelper.put_env(:rate_limits, enabled: false)
      for _ <- 1..500, do: assert(:ok = RateLimit.hit(:register, "ip"))
      refute RateLimit.blocked?(:register, "ip")
      assert :ok = RateLimit.hold_seat("ip")
    end

    test "every policy has a sensible count and window" do
      for policy <- RateLimit.policies() do
        {limit, window} = RateLimit.policy!(policy)
        assert limit >= 1 and window >= 1_000, inspect(policy)
      end
    end
  end

  describe "tidying" do
    test "counts of windows that have ended are removed, the current ones are not" do
      enable()
      RateLimit.hit(:guest, "old", 1_000)
      RateLimit.hit(:guest, "current", 50_000_000)

      RateLimit.sweep(50_000_000)

      keys =
        :ets.tab2list(RateLimit)
        |> Enum.map(fn {{_policy, subject, _window}, _n, _exp} -> subject end)

      refute "old" in keys
      assert "current" in keys
    end
  end

  describe "hold_seat/1: how many live connections one address may keep" do
    setup do
      enable(1, seats_per_ip: 2)
      # a fresh address for each test: holders from another test may still be alive
      %{
        ip: "ip-#{System.unique_integer([:positive])}",
        other: "other-#{System.unique_integer([:positive])}"
      }
    end

    # a process that holds a seat until told to stop
    defp holder(ip) do
      parent = self()

      pid =
        spawn(fn ->
          send(parent, {:held, self(), RateLimit.hold_seat(ip)})
          receive do: (:stop -> :ok)
        end)

      assert_receive {:held, ^pid, result}
      {pid, result}
    end

    test "up to the limit, then refused", %{ip: ip} do
      assert {_, :ok} = holder(ip)
      assert {_, :ok} = holder(ip)
      assert {_, {:error, :too_many}} = holder(ip)
    end

    test "another address is not affected", %{ip: ip, other: other} do
      holder(ip)
      holder(ip)
      assert {_, :ok} = holder(other)
    end

    test "the seat is let go when the process ends", %{ip: ip} do
      {a, :ok} = holder(ip)
      {_b, :ok} = holder(ip)
      assert {_, {:error, :too_many}} = holder(ip)

      ref = Process.monitor(a)
      send(a, :stop)
      assert_receive {:DOWN, ^ref, :process, ^a, _}
      # The registry hears of the exit a moment after we do, and there is no message to wait for,
      # so ask again for a short while rather than sleep a fixed time.
      assert eventually(fn -> match?({_, :ok}, holder(ip)) end)
    end

    defp eventually(fun, tries \\ 40) do
      cond do
        fun.() ->
          true

        tries == 0 ->
          false

        true ->
          receive do
          after
            25 -> eventually(fun, tries - 1)
          end
      end
    end
  end
end
