import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ledger, Ledger.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ledger_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ledger, LedgerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "nfXqtIqfqTjxEngG1ccHrd+wHjl4LkfDY6FkWvMI4NcIPYdrtOWRuSotkgHcQfte",
  server: false

# Custom domains: stub adapters; tests drive them via :dns_stub /
# :fly_stub application env (set per-test).
config :ledger, :dns_resolver, Ledger.CustomDomains.DnsResolver.Stub
config :ledger, :fly_client, Ledger.CustomDomains.FlyClient.Stub

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Capture mail in-memory; assert with Swoosh.TestAssertions.
config :ledger, Ledger.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

# Don't run queues/plugins in test. Jobs are inserted and asserted with
# Oban.Testing (drain or assert_enqueued).
config :ledger, Oban, testing: :manual
