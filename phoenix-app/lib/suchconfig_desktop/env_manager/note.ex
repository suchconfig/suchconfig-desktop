defmodule SuchConfigDesktop.EnvManager.Note do
  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.EnvManager.{NoteEntry, ProjectFolder}

  @note_types [
    "generic_note",
    "environment_files",
    "secrets_credentials",
    "ai_editor_rules",
    "tooling_config_snippets",
    "project_notes"
  ]

  schema "env_notes" do
    field :title, :string
    field :note_type, :string, default: "generic_note"
    field :security_mode, :string, default: "global_passkey"
    field :raw_content_encrypted, :binary
    field :raw_content_nonce, :binary
    field :parsed_entries_encrypted, :binary
    field :parsed_entries_nonce, :binary
    field :encryption_version, :integer, default: 1

    belongs_to :project_folder, ProjectFolder
    has_many :entries, NoteEntry, foreign_key: :note_id

    timestamps(type: :utc_datetime)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :title,
      :note_type,
      :security_mode,
      :project_folder_id,
      :raw_content_encrypted,
      :raw_content_nonce,
      :parsed_entries_encrypted,
      :parsed_entries_nonce,
      :encryption_version
    ])
    |> validate_required([:title, :project_folder_id])
    |> validate_inclusion(:note_type, @note_types)
    |> foreign_key_constraint(:project_folder_id)
    |> unique_constraint(:title, name: :env_notes_project_folder_id_title_index)
  end
end
