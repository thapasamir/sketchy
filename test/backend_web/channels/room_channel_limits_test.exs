defmodule BackendWeb.RoomChannelLimitsTest do
  # The limits are an application setting shared by everything, so these can't run alongside others.
  use BackendWeb.ChannelCase, async: false

  import Backend.RateLimitHelper

  # (going over a limit is logged, on purpose: it is expected here)
  @moduletag :capture_log

  alias Backend.Rooms
  alias BackendWeb.{RoomChannel, UserSocket}

  defp socket_from(ip), do: socket(UserSocket, "test", %{client_ip: ip})

  defp enter(ip, code, player_id),
    do:
      subscribe_and_join(socket_from(ip), RoomChannel, "room:" <> code, %{
        "player_id" => player_id
      })

  defp ip, do: "ip-#{System.unique_integer([:positive])}"

  defp room_with_host do
    {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
    %{code: code, host: host}
  end

  # push `n` messages as fast as possible and collect how each was answered
  defp blast(socket, event, n) do
    refs = for _ <- 1..n, do: push(socket, event, %{})

    for ref <- refs do
      assert_reply ref, status, payload
      {status, payload}
    end
  end

  defp limited?({:error, %{reason: "rate_limited"}}), do: true
  defp limited?(_), do: false

  describe "how fast one connection may send" do
    setup do
      enable()
      %{code: code, host: host} = room_with_host()
      {:ok, _, socket} = enter(ip(), code, host)
      %{socket: socket}
    end

    test "ordinary messages: a short burst is fine, a flood is refused", %{socket: socket} do
      results = blast(socket, "finish_turn", 30)

      # the first 20 are answered by the room (it says it isn't their turn), the rest are refused
      assert Enum.take(results, 20) |> Enum.reject(&limited?/1) |> length() == 20
      assert Enum.drop(results, 20) |> Enum.all?(&limited?/1)
    end

    test "drawing is allowed much more, because the points come in fast", %{socket: socket} do
      results = blast(socket, "draw", 100)
      refute Enum.any?(results, &limited?/1)
    end

    test "asking for the whole picture again is allowed only now and then", %{socket: socket} do
      results = blast(socket, "sync", 9)
      assert Enum.count(results, &limited?/1) >= 3
      refute limited?(hd(results))
    end

    test "a connection that keeps going is closed, not just refused", %{socket: socket} do
      Process.flag(:trap_exit, true)
      ref = Process.monitor(socket.channel_pid)

      for _ <- 1..90, do: push(socket, "finish_turn", %{})

      assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :rate_limited}}, 1_000
    end

    test "a message the server doesn't know gets an answer, and the connection survives", %{
      socket: socket
    } do
      ref = push(socket, "no_such_thing", %{})
      assert_reply ref, :error, %{reason: "unknown_event"}
      assert Process.alive?(socket.channel_pid)
    end
  end

  describe "when the limits are off" do
    test "nothing is refused" do
      %{code: code, host: host} = room_with_host()
      {:ok, _, socket} = enter(ip(), code, host)
      refute Enum.any?(blast(socket, "finish_turn", 60), &limited?/1)
    end
  end

  describe "one address, many connections" do
    setup do
      enable(1, seats_per_ip: 2)
      :ok
    end

    test "only so many at once, and a third is turned away" do
      mine = ip()
      %{code: code, host: host} = room_with_host()
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
      {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")

      assert {:ok, _, _} = enter(mine, code, host)
      assert {:ok, _, _} = enter(mine, code, p2)
      assert {:error, %{reason: "too_many_connections"}} = enter(mine, code, p3)
    end

    test "someone on another address is not affected" do
      mine = ip()
      %{code: code, host: host} = room_with_host()
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
      {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")

      {:ok, _, _} = enter(mine, code, host)
      {:ok, _, _} = enter(mine, code, p2)
      assert {:ok, _, _} = enter(ip(), code, p3)
    end

    test "a seat is free again once its connection closes" do
      mine = ip()
      %{code: code, host: host} = room_with_host()
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
      {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")

      {:ok, _, first} = enter(mine, code, host)
      {:ok, _, _} = enter(mine, code, p2)
      assert {:error, %{reason: "too_many_connections"}} = enter(mine, code, p3)

      Process.flag(:trap_exit, true)
      ref = Process.monitor(first.channel_pid)
      leave(first)
      assert_receive {:DOWN, ^ref, :process, _, _}

      assert eventually(fn -> match?({:ok, _, _}, enter(mine, code, p3)) end)
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

  describe "how fast one address may join" do
    test "a few joins a minute, then it is told to wait" do
      # channel_join: 30 * 0.1 = 3
      enable(0.1, seats_per_ip: 100)
      mine = ip()
      %{code: code, host: host} = room_with_host()

      for _ <- 1..3, do: assert({:ok, _, _} = enter(mine, code, host))
      assert {:error, %{reason: "rate_limited"}} = enter(mine, code, host)
      assert {:ok, _, _} = enter(ip(), code, host)
    end
  end
end
