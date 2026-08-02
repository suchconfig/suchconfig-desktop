defmodule SuchConfigDesktop.Repo.Migrations.CreateSecretsVault do
  use Ecto.Migration

  def change do
    create table(:secrets_vault_folders) do
      add :name, :string, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:secrets_vault_folders, [:name])

    create table(:secrets_vault_items) do
      add :secrets_vault_folder_id,
          references(:secrets_vault_folders, on_delete: :nilify_all)

      add :title, :string, null: false
      add :kind, :string, null: false, default: "password"
      add :security_mode, :string, null: false, default: "global_passkey"

      add :crdt_snapshot_encrypted, :binary
      add :crdt_snapshot_nonce, :binary
      add :crdt_encryption_version, :integer, null: false, default: 1
      add :crdt_schema_version, :integer, null: false, default: 1
      add :crdt_snapshot_hash, :string

      add :updated_clock, :bigint, null: false, default: 0
      add :peer_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:secrets_vault_items, [:secrets_vault_folder_id])
    create index(:secrets_vault_items, [:kind])
    create unique_index(:secrets_vault_items, [:secrets_vault_folder_id, :title])
  end
end
