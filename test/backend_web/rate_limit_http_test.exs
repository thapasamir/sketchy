defmodule BackendWeb.RateLimitHttpTest do
  # The limits are an application setting shared by everything, so these can't run alongside others.
  use BackendWeb.ConnCase, async: false

  import Backend.RateLimitHelper

  # (going over a limit is logged, on purpose: it is expected here)
  @moduletag :capture_log

  alias Backend.Rooms

  # a request that seems to come from this address
  defp from(conn, ip), do: %{conn | remote_ip: ip}
  defp a, do: {10, 0, 0, 1}
  defp b, do: {10, 0, 0, 2}

  defp unique(prefix), do: "#{prefix}#{System.unique_integer([:positive])}"

  describe "what a refused request looks like" do
    setup do
      # guest: 60 * 0.05 = 3
      enable(0.05)
    end

    test "a 429, a plain message, and how long to wait", %{conn: conn} do
      for _ <- 1..3, do: assert(post(from(conn, a()), "/api/users/guest") |> json_response(201))

      refused = post(from(conn, a()), "/api/users/guest")
      assert %{"error" => "rate_limited", "message" => message} = json_response(refused, 429)
      assert message =~ ~r/wait/i
      assert [seconds] = get_resp_header(refused, "retry-after")
      assert String.to_integer(seconds) in 1..600
    end

    test "nothing is created for a refused request", %{conn: conn} do
      for _ <- 1..3, do: post(from(conn, a()), "/api/users/guest")
      before = Backend.Repo.aggregate(Backend.Accounts.User, :count)
      post(from(conn, a()), "/api/users/guest")
      assert Backend.Repo.aggregate(Backend.Accounts.User, :count) == before
    end
  end

  describe "guests" do
    setup do
      enable(0.05)
    end

    test "each address gets a few, and another address is not held back by it", %{conn: conn} do
      for _ <- 1..3, do: post(from(conn, a()), "/api/users/guest")
      assert post(from(conn, a()), "/api/users/guest") |> json_response(429)
      assert post(from(conn, b()), "/api/users/guest") |> json_response(201)
    end

    test "there is also a limit across everybody, however many addresses" do
      # guest_all: 1500 * 0.05 = 75, and each address may make 3: so 25 addresses use it all up
      for n <- 1..25,
          _ <- 1..3,
          do:
            assert(
              post(from(build_conn(), {10, 1, 0, n}), "/api/users/guest")
              |> json_response(201)
            )

      # a brand new address, well within its own limit, is still refused: the total is spent
      assert post(from(build_conn(), {10, 2, 0, 1}), "/api/users/guest") |> json_response(429)
    end
  end

  describe "accounts" do
    test "registering is limited more tightly than anything, as each one costs a slow hash", %{
      conn: conn
    } do
      # register: 10 * 0.1 = 1
      enable(0.1)
      name = unique("reg")
      params = fn n -> %{username: n, email: n <> "@example.com", password: "secret123"} end

      assert post(from(conn, a()), "/api/users/register", params.(name)) |> json_response(201)

      assert post(from(conn, a()), "/api/users/register", params.(name <> "x"))
             |> json_response(429)

      assert post(from(conn, b()), "/api/users/register", params.(name <> "y"))
             |> json_response(201)
    end

    test "a wrong password can be tried only so many times for one account, from any address", %{
      conn: conn
    } do
      # login_user: 10 * 0.1 = 1; login: 30 * 0.1 = 3
      enable(0.1)
      body = %{username: "someone", password: "nope"}

      assert post(from(conn, a()), "/api/users/login", body) |> json_response(401)
      assert post(from(conn, b()), "/api/users/login", body) |> json_response(429)
    end

    test "the account limit does not hold other accounts back", %{conn: conn} do
      enable(0.1)

      assert post(from(conn, a()), "/api/users/login", %{username: "one", password: "x"})
             |> json_response(401)

      assert post(from(conn, a()), "/api/users/login", %{username: "two", password: "x"})
             |> json_response(401)
    end

    test "the account is the same whatever the capitals", %{conn: conn} do
      enable(0.1)

      assert post(from(conn, a()), "/api/users/login", %{username: "Sam", password: "x"})
             |> json_response(401)

      assert post(from(conn, b()), "/api/users/login", %{username: "sAM", password: "x"})
             |> json_response(429)
    end

    test "logins are limited per address too", %{conn: conn} do
      enable(0.1)

      for n <- 1..3,
          do:
            assert(
              post(from(conn, a()), "/api/users/login", %{username: "u#{n}", password: "x"})
              |> json_response(401)
            )

      assert post(from(conn, a()), "/api/users/login", %{username: "u4", password: "x"})
             |> json_response(429)
    end

    test "the right password still works when not over a limit", %{conn: conn} do
      enable(1)
      name = unique("ok")

      post(from(conn, a()), "/api/users/register", %{
        username: name,
        email: name <> "@example.com",
        password: "secret123"
      })

      assert post(from(conn, a()), "/api/users/login", %{username: name, password: "secret123"})
             |> json_response(200)
    end

    test "login with something that isn't text is refused plainly, not with a crash", %{
      conn: conn
    } do
      enable(1)

      assert post(from(conn, a()), "/api/users/login", %{username: 123, password: ["x"]})
             |> json_response(422)
    end
  end

  describe "rooms" do
    test "making rooms is limited per address", %{conn: conn} do
      # room_create: 20 * 0.05 = 1
      enable(0.05)
      assert post(from(conn, a()), "/api/rooms", %{name: "One"}) |> json_response(201)
      assert post(from(conn, a()), "/api/rooms", %{name: "Two"}) |> json_response(429)
      assert post(from(conn, b()), "/api/rooms", %{name: "Three"}) |> json_response(201)
    end

    test "there is only room for so many rooms at once", %{conn: conn} do
      put_env(:max_rooms, Rooms.live_rooms())

      refused = post(conn, "/api/rooms", %{name: "Late"})
      assert %{"error" => "server_busy", "message" => message} = json_response(refused, 503)
      assert message =~ ~r/full/i
    end

    test "the cap does not stop people joining a room that exists", %{conn: conn} do
      {:ok, %{code: code}} = Rooms.create_room("Host")
      put_env(:max_rooms, 0)
      assert post(conn, "/api/rooms/#{code}/join", %{name: "Friend"}) |> json_response(200)
    end

    test "joining is limited per address", %{conn: conn} do
      # room_join: 60 * 0.05 = 3
      enable(0.05)
      {:ok, %{code: code}} = Rooms.create_room("Host")

      for n <- 1..3,
          do:
            assert(
              post(from(conn, a()), "/api/rooms/#{code}/join", %{name: "P#{n}"})
              |> json_response(200)
            )

      assert post(from(conn, a()), "/api/rooms/#{code}/join", %{name: "P4"}) |> json_response(429)
    end
  end

  describe "guessing room codes" do
    setup do
      # room_miss: 15 * 0.05 = 1; room_join: 3
      enable(0.05)
      {:ok, %{code: code}} = Rooms.create_room("Host")
      %{code: code}
    end

    test "a code that doesn't exist is allowed only so many times, then even real ones are refused",
         %{conn: conn, code: code} do
      assert post(from(conn, a()), "/api/rooms/ZZZZ/join", %{name: "Guess"}) |> json_response(404)

      assert post(from(conn, a()), "/api/rooms/YYYY/join", %{name: "Guess"}) |> json_response(429)

      assert post(from(conn, a()), "/api/rooms/#{code}/join", %{name: "Guess"})
             |> json_response(429)
    end

    test "another address is not held back by someone else's guessing", %{conn: conn, code: code} do
      post(from(conn, a()), "/api/rooms/ZZZZ/join", %{name: "Guess"})

      assert post(from(conn, b()), "/api/rooms/#{code}/join", %{name: "Friend"})
             |> json_response(200)
    end

    test "joining a room that exists never counts as a guess", %{conn: conn, code: code} do
      for n <- 1..3,
          do:
            assert(
              post(from(conn, a()), "/api/rooms/#{code}/join", %{name: "P#{n}"})
              |> json_response(200)
            )
    end

    test "a full room or a taken name doesn't count either (the code was right)", %{
      conn: conn,
      code: code
    } do
      assert post(from(conn, a()), "/api/rooms/#{code}/join", %{name: "Host"})
             |> json_response(409)

      assert post(from(conn, a()), "/api/rooms/#{code}/join", %{name: "Other"})
             |> json_response(200)
    end
  end

  describe "the whole API" do
    test "has a ceiling on how much one address may use", %{conn: conn} do
      # api: 300 * 0.05 = 15
      enable(0.05)
      for _ <- 1..15, do: assert(get(from(conn, a()), "/api/users/me") |> json_response(401))
      assert get(from(conn, a()), "/api/users/me") |> json_response(429)
      assert get(from(conn, b()), "/api/users/me") |> json_response(401)
    end

    test "but the pages and files are not counted", %{conn: conn} do
      enable(0.05)
      for _ <- 1..40, do: assert(get(from(conn, a()), "/") |> response(200))
    end
  end

  describe "with the limits off" do
    test "nothing is ever refused", %{conn: conn} do
      for _ <- 1..80, do: assert(post(from(conn, a()), "/api/users/guest") |> json_response(201))
    end
  end

  describe "who a request is from" do
    test "behind a trusted proxy, by the header and not by the proxy's own address", %{conn: conn} do
      # guest: 3
      enable(0.05)
      put_env(:client_ip_header, "fly-client-ip")
      proxy = {172, 16, 0, 1}

      as = fn conn, ip -> conn |> from(proxy) |> put_req_header("fly-client-ip", ip) end

      for _ <- 1..3,
          do: assert(post(as.(conn, "203.0.113.1"), "/api/users/guest") |> json_response(201))

      assert post(as.(conn, "203.0.113.1"), "/api/users/guest") |> json_response(429)
      # a different person behind the same proxy is not held back
      assert post(as.(conn, "203.0.113.2"), "/api/users/guest") |> json_response(201)
    end

    test "where no proxy is trusted, a header can't be used to dodge a limit", %{conn: conn} do
      enable(0.05)
      Application.delete_env(:backend, :client_ip_header)

      for _ <- 1..3,
          do:
            post(
              from(conn, a()) |> put_req_header("fly-client-ip", "9.9.9.1"),
              "/api/users/guest"
            )

      refused =
        post(from(conn, a()) |> put_req_header("fly-client-ip", "9.9.9.2"), "/api/users/guest")

      assert json_response(refused, 429)
    end
  end

  # characters that can't be written plainly in a source file, so they are made from their code points
  defp chars(codepoints), do: for(cp <- codepoints, into: "", do: <<cp::utf8>>)

  describe "names" do
    test "unseen and direction-changing characters are removed, runs of spaces become one", %{
      conn: conn
    } do
      zero_width_space = chars([0x200B])
      right_to_left_override = chars([0x202E])
      nul = chars([0])
      name = "  Sa" <> zero_width_space <> "m" <> right_to_left_override <> "  i" <> nul <> "r\n "

      response = post(conn, "/api/rooms", %{name: name}) |> json_response(201)
      assert {:ok, room} = Rooms.fetch_member_room(response["code"], response["player_id"])
      assert [%{name: "Sam ir"}] = Backend.Rooms.Room.to_public(room).players
    end

    test "a name made only of such characters is no name", %{conn: conn} do
      name = chars([0x200B, 0x200E, 0x202E])

      assert %{"error" => "name_required"} =
               post(conn, "/api/rooms", %{name: name}) |> json_response(422)
    end

    test "a compound emoji keeps the joiner inside it", %{conn: conn} do
      joiner = chars([0x200D])
      family = "👨" <> joiner <> "👩" <> joiner <> "👧"
      response = post(conn, "/api/rooms", %{name: family}) |> json_response(201)
      {:ok, room} = Rooms.fetch_member_room(response["code"], response["player_id"])
      assert [%{name: ^family}] = Backend.Rooms.Room.to_public(room).players
    end
  end
end
