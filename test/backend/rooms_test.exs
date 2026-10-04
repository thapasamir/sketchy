defmodule Backend.RoomsTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms
  alias Backend.Rooms.{Room, RoomServer}

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

    test "subscribers are told when the new player's connection arrives" do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Samir")
      Rooms.connect(code, host, self())
      Rooms.subscribe(code)

      {:ok, %{player_id: id}} = Rooms.join_room(code, "Priya")
      refute_receive {:room_updated, _}, 50

      {:ok, _} = Rooms.connect(code, id, self())
      assert_receive {:room_updated, %{players: %{^id => %{connected?: true}}}}
    end
  end

  # A stand-in for a channel process: alive until told to stop
  defp fake_connection do
    spawn(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp stop(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
  end

  describe "connections" do
    setup do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      {:ok, %{player_id: guest}} = Rooms.join_room(code, "Guest")
      host_conn = fake_connection()
      guest_conn = fake_connection()
      {:ok, _} = Rooms.connect(code, host, host_conn)
      {:ok, _} = Rooms.connect(code, guest, guest_conn)
      Rooms.subscribe(code)
      %{code: code, host: host, guest: guest, host_conn: host_conn, guest_conn: guest_conn}
    end

    test "only members can connect", %{code: code} do
      assert {:error, :not_a_member} = Rooms.connect(code, "stranger", self())
      assert {:error, :room_not_found} = Rooms.connect("ZZZZ", "x", self())
    end

    test "a dropped connection marks the player away, then removes them after the grace period",
         %{code: code, guest: guest, guest_conn: conn} do
      stop(conn)

      assert_receive {:room_updated, %{players: %{^guest => %{connected?: false}}}}, 1000
      {:ok, room} = RoomServer.get_state(code)
      assert Map.has_key?(room.players, guest), "still has a seat during the grace period"

      assert_receive {:room_updated, room}, 2000
      refute Map.has_key?(room.players, guest)
    end

    test "reconnecting inside the grace period keeps the seat", %{
      code: code,
      guest: guest,
      guest_conn: conn
    } do
      stop(conn)
      assert_receive {:room_updated, %{players: %{^guest => %{connected?: false}}}}, 1000

      {:ok, _} = Rooms.connect(code, guest, fake_connection())
      assert_receive {:room_updated, %{players: %{^guest => %{connected?: true}}}}, 1000

      refute_receive {:room_updated, _}, 700
      {:ok, room} = RoomServer.get_state(code)
      assert room.players[guest].connected?
    end

    test "a player with two tabs is only away when both are gone", %{
      code: code,
      guest: guest,
      guest_conn: tab1
    } do
      tab2 = fake_connection()
      {:ok, _} = Rooms.connect(code, guest, tab2)
      assert_receive {:room_updated, _}, 1000

      stop(tab1)
      refute_receive {:room_updated, _}, 100
      {:ok, room} = RoomServer.get_state(code)
      assert room.players[guest].connected?

      stop(tab2)
      assert_receive {:room_updated, %{players: %{^guest => %{connected?: false}}}}, 1000
    end

    test "leaving on purpose frees the seat immediately and the stale connection is ignored", %{
      code: code,
      guest: guest,
      guest_conn: conn
    } do
      assert :ok = Rooms.leave(code, guest)
      assert_receive {:room_updated, room}, 1000
      refute Map.has_key?(room.players, guest)

      stop(conn)
      refute_receive {:room_updated, _}, 100
    end

    test "when the host leaves, the next player becomes host", %{
      code: code,
      host: host,
      guest: guest
    } do
      :ok = Rooms.leave(code, host)
      assert_receive {:room_updated, room}, 1000
      assert room.host_id == guest
    end

    test "the room closes when the last player leaves", %{code: code, host: host, guest: guest} do
      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      ref = Process.monitor(pid)

      :ok = Rooms.leave(code, host)
      :ok = Rooms.leave(code, guest)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert {:error, :room_not_found} = RoomServer.get_state(code)
    end

    test "the room closes when everyone drops and nobody comes back", %{
      code: code,
      host_conn: host_conn,
      guest_conn: guest_conn
    } do
      [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
      ref = Process.monitor(pid)

      stop(host_conn)
      stop(guest_conn)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
    end
  end

  test "a room nobody ever connects to closes itself" do
    {:ok, %{code: code}} = Rooms.create_room("Ghost")
    [{pid, _}] = Registry.lookup(Backend.RoomRegistry, code)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2000
  end

  describe "settings and starting" do
    setup do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Host")
      {:ok, %{player_id: p2}} = Rooms.join_room(code, "Two")
      {:ok, %{player_id: p3}} = Rooms.join_room(code, "Three")
      for id <- [host, p2, p3], do: {:ok, _} = Rooms.connect(code, id, fake_connection())
      %{code: code, host: host, p2: p2, p3: p3}
    end

    test "ready flags are shared with everyone and cleared when settings change", %{
      code: code,
      host: host,
      p2: p2
    } do
      Rooms.subscribe(code)
      {:ok, _} = Rooms.set_ready(code, p2, true)
      assert_receive {:room_updated, %{players: %{^p2 => %{ready?: true}}}}

      {:ok, _} = Rooms.update_settings(code, host, %{"rounds" => 4})
      assert_receive {:room_updated, %{players: %{^p2 => %{ready?: false}}}}
    end

    test "the host removes a player: they're told, the others see the new list", %{
      code: code,
      host: host,
      p2: p2
    } do
      Rooms.subscribe(code)
      assert :ok = Rooms.kick(code, host, p2)

      assert_receive {:player_kicked, ^p2}
      assert_receive {:room_updated, room}
      refute Map.has_key?(room.players, p2)
    end

    test "kick is refused for non-hosts, the host and strangers", %{
      code: code,
      host: host,
      p2: p2,
      p3: p3
    } do
      assert {:error, :not_host} = Rooms.kick(code, p2, p3)
      assert {:error, :host_cannot} = Rooms.kick(code, host, host)
      assert {:error, :not_a_member} = Rooms.kick(code, host, "ghost")
    end

    test "a removed player can come back in with a fresh seat", %{code: code, host: host, p2: p2} do
      :ok = Rooms.kick(code, host, p2)
      assert {:ok, %{player_id: new_id}} = Rooms.join_room(code, "Two")
      assert new_id != p2
    end

    test "the host changes settings; everyone gets the update", %{code: code, host: host} do
      Rooms.subscribe(code)
      assert {:ok, _} = Rooms.update_settings(code, host, %{"rounds" => 4, "draw_time" => 90})
      assert_receive {:room_updated, %{settings: %{rounds: 4, draw_time: 90}}}
    end

    test "a non-host cannot", %{code: code, p2: p2} do
      assert {:error, :not_host} = Rooms.update_settings(code, p2, %{"rounds" => 4})
      assert {:error, :not_host} = Rooms.start_game(code, p2)
    end

    test "bad values are refused", %{code: code, host: host} do
      assert {:error, :invalid_settings} = Rooms.update_settings(code, host, %{"rounds" => 9})
      assert {:error, :invalid_settings} = Rooms.update_settings(code, host, %{"draw_time" => 45})
      assert {:error, :invalid_settings} = Rooms.update_settings(code, host, %{"rounds" => "3"})
    end

    test "the host starts the game, after which nothing in the lobby can change", %{
      code: code,
      host: host,
      p2: p2,
      p3: p3
    } do
      assert {:error, :not_all_ready} = Rooms.start_game(code, host)
      {:ok, _} = Rooms.set_ready(code, p2, true)
      {:ok, _} = Rooms.set_ready(code, p3, true)

      assert {:ok, %{phase: :reveal}} = Rooms.start_game(code, host)
      assert {:error, :game_in_progress} = Rooms.start_game(code, host)
      assert {:error, :game_in_progress} = Rooms.update_settings(code, host, %{"rounds" => 4})
      assert {:error, :not_host} = Rooms.update_settings(code, p2, %{"rounds" => 4})
    end

    test "someone who arrives after the start joins as a spectator, not a player", %{
      code: code,
      host: host,
      p2: p2,
      p3: p3
    } do
      {:ok, _} = Rooms.set_ready(code, p2, true)
      {:ok, _} = Rooms.set_ready(code, p3, true)
      {:ok, _} = Rooms.start_game(code, host)

      assert {:ok, %{player_id: late}} = Rooms.join_room(code, "Late")
      {:ok, room} = RoomServer.get_state(code)
      assert Room.spectator?(room, late)
      # not dealt a card, not in the turn order, not given a colour
      assert Room.secret_for(room, late) == nil
      refute late in room.game.turn_order
      refute Map.has_key?(room.game.colors, late)
    end

    test "starting deals exactly one imposter, and only the imposter lacks the word", %{
      code: code,
      host: host,
      p2: p2,
      p3: p3
    } do
      {:ok, _} = Rooms.set_ready(code, p2, true)
      {:ok, _} = Rooms.set_ready(code, p3, true)
      {:ok, room} = Rooms.start_game(code, host)

      secrets = for id <- [host, p2, p3], do: Room.secret_for(room, id)
      assert Enum.count(secrets, &(&1.role == "imposter")) == 1
      assert [%{word: word}] = secrets |> Enum.filter(&(&1.role == "crew")) |> Enum.uniq()
      assert Enum.all?(secrets, &(&1.category == hd(secrets).category))

      imposter = Enum.find(secrets, &(&1.role == "imposter"))
      refute word in [imposter.hint, imposter.category]
    end

    test "the reveal ends by itself and drawing begins", %{code: code, host: host, p2: p2, p3: p3} do
      Rooms.subscribe(code)
      {:ok, _} = Rooms.set_ready(code, p2, true)
      {:ok, _} = Rooms.set_ready(code, p3, true)
      {:ok, _} = Rooms.start_game(code, host)

      assert_receive {:room_updated, %{phase: :reveal}}
      assert_receive {:room_updated, %{phase: :drawing}}, 2000
    end

    test "starting needs enough connected players" do
      {:ok, %{code: code, player_id: host}} = Rooms.create_room("Solo")
      {:ok, _} = Rooms.connect(code, host, fake_connection())
      assert {:error, :not_enough_players} = Rooms.start_game(code, host)
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
