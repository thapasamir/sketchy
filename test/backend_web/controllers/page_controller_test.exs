defmodule BackendWeb.PageControllerTest do
  use BackendWeb.ConnCase, async: true

  # Every page URL returns the same Svelte app shell; Svelte decides what to show.
  for path <- ["/", "/room/ABCD"] do
    test "GET #{path} serves the app shell", %{conn: conn} do
      conn = get(conn, unquote(path))
      assert html_response(conn, 200) =~ ~s(<script src="/assets/app.js">)
    end
  end
end
