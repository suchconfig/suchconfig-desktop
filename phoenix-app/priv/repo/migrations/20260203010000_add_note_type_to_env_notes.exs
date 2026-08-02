defmodule SuchConfigDesktop.Repo.Migrations.AddNoteTypeToEnvNotes do
  use Ecto.Migration

  def change do
    alter table(:env_notes) do
      add :note_type, :string, default: "generic_note", null: false
    end
  end
end
