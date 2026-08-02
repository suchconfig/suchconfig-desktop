import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/suchconfig_desktop start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :suchconfig_desktop, SuchConfigDesktopWeb.Endpoint, server: true
end

if config_env() == :prod do
  config :suchconfig_desktop, :vault_skipped_cookie, "suchconfig_vault_skipped"

  database_path =
    System.get_env("SUCHCONFIG_DATABASE_PATH") ||
      Path.expand("priv/repo/suchconfig_desktop_prod.db", __DIR__)

  database_dir = Path.dirname(database_path)

  if database_dir != "" do
    File.mkdir_p!(database_dir)
  end

  config :suchconfig_desktop, :run_migrations, true

  config :suchconfig_desktop, SuchConfigDesktop.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "1"),
    timeout: 20_000

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      "suchconfig-desktop-local-phoenix-secret-key-base-not-for-hosted-deployments-64b-min"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :suchconfig_desktop, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :suchconfig_desktop, SuchConfigDesktopWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [ip: {127, 0, 0, 1}, port: port],
    secret_key_base: secret_key_base,
    check_origin: false

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :suchconfig_desktop, SuchConfigDesktopWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :suchconfig_desktop, SuchConfigDesktopWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :suchconfig_desktop, SuchConfigDesktop.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
