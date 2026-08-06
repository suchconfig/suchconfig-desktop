defmodule SuchConfigDesktop.Repo.Migrations.CreateSecretsVaultActivityEvents do
  use Ecto.Migration

  def change do
    create table(:secrets_vault_activity_events) do
      add :secrets_vault_item_id,
          references(:secrets_vault_items, on_delete: :delete_all),
          null: false

      add :action, :string, null: false
      add :summary, :string, null: false
      add :device_label, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:secrets_vault_activity_events, [:secrets_vault_item_id, :inserted_at])
    create index(:secrets_vault_activity_events, [:action])
  end
end
