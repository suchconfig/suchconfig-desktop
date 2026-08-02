defmodule SuchConfigDesktop.EnvManager.NoteEntry do
  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.EnvManager.Note

  schema "env_note_entries" do
    field :position, :integer, default: 0
    field :key_name, :string
    field :value_encrypted, :binary
    field :value_nonce, :binary
    field :is_secret, :boolean, default: true
    field :line_number, :integer
    field :encryption_version, :integer, default: 1

    belongs_to :note, Note

    timestamps(type: :utc_datetime)
  end

  def changeset(note_entry, attrs) do
    note_entry
    |> cast(attrs, [
      :note_id,
      :position,
      :key_name,
      :value_encrypted,
      :value_nonce,
      :is_secret,
      :line_number,
      :encryption_version
    ])
    |> validate_required([:note_id, :key_name])
    |> foreign_key_constraint(:note_id)
    |> unique_constraint(:key_name, name: :env_note_entries_note_id_key_name_position_index)
  end
end
