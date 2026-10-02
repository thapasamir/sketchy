defmodule BackendWeb.Auth do
  @moduledoc """
  Proves who is calling the API.

  After login the server hands the browser a signed token (`sign/1`). The browser sends it back
  as `Authorization: Bearer <token>`. Only the server knows the signing key, so a token can't be
  forged or edited, unlike a bare user id sitting in localStorage.

  As a plug it sets `conn.assigns.current_user` to the user, or nil when there is no valid token.
  It never rejects the request itself: endpoints decide whether they need a user.
  """

  import Plug.Conn

  alias Backend.Accounts

  @salt "user auth"
  @max_age_seconds 60 * 60 * 24 * 30

  def init(opts), do: opts

  def call(conn, _opts) do
    user =
      with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
           {:ok, user} <- verify(token) do
        user
      else
        _ -> nil
      end

    assign(conn, :current_user, user)
  end

  def sign(user), do: Phoenix.Token.sign(BackendWeb.Endpoint, @salt, user.id)

  def verify(token) do
    with {:ok, id} <-
           Phoenix.Token.verify(BackendWeb.Endpoint, @salt, token, max_age: @max_age_seconds),
         %{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      _ -> :error
    end
  end
end
