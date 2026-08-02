defmodule SuchConfigDesktopWeb.ProjectVaultLive.LinkedSyncEvents do
  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.EnvManager.ProjectFolder
  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.LinkedSync
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey

  def assign_sync_status(socket, opts \\ []) do
    auto_open? = Keyword.get(opts, :auto_open_review?, false)
    item_id = socket.assigns[:selected_vault_item_id]
    folder_id = socket.assigns[:selected_folder_id]
    pw = socket.assigns[:vault_password]
    body = socket.assigns[:note_raw_content] || ""

    socket =
      with true <- socket.assigns[:vault_item_ui_enabled?],
           id when is_integer(id) <- item_id,
           fid when is_integer(fid) <- folder_id,
           true <- is_binary(pw) and pw != "",
           %ProjectFolder{} = folder <- find_folder(socket.assigns.folders, fid),
           item <- ProjectVault.get_vault_item!(id) do
        status = LinkedSync.status(item, folder, body, pw)
        assign(socket, linked_sync_status: status)
      else
        _ -> assign(socket, linked_sync_status: :not_linked)
      end

    maybe_auto_open_sync_review(socket, auto_open?)
  end

  def sync_push_to_project(_params, socket) do
    with {:ok, socket} <- ensure_unlocked(socket, :sync_push),
         {:ok, folder, item, pw, body} <- sync_context(socket),
         {:ok, _} <- LinkedSync.push_to_disk(item, folder, body, pw) do
      items = ProjectVault.list_vault_items_by_folder(folder.id)

      {:noreply,
       socket
       |> assign(vault_items: items, info: "Synced to linked project.", error: nil)
       |> assign_sync_status()}
    else
      {:error, :not_linked} ->
        {:noreply, assign(socket, error: "This item is not linked to a project file.", info: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}

      {:locked, socket} ->
        {:noreply, socket}
    end
  end

  def sync_refresh_from_disk(_params, socket) do
    case open_sync_review(socket) do
      {:ok, socket} -> {:noreply, socket}
      {:locked, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def sync_review_accept(_params, socket) do
    disk_body = socket.assigns[:sync_review_disk_body]
    item_id = socket.assigns[:sync_review_item_id]

    with {:ok, socket} <- ensure_unlocked(socket, :sync_push),
         {:ok, folder, item, pw, _} <- sync_context(socket),
         true <- item.id == item_id,
         {:ok, updated} <- LinkedSync.accept_pull(item, folder, disk_body, pw) do
      items = ProjectVault.list_vault_items_by_folder(folder.id)

      {:noreply,
       socket
       |> assign(
         vault_items: items,
         selected_vault_item_id: updated.id,
         note_raw_content: disk_body,
         show_sync_review_modal: false,
         sync_review_disk_body: nil,
         sync_review_vault_body: nil,
         sync_review_diff_lines: [],
         info: "Accepted changes from linked project.",
         error: nil
       )
       |> assign_sync_status()}
    else
      {:locked, socket} ->
        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, error: "Could not apply linked file changes.", info: nil)}
    end
  end

  def sync_review_reject(_params, socket) do
    {:noreply,
     assign(socket,
       show_sync_review_modal: false,
       sync_review_disk_body: nil,
       sync_review_vault_body: nil,
       sync_review_diff_lines: [],
       info: nil
     )}
  end

  def toggle_folder_auto_sync(_params, socket) do
    folder_id = socket.assigns[:selected_folder_id]

    with fid when is_integer(fid) <- folder_id,
         %ProjectFolder{} = folder <- ProjectVault.get_project_folder!(fid),
         next <- !(folder.linked_auto_sync || false),
         {:ok, _} <- ProjectVault.update_project_folder(folder, %{linked_auto_sync: next}) do
      folders = ProjectVault.list_project_folders()

      {:noreply,
       assign(socket,
         folders: folders,
         selected_folder_linked_auto_sync: next,
         info: if(next, do: "Always sync files enabled.", else: "Always sync files disabled."),
         error: nil
       )}
    else
      _ -> {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}
    end
  end

  def upgrade_legacy_note(_params, socket) do
    note_id = socket.assigns[:selected_note_id]
    folder_id = socket.assigns[:selected_folder_id]
    pw = socket.assigns[:vault_password]

    with id when is_integer(id) <- note_id,
         fid when is_integer(fid) <- folder_id,
         true <- is_binary(pw) and pw != "",
         note <- ProjectVault.get_note!(id),
         {:ok, item} <- ProjectVault.upgrade_legacy_note_to_vault_item(note, fid, pw) do
      items = ProjectVault.list_vault_items_by_folder(fid)
      notes = ProjectVault.list_notes_by_folder(fid)

      {:noreply,
       assign(socket,
         vault_items: items,
         notes: notes,
         selected_note_id: nil,
         selected_vault_item_id: item.id,
         editor_focus: :vault_item,
         note_title: item.title,
         note_category: item.kind,
         info: "Upgraded to vault item.",
         error: nil
       )
       |> VaultItemTagEvents.load_item_tags(item, pw)
       |> VaultItemTagEvents.assign_folder_tags()
       |> assign_sync_status()}
    else
      _ ->
        {:noreply, assign(socket, error: "Could not upgrade legacy note.", info: nil)}
    end
  end

  def handle_linked_file_changed(socket, %{"folder_id" => fid, "relative_path" => rel}) do
    folder_id = socket.assigns[:selected_folder_id]

    if same_folder_id?(folder_id, fid) and selected_item_matches_linked_path?(socket, rel) do
      {:noreply,
       socket
       |> assign(info: "Linked file changed on disk.", error: nil)
       |> assign_sync_status(auto_open_review?: true)}
    else
      {:noreply, socket}
    end
  end

  def maybe_auto_push_after_save(socket) do
    with true <- socket.assigns[:selected_folder_linked_auto_sync],
         {:ok, folder, item, pw, body} <- sync_context(socket),
         :vault_ahead <- LinkedSync.status(item, folder, body, pw),
         {:ok, _} <- LinkedSync.push_to_disk(item, folder, body, pw) do
      assign(socket, info: "Synced to linked project.", linked_sync_status: :in_sync)
    else
      _ -> socket
    end
  end

  defp maybe_auto_open_sync_review(socket, false), do: socket

  defp maybe_auto_open_sync_review(socket, true) do
    status = socket.assigns[:linked_sync_status]

    if status in [:disk_ahead, :conflict] and not socket.assigns[:show_sync_review_modal] do
      case open_sync_review(socket) do
        {:ok, socket} -> socket
        {:locked, socket} -> socket
        {:error, socket} -> socket
      end
    else
      socket
    end
  end

  defp open_sync_review(socket) do
    with {:ok, socket} <- ensure_unlocked(socket, :sync_refresh),
         {:ok, folder, item, pw, body} <- sync_context(socket),
         {:ok, preview} <- LinkedSync.pull_preview(item, folder, body, pw) do
      rel = LinkedSync.linked_relative_path(item, folder, pw) || item.title

      {:ok,
       assign(socket,
         show_sync_review_modal: true,
         sync_review_disk_body: preview.disk_body,
         sync_review_vault_body: preview.vault_body,
         sync_review_diff_lines: preview.diff_lines,
         sync_review_item_id: item.id,
         sync_review_relative_path: rel,
         error: nil,
         info: nil
       )}
    else
      {:error, :not_linked} ->
        {:error, assign(socket, error: "This item is not linked to a project file.", info: nil)}

      {:error, reason} ->
        {:error, assign(socket, error: ProjectVault.format_error(reason), info: nil)}

      {:locked, socket} ->
        {:locked, socket}
    end
  end

  defp selected_item_matches_linked_path?(socket, rel) when is_binary(rel) do
    item_id = socket.assigns[:selected_vault_item_id]
    folder_id = socket.assigns[:selected_folder_id]
    pw = socket.assigns[:vault_password]
    norm_rel = normalize_linked_path(rel)

    with id when is_integer(id) <- item_id,
         fid when is_integer(fid) <- folder_id,
         %{} = item <- ProjectVault.get_vault_item(id),
         %ProjectFolder{} = folder <- find_folder(socket.assigns.folders, fid) do
      norm_rel == normalize_linked_path(item.title) or
        linked_path_match?(item, norm_rel, socket) or
        linked_path_match?(item, rel, socket) or
        (is_binary(pw) and pw != "" and
           LinkedSync.linked_relative_path(item, folder, pw) in [rel, norm_rel])
    else
      _ -> false
    end
  end

  defp selected_item_matches_linked_path?(_, _), do: false

  defp normalize_linked_path(path) when is_binary(path) do
    path |> String.trim() |> Path.basename()
  end

  defp same_folder_id?(folder_id, fid) do
    folder_id != nil and to_string(folder_id) == to_string(fid)
  end

  defp linked_path_match?(item, rel, socket) do
    pw = socket.assigns[:vault_password]

    case ProjectVault.vault_item_frontmatter(item, pw, "linked_relative_path") do
      {:ok, path} -> normalize_linked_path(path) == normalize_linked_path(rel)
      _ -> false
    end
  end

  defp sync_context(socket) do
    folder_id = socket.assigns[:selected_folder_id]
    item_id = socket.assigns[:selected_vault_item_id]
    pw = socket.assigns[:vault_password]
    body = socket.assigns[:note_raw_content] || ""

    with fid when is_integer(fid) <- folder_id,
         id when is_integer(id) <- item_id,
         true <- is_binary(pw) and pw != "",
         %ProjectFolder{} = folder <- find_folder(socket.assigns.folders, fid),
         %{} = item <- ProjectVault.get_vault_item(id) do
      {:ok, folder, item, pw, body}
    else
      _ -> {:error, :not_linked}
    end
  end

  defp ensure_unlocked(socket, pending_action) do
    socket = VaultKey.ensure_vault_key_from_registry(socket)
    pw = socket.assigns[:vault_password]

    if is_binary(pw) and pw != "" do
      {:ok, socket}
    else
      {:locked,
       assign(socket,
         show_global_passkey_modal: true,
         global_passkey_purpose: "save",
         pending_unlock_action: pending_action,
         error: nil,
         info: nil
       )}
    end
  end

  defp find_folder(folders, id) when is_list(folders) do
    Enum.find(folders, &(&1.id == id))
  end
end
