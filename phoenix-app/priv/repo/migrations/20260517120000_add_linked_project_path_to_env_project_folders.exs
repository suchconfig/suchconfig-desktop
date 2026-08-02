defmodule SuchConfigDesktop.Repo.Migrations.AddLinkedProjectPathToEnvProjectFolders do
  use Ecto.Migration

  def change do
    alter table(:env_project_folders) do
      add :linked_project_path, :string
    end
  end
end
