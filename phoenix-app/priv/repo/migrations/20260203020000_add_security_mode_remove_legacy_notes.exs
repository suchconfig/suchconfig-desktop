defmodule SuchConfigDesktop.Repo.Migrations.AddSecurityModeRemoveLegacyNotes do
  use Ecto.Migration

  def up do
    alter table(:env_notes) do
      add :security_mode, :string, null: true
    end

    execute("""
    UPDATE env_notes
    SET security_mode = 'per_note_password'
    WHERE raw_content_encrypted IS NOT NULL AND encryption_version = 1
    """)

    execute("""
    UPDATE env_notes
    SET security_mode = 'global_passkey'
    WHERE security_mode IS NULL
    """)

    execute("""
    DELETE FROM env_note_entries
    WHERE note_id IN (SELECT id FROM env_notes WHERE security_mode = 'per_note_password')
    """)

    execute("""
    DELETE FROM env_notes
    WHERE security_mode = 'per_note_password'
    """)

    execute("""
    UPDATE env_notes
    SET security_mode = 'global_passkey'
    WHERE security_mode IS NULL
    """)
  end

  def down do
    alter table(:env_notes) do
      remove :security_mode
    end
  end
end
