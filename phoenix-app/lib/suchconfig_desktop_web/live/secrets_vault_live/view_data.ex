defmodule SuchConfigDesktopWeb.SecretsVaultLive.ViewData do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktopWeb.Sc.FilterPopover
  alias SuchConfigDesktopWeb.SecretsVaultLive.{Formatting, TagEvents}

  @not_loaded :not_loaded

  @default_vault_stats %{
    total: 0,
    folder_count: 0,
    login_count: 0,
    api_count: 0,
    ssh_count: 0,
    note_count: 0,
    crdt_enabled?: false
  }

  @doc """
  Computes list/filter/stats assigns for the Secrets Vault UI.

  Call after items, folders, filters, or vault password change — not on lightweight
  editor events (type picker, reveal toggle, form debounce).

  Vault-wide `list_items(nil)` runs only when `refresh_all_items: true`,
  `load_all_items: true`, or `all_items` was already loaded — not on every mount.

  Decrypted tag maps are cached on the socket. Re-decrypt only when vault-wide
  items are refreshed/loaded; folder switches reuse the cache.
  """
  def assign_view_data(socket, opts \\ []) do
    refresh_all_items = Keyword.get(opts, :refresh_all_items, false)
    load_all_items = Keyword.get(opts, :load_all_items, false)
    password = socket.assigns[:vault_password] || ""
    unlocked = socket.assigns[:global_passkey_unlocked] == true and password != ""

    {all_items, all_items_refreshed?} =
      resolve_all_items(socket, refresh_all_items, load_all_items)

    vault_wide_items = items_for_vault_wide(all_items, socket.assigns.items)

    all_tags_by_item_id =
      resolve_all_tags(socket, all_items, vault_wide_items, password, unlocked, all_items_refreshed?)

    tags_by_item_id =
      resolve_folder_tags(socket.assigns.items, all_tags_by_item_id, password, unlocked)

    filtered_items =
      Formatting.filter_items(
        socket.assigns.items,
        socket.assigns.filter_types,
        socket.assigns.filter_tags,
        tags_by_item_id
      )

    suggestion_tags =
      if all_items_loaded?(all_items) and is_map(all_tags_by_item_id) do
        all_tags_by_item_id
      else
        tags_by_item_id
      end

    tag_suggestions =
      if unlocked do
        TagEvents.tag_suggestions(suggestion_tags, socket.assigns[:item_tags] || [])
      else
        []
      end

    filter_type_options = Formatting.filter_type_options(socket.assigns.items)
    filter_tag_options = Formatting.tag_options(socket.assigns.items, tags_by_item_id)
    filter_active_count = length(socket.assigns.filter_types) + length(socket.assigns.filter_tags)

    folder_name =
      if Formatting.show_all_folder_selected?(socket.assigns.selected_folder_id) do
        "Show all"
      else
        Enum.find_value(socket.assigns.folders, "Vault", fn folder ->
          if folder.id == socket.assigns.selected_folder_id, do: folder.name
        end)
      end

    vault_stats =
      Formatting.vault_stats(
        vault_wide_items,
        socket.assigns.folders,
        socket.assigns[:crdt_enabled?]
      )

    filter_panel_assigns =
      FilterPopover.panel_assigns(%{
        id: "secrets-filter",
        panel_query: socket.assigns.filter_panel_query,
        selected_types: socket.assigns.filter_types,
        selected_tags: socket.assigns.filter_tags,
        type_options: filter_type_options,
        tag_options: filter_tag_options,
        active_count: filter_active_count
      })

    tag_count =
      if is_map(all_tags_by_item_id) do
        Formatting.unique_tag_count(all_tags_by_item_id)
      else
        0
      end

    assign(socket,
      all_items: all_items,
      all_tags_by_item_id: all_tags_by_item_id,
      tags_by_item_id: tags_by_item_id,
      filtered_items: filtered_items,
      entry_count: length(socket.assigns.items),
      filter_active_count: filter_active_count,
      tag_count: tag_count,
      filter_type_options: filter_type_options,
      filter_tag_options: filter_tag_options,
      folder_name: folder_name,
      vault_stats: vault_stats,
      tag_suggestions: tag_suggestions,
      generator_event_target: if(socket.assigns[:embedded], do: "#app-live-root", else: nil),
      filter_panel_assigns: filter_panel_assigns
    )
  end

  def default_vault_stats, do: @default_vault_stats

  def not_loaded, do: @not_loaded

  defp resolve_all_items(socket, refresh_all_items, load_all_items) do
    current = socket.assigns[:all_items]

    cond do
      refresh_all_items ->
        {SecretsVault.list_items(nil), true}

      load_all_items and not all_items_loaded?(current) ->
        {SecretsVault.list_items(nil), true}

      all_items_loaded?(current) ->
        {current, false}

      true ->
        {@not_loaded, false}
    end
  end

  defp resolve_all_tags(socket, all_items, vault_wide_items, password, unlocked, all_items_refreshed?) do
    cached = socket.assigns[:all_tags_by_item_id]

    cond do
      not unlocked ->
        @not_loaded

      not all_items_loaded?(all_items) ->
        @not_loaded

      all_items_refreshed? or not is_map(cached) ->
        Formatting.tags_by_item_id(vault_wide_items, password)

      true ->
        cached
    end
  end

  defp resolve_folder_tags(_items, _all_tags, _password, false), do: %{}

  defp resolve_folder_tags(items, all_tags, _password, true) when is_map(all_tags) do
    Map.new(items, fn item -> {item.id, Map.get(all_tags, item.id, [])} end)
  end

  defp resolve_folder_tags(items, _all_tags, password, true) do
    Formatting.tags_by_item_id(items, password)
  end

  defp all_items_loaded?(items), do: is_list(items)

  defp items_for_vault_wide(@not_loaded, folder_items), do: folder_items
  defp items_for_vault_wide(items, _folder_items) when is_list(items), do: items
end
