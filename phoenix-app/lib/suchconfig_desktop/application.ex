defmodule SuchConfigDesktop.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if Application.get_env(:suchconfig_desktop, :run_migrations, false) do
      run_migrations()
    end

    children = [
      SuchConfigDesktopWeb.Telemetry,
      SuchConfigDesktop.Repo,
      SuchConfigDesktop.VaultSessionRegistry,
      {DNSCluster,
       query: Application.get_env(:suchconfig_desktop, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SuchConfigDesktop.PubSub},
      # Start a worker by calling: SuchConfigDesktop.Worker.start_link(arg)
      # {SuchConfigDesktop.Worker, arg},
      # Start to serve requests, typically the last entry
      SuchConfigDesktopWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SuchConfigDesktop.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SuchConfigDesktopWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp run_migrations do
    for repo <- Application.get_env(:suchconfig_desktop, :ecto_repos, []) do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end
  end
end
