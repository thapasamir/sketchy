defmodule BackendWeb.ClientIP do
  @moduledoc """
  Who is really calling? Rate limits are counted per address, so the address has to be the person's
  and not the proxy's.

  On Fly every request arrives through Fly's proxy, so the connection's own address is always the
  proxy. The real one is in a header the proxy sets (`fly-client-ip`). That header is only
  trustworthy when the proxy is the only way in, so it is used only where it is turned on
  (`config :backend, :client_ip_header, "fly-client-ip"`, set for production). Anywhere else,
  such as development, the connection's own address is used and a header is ignored.

  The result is a string to count by. IPv6 addresses are cut to their /64 network, because one
  person can use any address in theirs: counting each one would make the limit meaningless.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: assign(conn, :client_ip, from_conn(conn))

  @doc "The address behind a request."
  def from_conn(conn), do: key(header_ip(conn.req_headers) || conn.remote_ip)

  @doc "The address behind a WebSocket connection, from its `connect_info` (`:peer_data`, `:x_headers`)."
  def from_connect_info(connect_info) do
    headers = Map.get(connect_info, :x_headers, [])
    peer = get_in(connect_info, [:peer_data, :address])
    key(header_ip(headers) || peer)
  end

  # the address in the trusted header, if there is one and it is turned on
  defp header_ip(headers) do
    with name when is_binary(name) <- Application.get_env(:backend, :client_ip_header),
         {_, value} <- List.keyfind(headers, name, 0),
         {:ok, ip} <-
           value |> String.trim() |> String.to_charlist() |> :inet.parse_strict_address() do
      ip
    else
      _ -> nil
    end
  end

  @doc "The string a limit is counted by, for an address as `:inet` gives it."
  def key({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  def key({a, b, c, d, _e, _f, _g, _h}) do
    [a, b, c, d] |> Enum.map_join(":", &Integer.to_string(&1, 16)) |> Kernel.<>("::/64")
  end

  def key(_other), do: "unknown"
end
