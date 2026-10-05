defmodule BackendWeb.RoomController do
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Backend.RateLimit
  alias Backend.Rooms
  alias BackendWeb.Plugs.RateLimit, as: Limit

  # Each room is a running process, so how fast one address can make them is limited, as is how
  # fast it can try to join (see Backend.RateLimit).
  plug Limit, [policy: :room_create] when action == :create
  plug Limit, [policy: :room_join] when action == :join

  # POST /api/rooms   body: {"name": "Samir"}
  def create(conn, %{"name" => name}) do
    respond(conn, Rooms.create_room(display_name(conn, name)), :created)
  end

  def create(conn, _params), do: error(conn, :name_required)

  # POST /api/rooms/ABCD/join   body: {"name": "Priya"}
  def join(conn, %{"code" => code, "name" => name}) do
    ip = conn.assigns[:client_ip] || "unknown"

    # Rooms are found by a four-letter code (about 330,000 of them), so trying codes one after
    # another is a way to find rooms to disturb. Joining one that doesn't exist is allowed only a few
    # times, and once the address has used them up it can't try any more for a while.
    case RateLimit.blocked?(:room_miss, ip) do
      {:blocked, retry_ms} ->
        Limit.reject(conn, retry_ms)

      false ->
        result = Rooms.join_room(code, display_name(conn, name))
        if result == {:error, :room_not_found}, do: RateLimit.hit(:room_miss, ip)
        respond(conn, result, :ok)
    end
  end

  def join(conn, _params), do: error(conn, :name_required)

  # A logged-in account always plays under its username; the name in the request is ignored,
  # so nobody can pose as someone else. Guests choose their own name.
  defp display_name(conn, requested) do
    case conn.assigns[:current_user] do
      %{user_type: "registered", username: username} -> username
      _ -> requested
    end
  end

  defp respond(conn, {:ok, %{code: code, player_id: player_id}}, status) do
    conn |> put_status(status) |> json(%{code: code, player_id: player_id})
  end

  defp respond(conn, {:error, reason}, _status), do: error(conn, reason)

  defp error(conn, reason) do
    conn
    |> put_status(status(reason))
    |> json(%{error: Atom.to_string(reason), message: message(reason)})
  end

  defp status(:name_required), do: :unprocessable_entity
  defp status(:name_too_long), do: :unprocessable_entity
  defp status(:room_not_found), do: :not_found
  defp status(:room_full), do: :conflict
  defp status(:name_taken), do: :conflict
  defp status(:game_in_progress), do: :conflict
  defp status(_), do: :service_unavailable

  defp message(:name_required), do: "Please enter your name"
  defp message(:name_too_long), do: "Name must be 20 characters or fewer"
  defp message(:room_not_found), do: "No room with that code. Check the letters and try again"
  defp message(:room_full), do: "That room is full"
  defp message(:name_taken), do: "Someone in that room already has that name. Pick another"
  defp message(:game_in_progress), do: "That game has already started"
  defp message(:server_busy), do: "We're full right now. Please try again in a few minutes"
  defp message(_), do: "Something went wrong, please try again"
end
