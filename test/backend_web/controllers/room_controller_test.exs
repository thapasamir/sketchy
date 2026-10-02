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

  describe "POST /api/rooms/:code/join" do
    setup do
      {:ok, %{code: code}} = Backend.Rooms.create_room("Samir")
      %{code: code}
    end

    test "joins the room", %{conn: conn, code: code} do
      conn = post(conn, "/api/rooms/#{code}/join", %{name: "Priya"})
      assert %{"code" => ^code, "player_id" => id} = json_response(conn, 200)
      assert {:ok, _room} = Backend.Rooms.fetch_member_room(code, id)
    end

    test "unknown room is a 404", %{conn: conn} do
      conn = post(conn, "/api/rooms/ZZZZ/join", %{name: "Priya"})
      assert %{"error" => "room_not_found"} = json_response(conn, 404)
    end

    test "duplicate name is a 409", %{conn: conn, code: code} do
      conn = post(conn, "/api/rooms/#{code}/join", %{name: "samir"})
      assert %{"error" => "name_taken"} = json_response(conn, 409)
    end

    test "missing name is a 422", %{conn: conn, code: code} do
      conn = post(conn, "/api/rooms/#{code}/join", %{})
      assert %{"error" => "name_required"} = json_response(conn, 422)
    end
  end
end
