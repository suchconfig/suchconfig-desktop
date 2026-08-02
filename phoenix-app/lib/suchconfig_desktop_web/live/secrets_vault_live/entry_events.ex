defmodule SuchConfigDesktopWeb.SecretsVaultLive.EntryEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting
  alias SuchConfigDesktopWeb.SecretsVaultLive.Generator
  alias SuchConfigDesktopWeb.SecretsVaultLive.TagEvents
  alias SuchConfigDesktopWeb.SecretsVaultLive.ViewData
  alias SuchConfigDesktopWeb.TrustedFolderEvents
  alias SuchConfigDesktopWeb.P2pLanSyncEvents

  def toggle_filter_panel(_params, socket) do
    opening = !socket.assigns.filter_open

    socket =
      socket
      |> assign(filter_open: opening)
      |> then(fn s ->
        if opening, do: ViewData.assign_view_data(s, load_all_items: true), else: s
      end)

    {:noreply, socket}
  end

  def close_filter_panel(_params, socket) do
    if socket.assigns.filter_open do
      {:noreply, assign(socket, filter_open: false)}
    else
      {:noreply, socket}
    end
  end

  def filter_panel_search(%{"query" => query}, socket) when is_binary(query) do
    {:noreply, assign(socket, filter_panel_query: query)}
  end

  def toggle_filter_type(%{"type" => type}, socket)
      when type in ["login", "api", "ssh", "note"] do
    types = toggle_list_member(socket.assigns.filter_types, type)
    {:noreply, socket |> assign(filter_types: types) |> ViewData.assign_view_data()}
  end

  def toggle_filter_tag(%{"tag" => tag}, socket) when is_binary(tag) do
    tags = toggle_list_member(socket.assigns.filter_tags, tag)
    {:noreply, socket |> assign(filter_tags: tags) |> ViewData.assign_view_data()}
  end

  def clear_filters(_params, socket) do
    {:noreply,
     socket
     |> assign(filter_types: [], filter_tags: [], filter_panel_query: "")
     |> ViewData.assign_view_data()}
  end

  def search_change(%{"search" => query}, socket) when is_binary(query) do
    folder_id = Formatting.items_query_folder_id(socket.assigns.selected_folder_id)
    password = socket.assigns.vault_password

    items =
      if socket.assigns.global_passkey_unlocked and password != "" do
        SecretsVault.search_items(folder_id, query, password)
      else
        SecretsVault.list_items(folder_id)
      end

    {:noreply, socket |> assign(search_query: query, items: items) |> ViewData.assign_view_data()}
  end

  def select_item(%{"id" => id}, socket) do
    item_id = parse_id(id)

    if is_nil(item_id) do
      {:noreply, socket}
    else
      load_item_into_editor(socket, item_id)
    end
  end

  def show_vault_stats(_params, socket) do
    {:noreply,
     socket
     |> assign(vault_panel: :stats)
     |> ViewData.assign_view_data(load_all_items: true)}
  end

  def close_new_entry_modal(_params, socket) do
    {:noreply, assign(socket, show_new_entry_modal: false)}
  end

  def set_new_entry_kind(%{"type" => type}, socket) when is_binary(type) do
    {:noreply,
     assign(socket,
       item_kind: Formatting.kind_from_modal_type(type),
       show_secret: false
     )}
  end

  def new_item(params, socket) do
    socket = sync_folder_from_params(socket, params)
    type = Map.get(params, "type", "login")
    new_item_of_type(type, socket)
  end

  def new_item_of_type(type, socket) when is_binary(type) do
    kind = Formatting.kind_from_modal_type(type)

    cond do
      socket.assigns.global_passkey_unlocked ->
        {:noreply,
         assign(
           socket,
           empty_editor_fields() ++
             [
               item_kind: kind,
               show_new_entry_modal: true,
               new_entry_tags: "",
               item_tags: [],
               new_entry_folder_id:
                 Formatting.new_entry_folder_id(socket.assigns.selected_folder_id)
             ]
         )}

      true ->
        {:noreply,
         assign(socket,
           pending_unlock_action: {:new_item, type},
           show_global_passkey_modal: true,
           global_passkey_purpose: "save"
         )}
    end
  end

  def new_item_of_type(_, socket), do: new_item_of_type("login", socket)

  def entry_form_change(params, socket) do
    previous_kind = Formatting.normalize_kind(socket.assigns.item_kind)

    socket =
      socket
      |> sync_folder_from_params(params)
      |> apply_entry_form_params(params)

    next_kind = Formatting.normalize_kind(socket.assigns.item_kind)

    socket =
      if previous_kind != next_kind do
        assign(socket, show_secret: false)
      else
        socket
      end

    {:noreply, socket}
  end

  def toggle_reveal(_params, socket) do
    if socket.assigns.global_passkey_unlocked do
      {:noreply, assign(socket, show_secret: !socket.assigns.show_secret)}
    else
      {:noreply, assign(socket, error: "Unlock the vault to reveal secrets.")}
    end
  end

  def copy_secret(_params, socket) do
    copy_field_value(socket, socket.assigns.secret_body, "Copied to clipboard.")
  end

  def copy_username(_params, socket) do
    copy_field_value(socket, socket.assigns.username, "Username copied.")
  end

  def copy_public_key(_params, socket) do
    copy_field_value(socket, socket.assigns.public_key, "Public key copied.")
  end

  def copy_fingerprint(_params, socket) do
    copy_field_value(socket, socket.assigns.fingerprint, "Fingerprint copied.")
  end

  def save_item(params, socket) do
    socket =
      socket
      |> sync_folder_from_params(params)
      |> apply_entry_form_params(params)

    cond do
      not socket.assigns.global_passkey_unlocked ->
        {:noreply,
         assign(socket,
           pending_unlock_action: :save_item,
           show_global_passkey_modal: true,
           global_passkey_purpose: "save"
         )}

      true ->
        persist_item(socket)
    end
  end

  def open_delete_modal(_params, socket) do
    if socket.assigns.selected_item_id do
      {:noreply, assign(socket, show_delete_modal: true)}
    else
      {:noreply, socket}
    end
  end

  def close_delete_modal(_params, socket) do
    {:noreply, assign(socket, show_delete_modal: false)}
  end

  def confirm_delete(_params, socket) do
    case SecretsVault.delete_item(socket.assigns.selected_item_id) do
      {:ok, _} ->
        folder_id = Formatting.items_query_folder_id(socket.assigns.selected_folder_id)
        items = SecretsVault.list_items(folder_id)

        socket =
          case socket.assigns[:vault_session_id] do
            session_id when is_binary(session_id) ->
              TrustedFolderEvents.broadcast_sync(session_id, "secrets")
              P2pLanSyncEvents.broadcast_sync(session_id, "secrets")
              socket

            _ ->
              socket
          end

        {:noreply,
         socket
         |> assign(empty_editor_fields())
         |> assign(
           items: items,
           show_delete_modal: false,
           info: "Entry deleted.",
           error: nil
         )
         |> ViewData.assign_view_data(refresh_all_items: true)}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not delete entry.", show_delete_modal: false)}
    end
  end

  def open_generator_drawer(params, socket) do
    socket =
      if socket.assigns.embedded do
        context = Generator.context_from_params(params)
        mode = Generator.mode_from_params(params, context)
        target = Generator.target_from_params(params)

        Generator.broadcast_open(:secrets_entry, mode: mode, target: target)
        socket
      else
        Generator.open_from_params(params, socket)
      end

    {:noreply, socket}
  end

  def close_generator_drawer(_params, socket) do
    {:noreply, Generator.close(socket)}
  end

  def roll_generator(_params, socket) do
    {:noreply, Generator.roll(socket)}
  end

  def set_generator_mode(%{"mode" => mode}, socket) do
    if mode in Generator.modes() do
      {:noreply, Generator.set_mode(socket, mode)}
    else
      {:noreply, socket}
    end
  end

  def set_generator_username_form(params, socket) do
    {:noreply, Generator.set_username_form(socket, params)}
  end

  def set_generator_length(params, socket) do
    {:noreply, Generator.set_length(socket, Generator.parse_length_from_params(params))}
  end

  def toggle_generator_opt(%{"opt" => opt, "on" => on}, socket) do
    {:noreply, Generator.toggle_opt(socket, opt, on == "true")}
  end

  def copy_generator(_params, socket) do
    value = socket.assigns.generator_value

    if socket.assigns.global_passkey_unlocked and value != "" do
      socket =
        socket
        |> assign(generator_copied: true, error: nil)

      if connected?(socket) do
        Process.send_after(self(), :clear_generator_copied, 3000)
      end

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Nothing to copy.")}
    end
  end

  def set_generator_password(_params, socket) do
    value = socket.assigns.generator_value

    {:noreply,
     socket
     |> assign(
       secret_body: value,
       generator_strength: socket.assigns.generator_strength_level,
       show_generator_drawer: false,
       info: "Password set on entry.",
       error: nil
     )}
  end

  def set_generator_username(_params, socket) do
    value = socket.assigns.generator_value

    {:noreply,
     socket
     |> assign(
       username: value,
       show_generator_drawer: false,
       info: "Username set on entry.",
       error: nil
     )}
  end

  defp persist_item(socket) do
    password = socket.assigns.vault_password
    kind = Formatting.normalize_kind(socket.assigns.item_kind)
    folder_id = folder_id_for_save(socket)

    attrs = %{
      id: socket.assigns.selected_item_id,
      title: socket.assigns.item_title,
      kind: kind,
      security_mode: "global_passkey",
      secrets_vault_folder_id: folder_id,
      body: socket.assigns.secret_body,
      frontmatter: TagEvents.frontmatter_for_save(socket)
    }

    case SecretsVault.save_item(attrs, password) do
      {:ok, item} ->
        saved_folder_id = item.secrets_vault_folder_id
        show_all? = Formatting.show_all_folder_selected?(socket.assigns.selected_folder_id)

        items =
          if show_all? do
            SecretsVault.list_items(nil)
          else
            SecretsVault.list_items(saved_folder_id)
          end

        selected_folder_id =
          if show_all?, do: Formatting.show_all_folder_id(), else: saved_folder_id

        {:noreply,
         socket
         |> assign(
           items: items,
           selected_folder_id: selected_folder_id,
           selected_item_id: item.id,
           vault_panel: :detail,
           item_kind: Formatting.normalize_kind(item.kind),
           show_new_entry_modal: false,
           new_entry_tags: "",
           new_entry_folder_id: nil,
           entry_folder_id: folder_id,
           info: "Entry saved.",
           error: nil
         )
         |> TagEvents.load_item_tags(item, password)
         |> ViewData.assign_view_data(refresh_all_items: true)
         |> tap(fn s ->
           TrustedFolderEvents.broadcast_sync(s.assigns[:vault_session_id], "secrets")
           P2pLanSyncEvents.broadcast_sync(s.assigns[:vault_session_id], "secrets")
         end)}

      {:error, reason} ->
        {:noreply, assign(socket, error: Formatting.save_error_message(reason))}
    end
  end

  defp load_item_into_editor(socket, item_id) do
    item = SecretsVault.get_item!(item_id)
    password = socket.assigns.vault_password

    with {:ok, body} <- SecretsVault.decrypt_item_body(item, password),
         {:ok, fm} <- SecretsVault.decrypt_item_frontmatter(item, password) do
      {:noreply,
       socket
       |> assign(
         selected_item_id: item.id,
         vault_panel: :detail,
         item_title: item.title,
         item_kind: Formatting.normalize_kind(item.kind),
         username: Map.get(fm, "username", ""),
         url: Map.get(fm, "url", ""),
         public_key: Map.get(fm, "public_key", ""),
         fingerprint: Map.get(fm, "fingerprint", ""),
         secret_body: body,
         show_secret: false,
         item_inserted_at: item.inserted_at,
         item_updated_at: item.updated_at,
         entry_folder_id: item.secrets_vault_folder_id,
         error: nil
       )
       |> TagEvents.load_item_tags(item, password)
       |> ViewData.assign_view_data()}
    else
      _ ->
        {:noreply,
         assign(socket,
           selected_item_id: item.id,
           vault_panel: :detail,
           item_title: item.title,
           item_kind: Formatting.normalize_kind(item.kind),
           error: "Could not decrypt this entry. Check your passkey."
         )}
    end
  end

  defp empty_editor_fields do
    [
      selected_item_id: nil,
      entry_folder_id: nil,
      vault_panel: :stats,
      item_title: "",
      item_kind: "password",
      username: "",
      url: "",
      public_key: "",
      fingerprint: "",
      secret_body: "",
      show_secret: false,
      item_inserted_at: nil,
      item_updated_at: nil,
      item_tags: [],
      info: nil,
      error: nil
    ]
  end

  defp copy_field_value(socket, value, success_message) do
    if socket.assigns.global_passkey_unlocked and value != "" do
      {:noreply,
       socket
       |> push_event("copy_to_clipboard", %{content: value})
       |> assign(info: success_message, error: nil)}
    else
      {:noreply, assign(socket, error: "Nothing to copy.")}
    end
  end

  defp sync_folder_from_params(socket, params) do
    case Map.get(params, "secrets_vault_folder_id") do
      id when is_binary(id) ->
        folder_id = if id == "", do: nil, else: parse_id(id)
        folder_assign(socket, folder_id)

      _ ->
        socket
    end
  end

  defp folder_assign(socket, folder_id) do
    cond do
      socket.assigns.show_new_entry_modal ->
        assign(socket, new_entry_folder_id: folder_id)

      socket.assigns.selected_item_id ->
        assign(socket, entry_folder_id: folder_id)

      true ->
        socket
    end
  end

  defp folder_id_for_save(socket) do
    folder_id =
      cond do
        socket.assigns.show_new_entry_modal ->
          socket.assigns.new_entry_folder_id

        socket.assigns.selected_item_id ->
          socket.assigns.entry_folder_id || socket.assigns.selected_folder_id

        true ->
          socket.assigns.new_entry_folder_id || socket.assigns.selected_folder_id
      end

    Formatting.save_folder_id(folder_id)
  end

  defp apply_entry_form_params(socket, params) do
    next_kind = params |> Map.get("kind", socket.assigns.item_kind) |> Formatting.normalize_kind()

    folder_id =
      folder_id_from_params(
        params,
        folder_id_fallback(socket)
      )

    socket =
      assign(socket,
        item_title: Map.get(params, "title", socket.assigns.item_title),
        item_kind: next_kind,
        username: Map.get(params, "username", socket.assigns.username),
        url: Map.get(params, "url", socket.assigns.url),
        public_key: Map.get(params, "public_key", socket.assigns.public_key),
        fingerprint: Map.get(params, "fingerprint", socket.assigns.fingerprint),
        secret_body: Map.get(params, "secret_body", socket.assigns.secret_body),
        new_entry_tags: Map.get(params, "new_entry_tags", socket.assigns[:new_entry_tags] || "")
      )

    folder_assign(socket, folder_id)
  end

  defp folder_id_fallback(socket) do
    cond do
      socket.assigns.show_new_entry_modal -> socket.assigns[:new_entry_folder_id]
      socket.assigns.selected_item_id -> socket.assigns[:entry_folder_id]
      true -> nil
    end
  end

  defp folder_id_from_params(params, current) do
    case Map.get(params, "secrets_vault_folder_id") do
      id when is_binary(id) and id != "" -> parse_id(id) || current
      "" -> nil
      _ -> current
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(_), do: nil

  defp toggle_list_member(list, value) when is_list(list) do
    if value in list, do: List.delete(list, value), else: list ++ [value]
  end
end
