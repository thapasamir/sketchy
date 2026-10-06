defmodule BackendWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  @assets ["/assets/app.css", "/assets/app.js"]

  # Every URL returns the Svelte app shell; Svelte decides what to show. Only the home page is
  # meant for search results: a room link (/room/ABCD) is an invitation, and anything else is not a
  # page, so those are told to stay out of the index.
  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> keep_out_of_search()
    |> send_resp(200, shell())
  end

  # The shell names the JS and CSS without a fingerprint. In production they are swapped for the
  # digested URLs (app-<hash>.js?vsn=d), which the static plug lets browsers cache for a year.
  defp shell do
    case :persistent_term.get({__MODULE__, :shell}, nil) do
      nil ->
        html =
          :backend
          |> Application.app_dir("priv/static/index.html")
          |> File.read!()
          |> fingerprint_assets()

        :persistent_term.put({__MODULE__, :shell}, html)
        html

      html ->
        html
    end
  end

  defp fingerprint_assets(html) do
    Enum.reduce(@assets, html, fn path, acc ->
      String.replace(acc, ~s("#{path}"), ~s("#{BackendWeb.Endpoint.static_path(path)}"))
    end)
  end

  defp keep_out_of_search(%{request_path: "/"} = conn), do: conn
  defp keep_out_of_search(conn), do: put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
end
