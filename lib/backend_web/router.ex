defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # JSON endpoints: one request, one response
  scope "/api", BackendWeb do
    pipe_through :api

    post "/rooms", RoomController, :create
  end

  # Everything else gets the Svelte app (/, /room/ABCD, ...)
  scope "/", BackendWeb do
    get "/*path", PageController, :index
  end
end
