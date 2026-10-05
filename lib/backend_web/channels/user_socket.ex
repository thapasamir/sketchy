defmodule BackendWeb.UserSocket do
  use Phoenix.Socket

  alias Backend.RateLimit
  alias BackendWeb.ClientIP

  # One WebSocket connection per browser tab. Topics matching "room:*" are handled by RoomChannel.
  channel "room:*", BackendWeb.RoomChannel

  # Anyone may connect (who you are is checked when you join a room's channel: player_id must
  # belong to that room), but how fast one address may open connections is limited, and the
  # address is kept on the socket for the limits that come after (see RoomChannel).
  @impl true
  def connect(_params, socket, connect_info) do
    ip = ClientIP.from_connect_info(connect_info)

    case RateLimit.hit(:socket_connect, ip) do
      :ok ->
        # a name for this one connection, so it can be told to close (see `id/1`)
        id = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
        {:ok, socket |> assign(:client_ip, ip) |> assign(:socket_id, id)}

      {:error, _retry_ms} ->
        :error
    end
  end

  # Each connection is named after its own random id, so `BackendWeb.Endpoint.broadcast(id,
  # "disconnect", %{})` closes that connection and no other. (Not the address: people share those.)
  @impl true
  def id(%{assigns: %{socket_id: id}}), do: "user_socket:" <> id
  def id(_socket), do: nil
end
