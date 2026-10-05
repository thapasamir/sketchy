defmodule Backend.RateLimitHelper do
  @moduledoc """
  Switch the abuse limits on for one test. They are off in the test environment (so the other
  tests can make many users and rooms from one address), and a setting that is global to the
  application, so a test that uses this must not be `async`.

  `scale` multiplies every count (see `Backend.RateLimit`): 0.05 turns "60 guests" into 3.
  """

  def enable(scale \\ 1, extra \\ []) do
    old = Application.get_env(:backend, :rate_limits)
    Application.put_env(:backend, :rate_limits, [enabled: true, scale: scale] ++ extra)
    Backend.RateLimit.reset()

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:backend, :rate_limits, old)
      Backend.RateLimit.reset()
    end)
  end

  @doc "Set an application setting for one test, and put it back afterwards."
  def put_env(key, value) do
    old = Application.fetch_env(:backend, key)
    Application.put_env(:backend, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case old do
        {:ok, v} -> Application.put_env(:backend, key, v)
        :error -> Application.delete_env(:backend, key)
      end
    end)
  end
end
