defmodule SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents do
  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.BrokerFrontmatter
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  def assign_folder_tags(socket) do
    folder_id = socket.assigns[:selected_folder_id]
    pw = socket.assigns[:vault_password]
    items = if folder_id, do: ProjectVault.list_vault_items_by_folder(folder_id), else: []

    socket
    |> assign(vault_item_tags: VaultItemTags.tags_by_item_id(items, pw))
    |> assign(
      tag_suggestions:
        VaultItemTags.folder_tag_suggestions(items, pw, socket.assigns[:item_tags] || [])
    )
  end

  def load_item_tags(socket, item, password) do
    tags = VaultItemTags.display_tags(item, password)

    socket
    |> assign(item_tags: tags)
    |> assign(display_mode: Formatting.default_display_mode(item.kind, tags))
  end

  def load_draft_tags(socket) do
    assign(socket, item_tags: [], display_mode: :input)
  end

  def add_item_tag(%{"tag" => raw}, socket) do
    tag = VaultItemTags.normalize_tag(raw)

    if tag == "" or tag == VaultItemTags.system_linked_tag() do
      {:noreply, socket}
    else
      tags =
        socket.assigns[:item_tags]
        |> List.wrap()
        |> Enum.map(&VaultItemTags.normalize_tag/1)
        |> then(&Enum.uniq([tag | &1]))

      {:noreply,
       socket
       |> assign(item_tags: tags)
       |> assign(
         display_mode:
           env_display_mode_after_tag_change(
             socket.assigns.note_category,
             socket.assigns[:item_tags],
             tags,
             socket.assigns.display_mode
           )
       )}
    end
  end

  def add_item_tag(_params, socket), do: {:noreply, socket}

  def add_item_tag_from_input(params, socket) do
    add_item_tag(%{"tag" => Map.get(params, "new_item_tag", "")}, socket)
  end

  def add_item_tag_keydown(%{"key" => "Enter"} = params, socket) do
    tag = Map.get(params, "value") || Map.get(params, "new_item_tag", "")
    add_item_tag(%{"tag" => tag}, socket)
  end

  def add_item_tag_keydown(_params, socket), do: {:noreply, socket}

  def remove_item_tag(%{"tag" => raw}, socket) do
    tag = VaultItemTags.normalize_tag(raw)

    tags =
      socket.assigns[:item_tags]
      |> List.wrap()
      |> Enum.reject(&(VaultItemTags.normalize_tag(&1) == tag))

    {:noreply,
     socket
     |> assign(item_tags: tags)
     |> assign(
       display_mode:
         env_display_mode_after_tag_change(
           socket.assigns.note_category,
           socket.assigns[:item_tags],
           tags,
           socket.assigns.display_mode
         )
     )}
  end

  def remove_item_tag(_params, socket), do: {:noreply, socket}

  defp env_display_mode_after_tag_change(note_category, previous_tags, next_tags, current_mode) do
    was_env? = Formatting.env_display_mode?(note_category, previous_tags)
    now_env? = Formatting.env_display_mode?(note_category, next_tags)

    cond do
      now_env? and not was_env? -> :copy
      now_env? -> current_mode
      true -> :input
    end
  end

  def frontmatter_for_save(socket, item_id, user_tags \\ nil) do
    pw = socket.assigns[:vault_password]
    tags = user_tags || socket.assigns[:item_tags] || []

    existing =
      case item_id do
        id when is_integer(id) ->
          case ProjectVault.get_vault_item(id) do
            %{} = item -> read_preservable_frontmatter(item, pw)
            _ -> %{}
          end

        _ ->
          %{}
      end

    VaultItemTags.merge_frontmatter(existing, tags)
  end

  def read_preservable_frontmatter(item, password) do
    keys =
      [VaultItemTags.frontmatter_key(), LinkedFrontmatter.relative_path()] ++
        LinkedFrontmatter.agreement_keys() ++ BrokerFrontmatter.keys()

    keys
    |> Enum.flat_map(fn key ->
      case ProjectVault.vault_item_frontmatter(item, password, key) do
        {:ok, v} when is_binary(v) -> [{key, v}]
        _ -> []
      end
    end)
    |> Map.new()
  end
end
