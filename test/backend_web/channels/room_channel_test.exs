defmodule BackendWeb.RoomChannelTest do
  use BackendWeb.ChannelCase, async: true

  alias Backend.Rooms
  alias BackendWeb.{RoomChannel, UserSocket}

  defp join_room(topic, params) do
    UserSocket |> socket("test", %{}) |> subscribe_and_join(RoomChannel, topic, params)
  end

  test "a member joins and receives the public room state" do
    {:ok, %{code: code, player_id: id}} = Rooms.create_room("Samir")

    assert {:ok, reply, _socket} = join_room("room:" <> code, %{"player_id" => id})
    assert reply.you == id
    assert %{code: ^code, host_id: ^id, players: [%{id: ^id, name: "Samir"}]} = reply.room
  end

  test "someone who is not in the room is rejected" do
    {:ok, %{code: code}} = Rooms.create_room("Samir")

    assert {:error, %{reason: "not_a_member"}} =
             join_room("room:" <> code, %{"player_id" => "nope"})
  end

  test "an unknown room is rejected" do
    assert {:error, %{reason: "room_not_found"}} = join_room("room:ZZZZ", %{"player_id" => "x"})
  end

  test "joining without a player_id is rejected" do
    {:ok, %{code: code}} = Rooms.create_room("Samir")
    assert {:error, %{reason: "player_id_required"}} = join_room("room:" <> code, %{})
  end
end
