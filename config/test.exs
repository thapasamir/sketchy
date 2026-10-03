import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :backend, Backend.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "backend_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :backend, BackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CKJ6RjjtDNjtnSTUbBedqi5IiEZChsSAueVzEmQFvukOZIIHzU2p2Jm6h8PDX7Lq",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# A disconnected player keeps their seat this long (default 30s). Short so tests can see it expire.
config :backend, reconnect_grace_ms: 300

# the reveal lasts 8s in the real game; short here so tests can watch it end
config :backend, reveal_ms: 200

# a turn is the room's draw time (30s+) in the real game; short here, and a vanished drawer is
# given up on quickly
config :backend, turn_ms: 1_500, drawer_away_ms: 150

# the vote and the caught imposter's guess are 30s / 20s in the real game
config :backend, vote_ms: 1_500, guess_ms: 1_000, result_ms: 800
