defmodule SuchConfigDesktop.SecretsVault.Folder do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "secrets_vault_folders" do
    field :name, :string
    field :description, :string

    has_many :items, SuchConfigDesktop.SecretsVault.Item, foreign_key: :secrets_vault_folder_id

    timestamps(type: :utc_datetime)
  end

  @unassociated_name "Unassociated"
  @deleted_items_name "Deleted Items"

  def unassociated_name, do: @unassociated_name

  def deleted_items_name, do: @deleted_items_name

  def uncategorized_name, do: unassociated_name()

  def system_folder_names, do: [@unassociated_name, @deleted_items_name]

  def system_folder?(%__MODULE__{name: name}) when is_binary(name),
    do: name in system_folder_names()

  def system_folder?(_), do: false

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:name)
  end
end
