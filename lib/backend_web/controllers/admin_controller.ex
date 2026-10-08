defmodule BackendWeb.AdminController do
  @moduledoc """
  A private stats page for the operator: /admin shows live rooms and players.

  The password is hardcoded for now. Change `@password` (or move it to an env var) before sharing
  the server with anyone you don't trust. Wrong guesses are counted per address and locked out.
  """
  use Phoenix.Controller, formats: [:html, :json]

  import Plug.Conn

  alias Backend.RateLimit
  alias BackendWeb.Plugs.RateLimit, as: Limit

  @password "givemeacess"

  # GET /admin: the page itself. It holds no data; it asks for it with the password.
  def page(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, html())
  end

  # GET /admin/stats   header: x-admin-password
  def stats(conn, _params) do
    ip = conn.assigns[:client_ip] || "unknown"

    case RateLimit.blocked?(:admin_miss, ip) do
      {:blocked, retry_ms} ->
        Limit.reject(conn, retry_ms)

      false ->
        if authorized?(conn) do
          conn |> put_resp_header("cache-control", "no-store") |> json(Backend.Rooms.stats())
        else
          RateLimit.hit(:admin_miss, ip)
          conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
        end
    end
  end

  defp authorized?(conn) do
    case get_req_header(conn, "x-admin-password") do
      [given] -> Plug.Crypto.secure_compare(given, @password)
      _ -> false
    end
  end

  defp html do
    """
    <!doctype html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Stats</title>
    <style>
      body{font:15px system-ui,sans-serif;margin:0;padding:20px;background:#fafafa;color:#222}
      h1{font-size:20px;margin:0 0 16px}
      .cards{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:20px}
      .card{background:#fff;border:1px solid #ddd;border-radius:8px;padding:10px 16px;min-width:110px}
      .card b{display:block;font-size:26px}
      .card span{color:#666;font-size:12px}
      table{border-collapse:collapse;width:100%;background:#fff}
      th,td{border:1px solid #ddd;padding:6px 10px;text-align:left;vertical-align:top}
      th{background:#f0f0f0}
      .off{color:#aaa}
      #err{color:#c00;margin:8px 0}
      form{display:flex;gap:8px}
      input{padding:8px;font-size:15px}
    </style></head><body>
    <h1>Game stats</h1>
    <form id="login"><input id="pw" type="password" placeholder="Password" autofocus><button>Show</button></form>
    <div id="err"></div>
    <div id="out" hidden>
      <div class="cards" id="cards"></div>
      <table><thead><tr><th>Room</th><th>Phase</th><th>Round</th><th>Age</th><th>Players</th></tr></thead>
      <tbody id="rows"></tbody></table>
      <p class="off" id="upd"></p>
    </div>
    <script>
      let pw = sessionStorage.getItem("adminpw") || "", timer = null;
      const $ = id => document.getElementById(id);
      const esc = s => String(s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
      const dur = s => s < 60 ? s + "s" : s < 3600 ? Math.floor(s/60) + "m" : Math.floor(s/3600) + "h " + Math.floor(s%3600/60) + "m";

      async function load() {
        const r = await fetch("/admin/stats", {headers: {"x-admin-password": pw}});
        if (!r.ok) {
          clearInterval(timer); sessionStorage.removeItem("adminpw");
          $("out").hidden = true; $("login").hidden = false;
          $("err").textContent = r.status === 429 ? "Too many wrong tries. Wait a while." : "Wrong password.";
          return;
        }
        const s = await r.json();
        $("err").textContent = ""; $("login").hidden = true; $("out").hidden = false;
        const card = (n, l) => `<div class="card"><b>${n}</b><span>${l}</span></div>`;
        $("cards").innerHTML =
          card(s.rooms + " / " + s.max_rooms, "active rooms") + card(s.players, "players") +
          card(s.connected, "connected now") + card(s.sockets, "open sockets") +
          Object.entries(s.by_phase).map(([p, n]) => card(n, p)).join("") +
          card(s.memory_mb + " MB", "memory") + card(dur(s.uptime_s), "uptime");
        $("rows").innerHTML = s.list.map(r => `<tr><td><b>${esc(r.code)}</b></td><td>${esc(r.phase)}</td>
          <td>${r.round ? r.round + "/" + r.rounds : "-"}</td><td>${dur(r.age_s)}</td>
          <td>${r.players.map(p => `<span class="${p.connected ? "" : "off"}">${esc(p.name)}${p.spectator ? " (watching)" : ""}</span>`).join(", ")}</td></tr>`).join("")
          || '<tr><td colspan="5" class="off">No rooms right now</td></tr>';
        $("upd").textContent = "Updated " + new Date().toLocaleTimeString() + " (refreshes every 3s)";
      }
      function start() { sessionStorage.setItem("adminpw", pw); load(); clearInterval(timer); timer = setInterval(load, 3000); }
      $("login").onsubmit = e => { e.preventDefault(); pw = $("pw").value; start(); };
      if (pw) start();
    </script></body></html>
    """
  end
end
