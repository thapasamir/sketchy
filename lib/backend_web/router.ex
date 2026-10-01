defmodule BackendWeb.Router do
  use BackendWeb, :router

  # Serve the Svelte app for every page URL (/, /room/ABCD, ...)
  scope "/", BackendWeb do
    get "/*path", PageController, :index
  end
end
