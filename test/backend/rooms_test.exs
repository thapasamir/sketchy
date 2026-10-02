defmodule Backend.RoomsTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.RoomServer

  describe "create_room/1" do
    test "starts a room with the creator as host and only player" do
      assert {:ok, %{code: code, player_id: player_id}} = Rooms.create_room("Samir")

      assert code =~ ~r/\A[A-Z]{4}\z/
      assert {:ok, room} = RoomServer.get_state(code)
      assert room.host_id == player_id
      assert room.phase == :lobby
      assert [%{id: ^player_id, name: "Samir"}] = Map.values(room.players)
    end

    test "trims the name" do
      {:ok, %{code: code}} = Rooms.create_room("  Samir  ")
      {:ok, room} = RoomServer.get_state(code)
      assert [%{name: "Samir"}] = Map.values(room.players)
    end

    test "rejects blank and too long names" do
      assert {:error, :name_required} = Rooms.create_room("   ")
      assert {:error, :name_required} = Rooms.create_room(nil)
      assert {:error, :name_too_long} = Rooms.create_room(String.duplicate("a", 21))
    end

    test "gives every room its own code" do
      codes = for _ <- 1..100, do: elem(Rooms.create_room("p"), 1).code
      assert length(Enum.uniq(codes)) == 100
    end
  end

  describe "isolation" do
    test "a crashed room is not restarted and does not affect other rooms" do
      {:ok, %{code: doomed}} = Rooms.create_room("A")
      {:ok, %{code: survivor}} = Rooms.create_room("B")

      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, doomed)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # wait until the supervisor has handled the exit before looking
      _ = :sys.get_state(Backend.RoomSupervisor)

      assert {:error, :room_not_found} = RoomServer.get_state(doomed)
      assert {:ok, _room} = RoomServer.get_state(survivor)
    end
  end

  describe "join_room/2" do
    test "adds a second player and the code is case-insensitive" do
      {:ok, %{code: code}} = Rooms.create_room("Samir")

      assert {:ok, %{code: ^code, player_id: id}} =
               Rooms.join_room(String.downcase(code), " Priya ")

      assert {:ok, room} = RoomServer.get_state(code)
      assert map_size(room.players) == 2
      assert room.players[id].name == "Priya"
    end

    test "reports why a join failed" do
      {:ok, %{code: code}} = Rooms.create_room("Samir")

      assert {:error, :room_not_found} = Rooms.join_room("ZZZZ", "Priya")
      assert {:error, :name_taken} = Rooms.join_room(code, "samir")
      assert {:error, :name_required} = Rooms.join_room(code, "  ")
    end

    test "two people grabbing the last seat at once: exactly one gets it" do
      {:ok, %{code: code}} = Rooms.create_room("host")
      for i <- 1..6, do: {:ok, _} = Rooms.join_room(code, "p#{i}")

      results =
        1..10
        |> Task.async_stream(fn i -> Rooms.join_room(code, "racer#{i}") end, max_concurrency: 10)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :room_full}, &1)) == 9
      {:ok, room} = RoomServer.get_state(code)
      assert map_size(room.players) == 8
    end

    test "subscribers are told when someone joins" do
      {:ok, %{code: code}} = Rooms.create_room("Samir")
      Rooms.subscribe(code)

      {:ok, _} = Rooms.join_room(code, "Priya")
      assert_receive {:room_updated, %{players: players}}
      assert map_size(players) == 2
    end
  end

  describe "fetch_member_room/2" do
    test "only members get the room, and the code is case-insensitive" do
      {:ok, %{code: code, player_id: id}} = Rooms.create_room("Samir")

      assert {:ok, %{code: ^code}} = Rooms.fetch_member_room(String.downcase(code), id)
      assert {:error, :not_a_member} = Rooms.fetch_member_room(code, "someone-else")
      assert {:error, :room_not_found} = Rooms.fetch_member_room("ZZZZ", id)
    end
  end
end
