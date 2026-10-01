defmodule BackendWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  # Every URL returns the Svelte app shell; Svelte decides what to show.
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:backend, "priv/static/index.html"))
  end
end
