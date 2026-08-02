# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :suchconfig_desktop,
  ecto_repos: [SuchConfigDesktop.Repo],
  generators: [timestamp_type: :utc_datetime],
  vault_item_crdt_persistence: true,
  secrets_vault_enabled: true,
  secrets_vault_crdt_persistence: true,
  local_broker_license_enabled: false,
  security_sentinel_license_enabled: false

config :suchconfig_core,
       :eff_wordlist_path,
       Path.expand("../vendor/suchconfig_core/priv/wordlists/eff_large_wordlist.txt", __DIR__)

config :mime, :types, %{
  "text/tab-separated-values" => ["tsv"],
  "application/vnd.suchconfig.vault+octet-stream" => ["suchvault", "suchconfig"]
}

# Configures the endpoint
config :suchconfig_desktop, SuchConfigDesktopWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SuchConfigDesktopWeb.ErrorHTML, json: SuchConfigDesktopWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SuchConfigDesktop.PubSub,
  live_view: [signing_salt: "ETHkiOOn"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :suchconfig_desktop, SuchConfigDesktop.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
build_path = Mix.Project.build_path()

colocated_path =
  Path.join([build_path, "lib/phoenix_colocated/priv/colocated/suchconfig_desktop.js"])

assets_node_modules = Path.expand("../assets/node_modules", __DIR__)

config :esbuild,
  version: "0.25.4",
  suchconfig_desktop: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --alias:phoenix-colocated/suchconfig_desktop=#{colocated_path}),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [assets_node_modules, Path.expand("../deps", __DIR__), build_path]
    }
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  suchconfig_desktop: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
