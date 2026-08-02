defmodule SuchConfigDesktop.Repo.Migrations.AddLinkedSyncToEnvProjectFolders do
  use Ecto.Migration

  def change do
    alter table(:env_project_folders) do
      add :linked_sync_enabled, :boolean, null: false, default: false
      add :linked_auto_sync, :boolean, null: false, default: false
    end
  end
end
