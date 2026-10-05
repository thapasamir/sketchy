defmodule BackendWeb.Plugs.RateLimit do
  @moduledoc """
  Refuses a request when its caller has done too much of one kind of thing. Used in the router and
  controllers with the name of a policy (see `Backend.RateLimit`):

      plug BackendWeb.Plugs.RateLimit, policy: :room_create when action == :create

  The caller is the address `BackendWeb.ClientIP` found. A refused request gets a 429 with a plain
  message and a `retry-after` header (in seconds), and goes no further.
  """

  import Plug.Conn

  alias Backend.RateLimit

  @behaviour Plug

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :policy)

  @impl true
  def call(conn, policy) do
    case RateLimit.hit(policy, conn.assigns[:client_ip] || "unknown") do
      :ok -> conn
      {:error, retry_ms} -> reject(conn, retry_ms)
    end
  end

  @doc "Answer 429 and stop. `retry_ms` is how long until the caller may try again."
  def reject(conn, retry_ms) do
    seconds = max(1, ceil(retry_ms / 1000))

    conn
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> put_resp_content_type("application/json")
    |> send_resp(429, Jason.encode!(%{error: "rate_limited", message: message(seconds)}))
    |> halt()
  end

  defp message(seconds) when seconds < 60,
    do: "Too many tries. Please wait #{seconds} seconds and try again."

  defp message(seconds),
    do: "Too many tries. Please wait about #{ceil(seconds / 60)} minutes and try again."
end
