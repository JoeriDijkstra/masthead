# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ledger,
  ecto_repos: [Ledger.Repo],
  generators: [timestamp_type: :utc_datetime]

# Hosts treated as the bare app surface (no subdomain). Overridden via APP_HOSTS
# at runtime in prod. Dev defaults to lvh.me so `*.lvh.me:4000` resolves to
# 127.0.0.1 without any /etc/hosts changes.
config :ledger, :app_hosts, ~w(lvh.me localhost 127.0.0.1)

# Used by the admin to build the public URL of a site (for "View site" links
# and the slug helper text in the new-site form). Prod overrides this in
# runtime.exs with the real domain + https.
config :ledger, :site_url,
  scheme: "http",
  host: "lvh.me",
  port: 4000

# Configure the endpoint
config :ledger, LedgerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LedgerWeb.ErrorHTML, json: LedgerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ledger.PubSub,
  live_view: [signing_salt: "MCz9rXle"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ledger: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  ledger: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
