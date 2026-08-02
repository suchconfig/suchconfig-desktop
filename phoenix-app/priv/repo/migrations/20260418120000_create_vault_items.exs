defmodule SuchConfigDesktop.Repo.Migrations.CreateVaultItems do
  use Ecto.Migration

  def change do
    create table(:vault_items) do
      add :project_folder_id, references(:env_project_folders, on_delete: :delete_all),
        null: false

      add :legacy_note_id, references(:env_notes, on_delete: :nilify_all)

      add :title, :string, null: false
      add :kind, :string, null: false, default: "generic_note"
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

    create index(:vault_items, [:project_folder_id])
    create unique_index(:vault_items, [:project_folder_id, :title])
    create index(:vault_items, [:kind])
    create index(:vault_items, [:legacy_note_id])

    create table(:vault_item_links) do
      add :source_id, references(:vault_items, on_delete: :delete_all), null: false
      add :target_id, references(:vault_items, on_delete: :delete_all), null: false
      add :link_kind, :string, null: false, default: "references"

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:vault_item_links, [:source_id])
    create index(:vault_item_links, [:target_id])
    create unique_index(:vault_item_links, [:source_id, :target_id, :link_kind])
  end
end
