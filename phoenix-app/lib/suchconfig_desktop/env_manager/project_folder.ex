defmodule SuchConfigDesktop.EnvManager.ProjectFolder do
  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.EnvManager.Note

  schema "env_project_folders" do
    field :name, :string
    field :description, :string
    field :tags, :string
    field :linked_project_path, :string
    field :linked_sync_enabled, :boolean, default: false
    field :linked_auto_sync, :boolean, default: false
    field :broker_enabled, :boolean, default: false
    field :broker_scope_id, :string
    field :broker_allowed_domains, :string
    field :broker_services, :string, default: "[]"

    has_many :notes, Note, foreign_key: :project_folder_id

    timestamps(type: :utc_datetime)
  end

  def changeset(project_folder, attrs) do
    project_folder
    |> cast(attrs, [
      :name,
      :description,
      :tags,
      :linked_project_path,
      :linked_sync_enabled,
      :linked_auto_sync,
      :broker_enabled,
      :broker_scope_id,
      :broker_allowed_domains,
      :broker_services
    ])
    |> validate_required([:name])
    |> unique_constraint(:name, message: "already exists")
  end
end
