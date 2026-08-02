defmodule SuchConfigDesktop.Vault.ItemLink do
  @moduledoc """
  Typed edge between two VaultItems (frontmatter wiki-links, `references`,
  `implements_policy_for`, etc.). Backs the Phase 3 graph view.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SuchConfigDesktop.Vault.Item

  @link_kinds ~w(references implements_policy_for depends_on documents)
  def allowed_link_kinds, do: @link_kinds

  schema "vault_item_links" do
    field :link_kind, :string, default: "references"

    belongs_to :source, Item, foreign_key: :source_id
    belongs_to :target, Item, foreign_key: :target_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:source_id, :target_id, :link_kind])
    |> validate_required([:source_id, :target_id, :link_kind])
    |> validate_inclusion(:link_kind, @link_kinds)
    |> validate_no_self_link()
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:target_id)
    |> unique_constraint([:source_id, :target_id, :link_kind],
      name: :vault_item_links_source_id_target_id_link_kind_index
    )
  end

  defp validate_no_self_link(changeset) do
    source = get_field(changeset, :source_id)
    target = get_field(changeset, :target_id)

    if not is_nil(source) and source == target do
      add_error(changeset, :target_id, "cannot link an item to itself")
    else
      changeset
    end
  end
end
