defmodule BackendWeb.UserControllerTest do
  use BackendWeb.ConnCase, async: true

  alias Backend.Rooms

  @creds %{username: "samir", email: "s@example.com", password: "secret123"}

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  test "register, login and guest all return a signed token", %{conn: conn} do
    assert %{"token" => t1, "user_type" => "registered", "username" => "samir"} =
             conn |> post("/api/users/register", @creds) |> json_response(201)

    assert %{"token" => t2} =
             build_conn()
             |> post("/api/users/login", %{username: "samir", password: "secret123"})
             |> json_response(200)

    assert %{"token" => t3, "user_type" => "guest"} =
             build_conn() |> post("/api/users/guest") |> json_response(201)

    assert Enum.all?([t1, t2, t3], &(is_binary(&1) and &1 != ""))
  end

  describe "GET /api/users/me" do
    test "returns who the token belongs to", %{conn: conn} do
      %{"token" => token, "user_id" => id} =
        conn |> post("/api/users/register", @creds) |> json_response(201)

      assert %{"user_id" => ^id, "username" => "samir", "user_type" => "registered"} =
               build_conn() |> bearer(token) |> get("/api/users/me") |> json_response(200)
    end

    test "rejects a missing token", %{conn: conn} do
      assert conn |> get("/api/users/me") |> json_response(401)
    end

    test "rejects a made-up or edited token", %{conn: conn} do
      %{"token" => token} = conn |> post("/api/users/register", @creds) |> json_response(201)

      assert build_conn() |> bearer("not-a-token") |> get("/api/users/me") |> json_response(401)
      assert build_conn() |> bearer(token <> "x") |> get("/api/users/me") |> json_response(401)
    end

    test "rejects a token whose user no longer exists", %{conn: conn} do
      %{"token" => token, "user_id" => id} =
        conn |> post("/api/users/guest") |> json_response(201)

      Backend.Repo.delete!(Backend.Accounts.get_user(id))
      assert build_conn() |> bearer(token) |> get("/api/users/me") |> json_response(401)
    end
  end

  test "a registered user always plays under their username, whatever name is sent", %{conn: conn} do
    %{"token" => token} = conn |> post("/api/users/register", @creds) |> json_response(201)

    %{"code" => code} =
      build_conn()
      |> bearer(token)
      |> post("/api/rooms", %{name: "Somebody Else"})
      |> json_response(201)

    {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
    assert [%{name: "samir"}] = Map.values(room.players)
  end

  test "joining a room as a registered user also uses the username", %{conn: conn} do
    %{"token" => token} = conn |> post("/api/users/register", @creds) |> json_response(201)
    {:ok, %{code: code}} = Rooms.create_room("Host")

    assert %{"player_id" => id} =
             build_conn()
             |> bearer(token)
             |> post("/api/rooms/#{code}/join", %{name: "Somebody Else"})
             |> json_response(200)

    {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
    assert room.players[id].name == "samir"
  end

  test "guests choose their own name", %{conn: conn} do
    %{"token" => token} = conn |> post("/api/users/guest") |> json_response(201)

    %{"code" => code} =
      build_conn() |> bearer(token) |> post("/api/rooms", %{name: "Alice"}) |> json_response(201)

    {:ok, room} = Backend.Rooms.RoomServer.get_state(code)
    assert [%{name: "Alice"}] = Map.values(room.players)
  end
end
