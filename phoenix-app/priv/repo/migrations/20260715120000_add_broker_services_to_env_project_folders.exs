defmodule SuchConfigDesktop.Repo.Migrations.AddBrokerServicesToEnvProjectFolders do
  use Ecto.Migration

  def change do
    alter table(:env_project_folders) do
      add :broker_services, :string, null: false, default: "[]"
    end
  end
end
