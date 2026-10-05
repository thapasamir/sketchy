defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    # who is calling, and a ceiling on how much of the API one address may use at all
    # (each endpoint below has its own, tighter limit too: see the controllers)
    plug BackendWeb.ClientIP
    plug BackendWeb.Plugs.RateLimit, policy: :api
    plug BackendWeb.Auth
  end

  # JSON endpoints: one request, one response
  scope "/api", BackendWeb do
    pipe_through :api

    post "/users/guest", UserController, :create_guest
    post "/users/register", UserController, :register
    post "/users/login", UserController, :login
    get "/users/me", UserController, :me
    post "/rooms", RoomController, :create
    post "/rooms/:code/join", RoomController, :join
  end

  # Everything else gets the Svelte app (/, /room/ABCD, ...)
  scope "/", BackendWeb do
    get "/*path", PageController, :index
  end
end
