defmodule SuchConfigDesktop.VaultKey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vault_keys" do
    field :key_id, :string
    field :key_text, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(vault_key, attrs) do
    vault_key
    |> cast(attrs, [:key_id, :key_text])
    |> validate_required([:key_id, :key_text])
    |> unique_constraint(:key_id)
  end
end
