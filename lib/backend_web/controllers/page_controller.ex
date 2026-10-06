defmodule BackendWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  # Every URL returns the Svelte app shell; Svelte decides what to show. Only the home page is
  # meant for search results: a room link (/room/ABCD) is an invitation, and anything else is not a
  # page, so those are told to stay out of the index.
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> keep_out_of_search()
    |> send_file(200, Application.app_dir(:backend, "priv/static/index.html"))
  end

  defp keep_out_of_search(%{request_path: "/"} = conn), do: conn
  defp keep_out_of_search(conn), do: put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
end
