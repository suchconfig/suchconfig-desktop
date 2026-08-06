defmodule SuchConfigDesktopWeb.SecretsVaultLive.TagEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.KindFields
  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting
  alias SuchConfigDesktopWeb.SecretsVaultLive.ViewData

  @secrets_suggested_tags [
    "Work",
    "Personal",
    "Production",
    "Staging",
    "Dev",
    "Shared",
    "Secrets",
    "Security"
  ]

  def tag_suggestions(tags_by_item_id, extra_tags \\ []) when is_map(tags_by_item_id) do
    base =
      tags_by_item_id
      |> Map.values()
      |> List.flatten()

    (@secrets_suggested_tags ++ base ++ List.wrap(extra_tags))
    |> Enum.map(&VaultItemTags.normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def load_item_tags(socket, item, password) do
    tags =
      case SecretsVault.decrypt_item_frontmatter(item, password) do
        {:ok, fm} -> VaultItemTags.decode(Map.get(fm, "tags"))
        _ -> []
      end

    assign(socket, item_tags: tags)
  end

  def clear_item_tags(socket), do: assign(socket, item_tags: [])

  def add_item_tag(%{"tag" => raw}, socket) do
    tag = VaultItemTags.normalize_tag(raw)

    if tag == "" do
      {:noreply, socket}
    else
      tags =
        socket.assigns[:item_tags]
        |> List.wrap()
        |> Enum.map(&VaultItemTags.normalize_tag/1)
        |> then(&Enum.uniq([tag | &1]))

      {:noreply, socket |> assign(item_tags: tags) |> ViewData.assign_view_data()}
    end
  end

  def add_item_tag(_params, socket), do: {:noreply, socket}

  def add_item_tag_from_input(params, socket) do
    add_item_tag(%{"tag" => Map.get(params, "new_item_tag", "")}, socket)
  end

  def remove_item_tag(%{"tag" => raw}, socket) do
    tag = VaultItemTags.normalize_tag(raw)

    tags =
      socket.assigns[:item_tags]
      |> List.wrap()
      |> Enum.reject(&(VaultItemTags.normalize_tag(&1) == tag))

    {:noreply, socket |> assign(item_tags: tags) |> ViewData.assign_view_data()}
  end

  def remove_item_tag(_params, socket), do: {:noreply, socket}

  def frontmatter_for_save(socket) do
    kind = Formatting.normalize_kind(socket.assigns.item_kind)

    base =
      KindFields.build_frontmatter(kind, %{
        username: socket.assigns.username,
        url: socket.assigns.url,
        public_key: socket.assigns.public_key,
        fingerprint: socket.assigns.fingerprint
      })

    user_tags =
      if socket.assigns[:show_new_entry_modal] do
        VaultItemTags.decode(socket.assigns[:new_entry_tags] || "")
      else
        socket.assigns[:item_tags] || []
      end

    VaultItemTags.merge_frontmatter(base, user_tags)
  end
end
