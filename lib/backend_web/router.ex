defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # JSON endpoints: one request, one response
  scope "/api", BackendWeb do
    pipe_through :api

    post "/users/guest", UserController, :create_guest
    post "/users/register", UserController, :register
    post "/users/login", UserController, :login
    post "/rooms", RoomController, :create
    post "/rooms/:code/join", RoomController, :join
  end

  # Everything else gets the Svelte app (/, /room/ABCD, ...)
  scope "/", BackendWeb do
    get "/*path", PageController, :index
  end
end
