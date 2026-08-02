defmodule SuchConfigDesktop.VaultMergeAuditEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @operations ~w(export import crdt_merge export_unpacked)

  schema "vault_merge_audit_events" do
    field :operation, :string
    field :metadata, :map, default: %{}

    belongs_to :project_folder, SuchConfigDesktop.EnvManager.ProjectFolder

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:operation, :project_folder_id, :metadata])
    |> validate_required([:operation])
    |> validate_inclusion(:operation, @operations)
  end
end
