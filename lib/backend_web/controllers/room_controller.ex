defmodule BackendWeb.RoomController do
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Backend.Rooms

  # POST /api/rooms   body: {"name": "Samir"}
  # Pattern matching on the params picks the clause: no "name" key falls through to the second one.
  def create(conn, %{"name" => name}) do
    case Rooms.create_room(name) do
      {:ok, %{code: code, player_id: player_id}} ->
        conn
        |> put_status(:created)
        |> json(%{code: code, player_id: player_id})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def create(conn, _params), do: error(conn, :name_required)

  defp error(conn, reason) do
    conn
    |> put_status(status(reason))
    |> json(%{error: Atom.to_string(reason), message: message(reason)})
  end

  defp status(:name_required), do: :unprocessable_entity
  defp status(:name_too_long), do: :unprocessable_entity
  defp status(_), do: :service_unavailable

  defp message(:name_required), do: "Please enter your name"
  defp message(:name_too_long), do: "Name must be 20 characters or fewer"
  defp message(_), do: "Could not create a room right now, please try again"
end
