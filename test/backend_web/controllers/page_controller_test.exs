defmodule BackendWeb.PageControllerTest do
  use BackendWeb.ConnCase, async: true

  # Every page URL returns the same Svelte app shell; Svelte decides what to show.
  for path <- ["/", "/room/ABCD"] do
    test "GET #{path} serves the app shell", %{conn: conn} do
      conn = get(conn, unquote(path))
      assert html_response(conn, 200) =~ ~s(<script defer src="/assets/app.js">)
    end
  end

  describe "search engines" do
    test "the home page may be indexed", %{conn: conn} do
      conn = get(conn, "/")
      assert get_resp_header(conn, "x-robots-tag") == []
    end

    test "a room link, or any other address, is kept out of the index", %{conn: conn} do
      for path <- ["/room/ABCD", "/nothing-here"] do
        conn = get(conn, path)
        assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
      end
    end

    test "the home page says what the game is, before any script runs", %{conn: conn} do
      html = conn |> get("/") |> html_response(200)
      assert html =~ "<title>Sketchy: Free Online Imposter Drawing Game"
      assert html =~ ~s(<link rel="canonical" href="https://sketchy.sakriitech.com/">)
      assert html =~ ~s(property="og:image")
      assert html =~ "<h1>"
    end

    test "robots.txt and the sitemap are served and name the site", %{conn: conn} do
      assert response(get(conn, "/robots.txt"), 200) =~
               "Sitemap: https://sketchy.sakriitech.com/sitemap.xml"

      assert response(get(conn, "/sitemap.xml"), 200) =~
               "<loc>https://sketchy.sakriitech.com/</loc>"

      assert response(get(conn, "/images/og.png"), 200)
    end
  end
end
