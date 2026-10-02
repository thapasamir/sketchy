defmodule BackendWeb.ChannelCase do
  @moduledoc "Test helpers for channels (no database needed)."
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      @endpoint BackendWeb.Endpoint
    end
  end
end
