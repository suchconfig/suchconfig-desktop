defmodule SuchConfigDesktop.Repo.Migrations.CreateVaultKeys do
  use Ecto.Migration

  def change do
    create table(:vault_keys) do
      add :key_id, :string, null: false
      add :key_text, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vault_keys, [:key_id])
  end
end
