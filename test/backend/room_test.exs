defmodule Backend.Rooms.RoomTest do
  use ExUnit.Case, async: true

  alias Backend.Rooms.Room

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
end
