defmodule SuchConfigDesktop.SecretsVault.ActivityEvent do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.SecretsVault.Item

  @actions ~w(create update copy)

  schema "secrets_vault_activity_events" do
    field :action, :string
    field :summary, :string
    field :device_label, :string
    field :metadata, :map, default: %{}

    belongs_to :secrets_vault_item, Item

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def actions, do: @actions

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:secrets_vault_item_id, :action, :summary, :device_label, :metadata])
    |> validate_required([:secrets_vault_item_id, :action, :summary, :device_label])
    |> validate_inclusion(:action, @actions)
    |> validate_length(:summary, min: 1, max: 255)
    |> validate_length(:device_label, min: 1, max: 255)
    |> foreign_key_constraint(:secrets_vault_item_id)
  end
end
