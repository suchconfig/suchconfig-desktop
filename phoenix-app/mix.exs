defmodule SuchConfigDesktop.MixProject do
  use Mix.Project

  # Note: Compilation warnings from Phoenix.Tracker.* modules are known issues with
  # Elixir 1.19.3's stricter type checking. These warnings come from Phoenix's internal
  # code and don't affect functionality. They can be safely ignored and will likely be
  # fixed in a future Phoenix release.

  def project do
    [
      app: :suchconfig_desktop,
      version: "0.2.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {SuchConfigDesktop.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def releases do
    [
      suchconfig_desktop: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.24"},
      {:decimal, "~> 3.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:lucide,
       github: "lucide-icons/lucide",
       tag: "0.445.0",
       sparse: "icons",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.26"},
      {:req, "~> 0.6.1"},
      {:plug, "~> 1.18.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Ash Framework for domain modeling and data management (commented out until available)
      # {:ash, "~> 3.0"},
      # {:ash_sqlite, "~> 1.0"},
      # {:ash_json_api, "~> 0.1"},
      {:suchconfig_core, path: "../vendor/suchconfig_core", override: true},
      # {:suchconfig_core, path: "../vendor/suchconfig_core", override: true},
      {:makeup, "~> 1.2"},
      {:makeup_json, "~> 1.0"},
      {:rustler, "~> 0.37.3"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind suchconfig_desktop", "esbuild suchconfig_desktop"],
      "assets.deploy": [
        "tailwind suchconfig_desktop --minify",
        "esbuild suchconfig_desktop --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
