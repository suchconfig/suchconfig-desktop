defmodule SuchConfigDesktop.Repo.Migrations.CreateEnvManagerTables do
  use Ecto.Migration

  def change do
    create table(:env_project_folders) do
      add :name, :string, null: false
      add :description, :text
      add :tags, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:env_project_folders, [:name])

    create table(:env_notes) do
      add :project_folder_id, references(:env_project_folders, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :raw_content_encrypted, :binary
      add :raw_content_nonce, :binary
      add :parsed_entries_encrypted, :binary
      add :parsed_entries_nonce, :binary
      add :encryption_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:env_notes, [:project_folder_id])
    create unique_index(:env_notes, [:project_folder_id, :title])

    create table(:env_note_entries) do
      add :note_id, references(:env_notes, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :key_name, :string, null: false
      add :value_encrypted, :binary
      add :value_nonce, :binary
      add :is_secret, :boolean, null: false, default: true
      add :line_number, :integer
      add :encryption_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:env_note_entries, [:note_id])
    create unique_index(:env_note_entries, [:note_id, :key_name, :position])
  end
end
