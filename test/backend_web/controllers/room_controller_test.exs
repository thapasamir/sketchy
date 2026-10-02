defmodule BackendWeb.RoomControllerTest do
  use BackendWeb.ConnCase, async: true

  test "POST /api/rooms creates a room", %{conn: conn} do
    conn = post(conn, "/api/rooms", %{name: "Samir"})

    assert %{"code" => code, "player_id" => player_id} = json_response(conn, 201)
    assert code =~ ~r/\A[A-Z]{4}\z/
    assert {:ok, _room} = Backend.Rooms.fetch_member_room(code, player_id)
  end

  test "POST /api/rooms without a name is a 422", %{conn: conn} do
    conn = post(conn, "/api/rooms", %{name: "  "})
    assert %{"error" => "name_required"} = json_response(conn, 422)

    conn = post(build_conn(), "/api/rooms", %{})
    assert %{"error" => "name_required"} = json_response(conn, 422)
  end
end
