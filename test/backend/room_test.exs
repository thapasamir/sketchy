defmodule Backend.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.Room

  defp deal(imposter \\ "p1") do
    %{
      imposter_id: imposter,
      imposter_history: [imposter],
      entry: %{
        category: "Animals",
        word: "Giraffe",
        difficulty: "easy",
        hints: ["tall", "savanna", "spots"]
      },
      hint: "savanna",
      used_words: ["Giraffe"],
      turn_order: ["p0", "p1", "p2"]
    }
  end

  defp room_with(names) do
    names
    |> Enum.with_index()
    |> Enum.reduce(Room.new("ABCD", "p0"), fn {name, i}, room ->
      Room.add_player(room, "p#{i}", name)
    end)
  end

  test "a new name joins" do
    assert {:ok, room} = Room.join(room_with(["Samir"]), "p9", "Priya")
    assert Room.player_count(room) == 2
  end

  test "names are unique ignoring case" do
    assert {:error, :name_taken} = Room.join(room_with(["Samir"]), "p9", "sAmIr")
  end

  test "a room holds at most 8 players" do
    full = room_with(for i <- 1..8, do: "player#{i}")
    assert {:error, :room_full} = Room.join(full, "p9", "late")
  end

  test "nobody joins once the game started" do
    started = %{room_with(["Samir"]) | phase: :drawing}
    assert {:error, :game_in_progress} = Room.join(started, "p9", "Priya")
  end

  describe "remove_player/2" do
    test "the host leaving passes the host role to the longest-present connected player" do
      room =
        room_with(["Host", "Two", "Three"])
        |> Room.set_connected("p1", false)
        |> Room.set_connected("p2", true)

      room = Room.remove_player(room, "p0")
      assert room.host_id == "p2"
    end

    test "a non-host leaving leaves the host alone" do
      room = Room.remove_player(room_with(["Host", "Two"]), "p1")
      assert room.host_id == "p0"
      assert Room.player_count(room) == 1
    end

    test "the last player leaving leaves no host" do
      assert %{host_id: nil, players: players} = Room.remove_player(room_with(["Host"]), "p0")
      assert players == %{}
    end
  end

  describe "settings" do
    test "partial updates keep the other value" do
      assert {:ok, room} = Room.update_settings(room_with(["H"]), "p0", %{rounds: 4})
      assert room.settings == %{rounds: 4, draw_time: 30}
    end

    test "limits: rounds 2-4, draw time 30-90 in steps of 10" do
      room = room_with(["H"])

      for rounds <- [1, 5, 2.5],
          do:
            assert(
              {:error, :invalid_settings} = Room.update_settings(room, "p0", %{rounds: rounds})
            )

      for t <- [20, 100, 35],
          do:
            assert(
              {:error, :invalid_settings} = Room.update_settings(room, "p0", %{draw_time: t})
            )

      assert {:ok, _} = Room.update_settings(room, "p0", %{rounds: 2, draw_time: 30})
      assert {:ok, _} = Room.update_settings(room, "p0", %{rounds: 4, draw_time: 90})
    end
  end

  describe "start_game/2" do
    defp connected(room),
      do: Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))

    defp all_ready(room) do
      room.players
      |> Map.keys()
      |> Enum.reject(&(&1 == room.host_id))
      |> Enum.reduce(room, fn id, room -> elem(Room.set_ready(room, id, true), 1) end)
    end

    test "needs three connected players" do
      assert {:error, :not_enough_players} =
               Room.start_game(connected(room_with(["A", "B"])), "p0", deal())

      assert {:error, :not_enough_players} =
               Room.start_game(room_with(["A", "B", "C"]), "p0", deal())
    end

    test "needs every connected non-host player to be ready" do
      room = connected(room_with(["A", "B", "C"]))
      assert {:error, :not_all_ready} = Room.start_game(room, "p0", deal())

      {:ok, room} = Room.set_ready(room, "p1", true)
      assert {:error, :not_all_ready} = Room.start_game(room, "p0", deal())

      {:ok, room} = Room.set_ready(room, "p2", true)
      assert {:ok, %{phase: :reveal}} = Room.start_game(room, "p0", deal())
    end

    test "a player who is away doesn't hold up the start" do
      room = connected(room_with(["A", "B", "C", "D"])) |> Room.set_connected("p3", false)
      assert {:ok, %{phase: :reveal}} = Room.start_game(all_ready(room), "p0", deal())
    end

    test "only the host starts" do
      room = all_ready(connected(room_with(["A", "B", "C"])))
      assert {:error, :not_host} = Room.start_game(room, "p1", deal())
    end
  end

  describe "set_ready/3" do
    test "toggles for a regular player" do
      {:ok, room} = Room.set_ready(room_with(["Host", "B"]), "p1", true)
      assert room.players["p1"].ready?
      {:ok, room} = Room.set_ready(room, "p1", false)
      refute room.players["p1"].ready?
    end

    test "the host, strangers, non-booleans and started games are refused" do
      room = room_with(["Host", "B"])
      assert {:error, :host_cannot} = Room.set_ready(room, "p0", true)
      assert {:error, :not_a_member} = Room.set_ready(room, "nobody", true)
      assert {:error, :invalid_ready} = Room.set_ready(room, "p1", "yes")
      assert {:error, :game_in_progress} = Room.set_ready(%{room | phase: :playing}, "p1", true)
    end

    test "changing a setting clears everyone's ready; saving the same values does not" do
      {:ok, room} = Room.set_ready(room_with(["Host", "B"]), "p1", true)

      {:ok, same} = Room.update_settings(room, "p0", %{rounds: room.settings.rounds})
      assert same.players["p1"].ready?

      {:ok, changed} = Room.update_settings(room, "p0", %{rounds: 4})
      refute changed.players["p1"].ready?
    end
  end

  describe "can_kick/3" do
    test "the host may remove another player" do
      assert :ok = Room.can_kick(room_with(["Host", "B"]), "p0", "p1")
    end

    test "nobody else, not the host themselves, not strangers, not after the start" do
      room = room_with(["Host", "B", "C"])
      assert {:error, :not_host} = Room.can_kick(room, "p1", "p2")
      assert {:error, :host_cannot} = Room.can_kick(room, "p0", "p0")
      assert {:error, :not_a_member} = Room.can_kick(room, "p0", "ghost")
      assert {:error, :game_in_progress} = Room.can_kick(%{room | phase: :playing}, "p0", "p1")
    end
  end

  describe "the secret of a round" do
    defp started do
      room = room_with(["Host", "Crew", "Spy"])
      room = Enum.reduce(Map.keys(room.players), room, &Room.set_connected(&2, &1, true))
      {:ok, room} = Room.set_ready(room, "p1", true)
      {:ok, room} = Room.set_ready(room, "p2", true)
      {:ok, room} = Room.start_game(room, "p0", deal("p2"))
      room
    end

    test "there is no secret in the lobby" do
      assert Room.secret_for(room_with(["Host"]), "p0") == nil
    end

    test "everyone except the imposter is told the word" do
      room = started()
      assert %{role: "crew", word: "Giraffe", category: "Animals"} = Room.secret_for(room, "p0")
      assert %{role: "crew", word: "Giraffe"} = Room.secret_for(room, "p1")
    end

    test "the imposter gets the category and a hint, and never the word" do
      secret = Room.secret_for(started(), "p2")
      assert secret == %{role: "imposter", category: "Animals", hint: "savanna"}
      refute Map.has_key?(secret, :word)
    end

    test "strangers learn nothing" do
      assert Room.secret_for(started(), "stranger") == nil
    end

    test "the public view of the room never contains the secret" do
      public = started() |> Room.to_public() |> inspect()
      refute public =~ "Giraffe"
      refute public =~ "savanna"
      refute public =~ "imposter"
    end

    test "the reveal ends in the drawing phase, and only once" do
      assert {:ok, %{phase: :drawing}} = Room.end_reveal(started(), 0, 1000)
      assert {:error, :not_revealing} = Room.end_reveal(room_with(["Host"]), 0, 1000)
    end
  end
end
