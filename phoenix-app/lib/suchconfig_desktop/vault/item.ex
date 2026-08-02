defmodule SuchConfigDesktop.Vault.Item do
  @moduledoc """
  Ecto schema for the unified CRDT-backed VaultItem.

  One row = one CRDT document. The encrypted snapshot lives in
  `crdt_snapshot_encrypted`; the plaintext is held transiently during
  decode/edit cycles only. Kind and security mode use the allow-lists in
  `SuchConfigDesktop.Vault.Types` so form params coerce cleanly.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.EnvManager.{Note, ProjectFolder}
  alias SuchConfigDesktop.Vault.Types

  schema "vault_items" do
    field :title, :string
    field :kind, :string, default: "generic_note"
    field :security_mode, :string, default: "global_passkey"

    field :crdt_snapshot_encrypted, :binary
    field :crdt_snapshot_nonce, :binary
    field :crdt_encryption_version, :integer, default: 1
    field :crdt_schema_version, :integer, default: 1
    field :crdt_snapshot_hash, :string

    field :updated_clock, :integer, default: 0
    field :peer_id, :integer

    belongs_to :project_folder, ProjectFolder
    belongs_to :legacy_note, Note, foreign_key: :legacy_note_id

    has_many :outgoing_links, SuchConfigDesktop.Vault.ItemLink, foreign_key: :source_id
    has_many :incoming_links, SuchConfigDesktop.Vault.ItemLink, foreign_key: :target_id

    timestamps(type: :utc_datetime)
  end

  @cast_fields ~w(
    title
    kind
    security_mode
    project_folder_id
    legacy_note_id
    crdt_snapshot_encrypted
    crdt_snapshot_nonce
    crdt_encryption_version
    crdt_schema_version
    crdt_snapshot_hash
    updated_clock
    peer_id
  )a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @cast_fields)
    |> validate_required([:title, :kind, :security_mode, :project_folder_id])
    |> validate_inclusion(:kind, Types.allowed_kind_strings())
    |> validate_inclusion(
      :security_mode,
      Enum.map(Types.allowed_security_modes(), &Atom.to_string/1)
    )
    |> validate_length(:title, min: 1, max: 255)
    |> validate_number(:crdt_encryption_version, greater_than: 0)
    |> validate_number(:crdt_schema_version, greater_than: 0)
    |> foreign_key_constraint(:project_folder_id)
    |> foreign_key_constraint(:legacy_note_id)
    |> unique_constraint(:title, name: :vault_items_project_folder_id_title_index)
  end

  @spec kind_atom(any()) :: Types.kind() | nil
  def kind_atom(%__MODULE__{kind: kind}) when is_binary(kind) do
    case Types.cast_kind(kind) do
      {:ok, atom} -> atom
      _ -> nil
    end
  end

  def kind_atom(_), do: nil
end
