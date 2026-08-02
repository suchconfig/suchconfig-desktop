defmodule SuchConfigDesktop.Repo.Migrations.AddBrokerFieldsToEnvProjectFolders do
  use Ecto.Migration

  def change do
    alter table(:env_project_folders) do
      add :broker_enabled, :boolean, null: false, default: false
      add :broker_scope_id, :string
      add :broker_allowed_domains, :string
    end
  end
end
