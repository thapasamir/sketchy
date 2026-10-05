defmodule BackendWeb.AvatarControllerTest do
  # A face sent along when making or joining a room
  use BackendWeb.ConnCase, async: true

  alias Backend.Avatar
  alias Backend.Rooms

  defp face(conn, code, id), do: ok_room(code, id).players[id].avatar
  defp ok_room(code, id), do: elem(Rooms.fetch_member_room(code, id), 1)

  test "a room made with a face gives its host that face", %{conn: conn} do
    response =
      post(conn, "/api/rooms", %{name: "Sam", avatar: %{eyes: 3, mouth: 4, hat: 5}})
      |> json_response(201)

    assert face(conn, response["code"], response["player_id"]) == %{eyes: 3, mouth: 4, hat: 5}
  end

  test "joining with a face gives that player it", %{conn: conn} do
    {:ok, %{code: code}} = Rooms.create_room("Host")

    response =
      post(conn, "/api/rooms/#{code}/join", %{name: "Pri", avatar: %{eyes: 1, mouth: 2, hat: 3}})
      |> json_response(200)

    assert face(conn, code, response["player_id"]) == %{eyes: 1, mouth: 2, hat: 3}
  end

  test "no face is fine: one is made", %{conn: conn} do
    response = post(conn, "/api/rooms", %{name: "Sam"}) |> json_response(201)
    assert {:ok, _} = Avatar.parse(face(conn, response["code"], response["player_id"]))
  end

  test "a face that isn't valid doesn't stop the room being made, it just isn't used", %{
    conn: conn
  } do
    for bad <- [%{eyes: 99, mouth: 0, hat: 0}, "face", 5, [1, 2], %{eyes: "x"}, %{}] do
      response = post(conn, "/api/rooms", %{name: "Sam", avatar: bad}) |> json_response(201)
      id = response["player_id"]
      assert face(conn, response["code"], id) == Avatar.from_seed(id), inspect(bad)
    end
  end

  test "the face of everyone is in what players are sent", %{conn: conn} do
    response =
      post(conn, "/api/rooms", %{name: "Sam", avatar: %{eyes: 3, mouth: 4, hat: 5}})
      |> json_response(201)

    {:ok, room} = Rooms.fetch_member_room(response["code"], response["player_id"])
    assert [%{avatar: %{eyes: 3, mouth: 4, hat: 5}}] = Backend.Rooms.Room.to_public(room).players
  end
end
