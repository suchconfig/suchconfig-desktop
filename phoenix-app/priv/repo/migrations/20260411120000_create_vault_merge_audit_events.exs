defmodule SuchConfigDesktop.Repo.Migrations.CreateVaultMergeAuditEvents do
  use Ecto.Migration

  def change do
    create table(:vault_merge_audit_events) do
      add :operation, :string, null: false
      add :project_folder_id, references(:env_project_folders, on_delete: :nilify_all)
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:vault_merge_audit_events, [:operation])
    create index(:vault_merge_audit_events, [:inserted_at])
  end
end
