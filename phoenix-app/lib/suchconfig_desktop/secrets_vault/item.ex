defmodule SuchConfigDesktop.SecretsVault.Item do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.SecretsVault.Folder
  alias SuchConfigDesktop.SecretsVault.Types

  schema "secrets_vault_items" do
    field :title, :string
    field :kind, :string, default: "password"
    field :security_mode, :string, default: "global_passkey"

    field :crdt_snapshot_encrypted, :binary
    field :crdt_snapshot_nonce, :binary
    field :crdt_encryption_version, :integer, default: 1
    field :crdt_schema_version, :integer, default: 1
    field :crdt_snapshot_hash, :string

    field :updated_clock, :integer, default: 0
    field :peer_id, :integer

    belongs_to :secrets_vault_folder, Folder

    timestamps(type: :utc_datetime)
  end

  @cast_fields ~w(
    title
    kind
    security_mode
    secrets_vault_folder_id
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
    |> validate_required([:title, :kind, :security_mode])
    |> validate_inclusion(:kind, Types.allowed_kind_strings())
    |> validate_inclusion(
      :security_mode,
      Enum.map(Types.allowed_security_modes(), &Atom.to_string/1)
    )
    |> validate_length(:title, min: 1, max: 255)
    |> validate_number(:crdt_encryption_version, greater_than: 0)
    |> validate_number(:crdt_schema_version, greater_than: 0)
    |> foreign_key_constraint(:secrets_vault_folder_id)
    |> unique_constraint(:title,
      name: :secrets_vault_items_secrets_vault_folder_id_title_index
    )
  end
end
