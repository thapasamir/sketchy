defmodule BackendWeb.UserSocket do
  use Phoenix.Socket

  # One WebSocket connection per browser tab. Topics matching "room:*" are handled by RoomChannel.
  channel "room:*", BackendWeb.RoomChannel

  # No accounts in this game, so every connection is accepted. Who you are is checked
  # when you join a room's channel (player_id must belong to that room).
  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
