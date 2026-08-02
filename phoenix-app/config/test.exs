import Config

config :suchconfig_desktop, :vault_skipped_cookie, "suchconfig_vault_skipped"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :suchconfig_desktop, SuchConfigDesktop.Repo,
  database:
    Path.expand(
      "../priv/repo/suchconfig_desktop_test#{System.get_env("MIX_TEST_PARTITION")}.db",
      __DIR__
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1,
  pragmas: [busy_timeout: 15_000]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :suchconfig_desktop, SuchConfigDesktopWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YZsKq0cb89ncaW77q+HBNwgILoUXcDGRLEtjlgEw+xxXTPlB5opV3mED9Fr2NOBS",
  server: false

# In test we don't send emails
config :suchconfig_desktop, SuchConfigDesktop.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :suchconfig_desktop, :archive_export_test_controls, true
