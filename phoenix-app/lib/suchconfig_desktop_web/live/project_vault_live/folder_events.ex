defmodule SuchConfigDesktopWeb.ProjectVaultLive.FolderEvents do
  @moduledoc """
  Event handlers for project folder creation and selection.
  """

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents
  alias SuchConfigDesktopWeb.TrustedFolderEvents

  def open_new_folder_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_new_folder_modal: true,
       folder_name: "",
       folder_description: "",
       folder_tags: "",
       new_folder_link_path: nil,
       new_folder_link_stage: :select_path,
       new_folder_link_error: nil,
       new_folder_run_sentinel: false,
       error: nil
     )}
  end

  def cancel_new_folder_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_new_folder_modal: false,
       folder_name: "",
       folder_description: "",
       folder_tags: "",
       new_folder_link_path: nil,
       new_folder_link_stage: :idle,
       new_folder_link_error: nil,
       new_folder_run_sentinel: false,
       error: nil
     )}
  end

  def new_folder_form_change(params, socket) do
    {:noreply,
     assign(socket,
       folder_name: Map.get(params, "folder_name", "") |> to_string(),
       folder_description: Map.get(params, "folder_description", "") |> to_string(),
       folder_tags: Map.get(params, "folder_tags", "") |> to_string(),
       new_folder_run_sentinel: checkbox_checked?(params, "run_sentinel_scan")
     )}
  end

  def folder_selected_for_new_project(path, socket) when is_binary(path) do
    trimmed = String.trim(path)

    if trimmed == "" do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         new_folder_link_path: trimmed,
         new_folder_link_stage: :ready,
         new_folder_link_error: nil,
         error: nil
       )}
    end
  end

  def folder_select_error_for_new_project(message, socket) when is_binary(message) do
    {:noreply,
     assign(socket,
       new_folder_link_stage: :select_path,
       new_folder_link_path: nil,
       new_folder_link_error: message,
       error: nil
     )}
  end

  def create(params, socket) do
    attrs = %{
      name: Map.get(params, "folder_name", "") |> String.trim(),
      description: Map.get(params, "folder_description", "") |> String.trim(),
      tags: Map.get(params, "folder_tags", "") |> String.trim()
    }

    link_path = new_folder_link_path(socket, params)
    run_sentinel? = should_run_sentinel_on_create?(socket, params, link_path)

    case ProjectVault.create_project_folder(attrs) do
      {:ok, folder} ->
        folder = maybe_link_new_folder(folder, link_path)
        folders = ProjectVault.list_project_folders()
        vault_items = list_vault_items_if(socket, folder.id)

        socket =
          socket
          |> assign(
            folders: folders,
            selected_folder_id: folder.id,
            selected_folder_linked_auto_sync: folder.linked_auto_sync || false,
            notes: ProjectVault.list_notes_by_folder(folder.id),
            vault_items: vault_items,
            selected_vault_item_id: nil,
            editor_focus: :note,
            folder_name: "",
            folder_description: "",
            folder_tags: "",
            new_folder_link_path: nil,
            new_folder_link_stage: :idle,
            new_folder_link_error: nil,
            new_folder_run_sentinel: false,
            show_new_folder_modal: false,
            folder_sidebar_expanded: true,
            info: create_success_info(link_path),
            error: nil,
            new_note_form_highlight: false
          )
          |> broadcast_projects_sync()

        socket =
          if run_sentinel? do
            SuchConfigDesktopWeb.ProjectVaultLive.SentinelEvents.start_onboard_scan(
              socket,
              link_path,
              folder.id
            )
          else
            socket
          end

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, error: ProjectVault.format_error(changeset), info: nil)}
    end
  end

  defp checkbox_checked?(params, key) do
    case Map.get(params, key) do
      true -> true
      "true" -> true
      "on" -> true
      _ -> false
    end
  end

  defp new_folder_link_path(socket, params) do
    from_params = Map.get(params, "folder_link_path") || Map.get(params, "link_path")

    cond do
      is_binary(from_params) ->
        trimmed = String.trim(from_params)
        if trimmed != "", do: trimmed, else: fallback_link_path(socket)

      true ->
        fallback_link_path(socket)
    end
  end

  defp fallback_link_path(socket) do
    case socket.assigns[:new_folder_link_path] do
      path when is_binary(path) ->
        trimmed = String.trim(path)
        if trimmed != "", do: trimmed, else: nil

      _ ->
        nil
    end
  end

  defp should_run_sentinel_on_create?(socket, params, link_path) do
    pro? = ProjectVault.security_sentinel_license_enabled?()

    checked? =
      checkbox_checked?(params, "run_sentinel_scan") or
        socket.assigns[:new_folder_run_sentinel] == true

    pro? and checked? and is_binary(link_path) and String.trim(link_path) != ""
  end

  defp maybe_link_new_folder(folder, path) when is_binary(path) do
    trimmed = String.trim(path)

    if trimmed == "" do
      folder
    else
      case ProjectVault.update_project_folder(folder, %{
             linked_project_path: trimmed,
             linked_sync_enabled: true
           }) do
        {:ok, updated} -> updated
        {:error, _} -> folder
      end
    end
  end

  defp maybe_link_new_folder(folder, _), do: folder

  defp create_success_info(path) when is_binary(path) and path != "" do
    "Project folder created and linked."
  end

  defp create_success_info(_), do: "Project folder created."

  def select(%{"id" => id}, socket) do
    folder_id = String.to_integer(id)
    vault_items = list_vault_items_if(socket, folder_id)
    folder = Enum.find(socket.assigns.folders, &(&1.id == folder_id))
    auto_sync = folder && (folder.linked_auto_sync || false)

    {:noreply,
     socket
     |> assign(
       selected_folder_id: folder_id,
       selected_folder_linked_auto_sync: auto_sync,
       notes: ProjectVault.list_notes_by_folder(folder_id),
       vault_items: vault_items,
       selected_note_id: nil,
       selected_vault_item_id: nil,
       editor_focus: :note,
       note_unlocked: false,
       note_category: "generic_note",
       vault_item_kind: "generic_note",
       security_mode: socket.assigns.security_mode,
       note_title: "",
       note_raw_content: "",
       item_tags: [],
       copy_all_copied: false,
       env_var_value_copied: %{},
       env_var_all_copied: %{},
       folder_sidebar_expanded: true,
       vault_activity_visible: false,
       info: nil,
       error: nil,
       new_note_form_highlight: false
     )
     |> VaultItemTagEvents.assign_folder_tags()
     |> SuchConfigDesktopWeb.ProjectVaultLive.SentinelEvents.load_risk_badge()}
  end

  def folder_row_click(%{"id" => id}, socket) do
    folder_id = String.to_integer(id)

    if folder_id == socket.assigns.selected_folder_id do
      {:noreply, socket}
    else
      select(%{"id" => id}, socket)
    end
  end

  def folder_row_click(_params, socket), do: {:noreply, socket}

  def open_edit(%{"id" => id}, socket) do
    folder_id = String.to_integer(id)
    folder = ProjectVault.get_project_folder!(folder_id)

    {:noreply,
     assign(socket,
       show_edit_folder_modal: true,
       editing_folder_id: folder.id,
       edit_folder_name: folder.name,
       edit_folder_delete_confirm: false,
       error: nil
     )}
  end

  def request_delete_folder(_params, socket) do
    if socket.assigns.editing_folder_id do
      {:noreply, assign(socket, edit_folder_delete_confirm: true)}
    else
      {:noreply, socket}
    end
  end

  def cancel_delete_folder_confirm(_params, socket) do
    {:noreply, assign(socket, edit_folder_delete_confirm: false)}
  end

  def cancel_edit(_params, socket) do
    {:noreply,
     assign(socket,
       show_edit_folder_modal: false,
       editing_folder_id: nil,
       edit_folder_name: "",
       edit_folder_delete_confirm: false,
       error: nil
     )}
  end

  def edit_folder_input(%{"name" => name}, socket) do
    {:noreply, assign(socket, edit_folder_name: name)}
  end

  def edit_folder_input(_params, socket), do: {:noreply, socket}

  def save_edit(%{"name" => name}, socket) do
    name = name |> to_string() |> String.trim()
    folder_id = socket.assigns.editing_folder_id

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Folder name is required.")}

      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "No folder selected.", show_edit_folder_modal: false)}

      true ->
        folder = ProjectVault.get_project_folder!(folder_id)

        case ProjectVault.update_project_folder(folder, %{name: name}) do
          {:ok, _} ->
            folders = ProjectVault.list_project_folders()

            {:noreply,
             assign(socket,
               folders: folders,
               show_edit_folder_modal: false,
               editing_folder_id: nil,
               edit_folder_name: "",
               edit_folder_delete_confirm: false,
               info: "Folder updated.",
               error: nil
             )
             |> broadcast_projects_sync()}

          {:error, changeset} ->
            {:noreply, assign(socket, error: ProjectVault.format_error(changeset), info: nil)}
        end
    end
  end

  def save_edit(params, socket) do
    save_edit(Map.put_new(params, "name", socket.assigns.edit_folder_name || ""), socket)
  end

  def delete_editing(_params, socket) do
    folder_id = socket.assigns.editing_folder_id

    cond do
      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "No folder selected.")}

      true ->
        folder = ProjectVault.get_project_folder!(folder_id)

        case ProjectVault.delete_project_folder(folder) do
          {:ok, _} ->
            folders = ProjectVault.list_project_folders()
            was_selected = socket.assigns.selected_folder_id == folder_id

            {selected_folder_id, notes, vault_items} =
              cond do
                folders == [] ->
                  {nil, [], []}

                was_selected ->
                  next = List.first(folders)
                  vid = next.id

                  vis =
                    if socket.assigns[:vault_item_ui_enabled?],
                      do: ProjectVault.list_vault_items_by_folder(vid),
                      else: []

                  {vid, ProjectVault.list_notes_by_folder(vid), vis}

                true ->
                  fid = socket.assigns.selected_folder_id

                  vis =
                    if socket.assigns[:vault_item_ui_enabled?] and fid,
                      do: ProjectVault.list_vault_items_by_folder(fid),
                      else: socket.assigns[:vault_items] || []

                  {fid, ProjectVault.list_notes_by_folder(fid), vis}
              end

            {:noreply,
             assign(socket,
               folders: folders,
               selected_folder_id: selected_folder_id,
               notes: notes,
               vault_items: vault_items,
               selected_note_id: if(was_selected, do: nil, else: socket.assigns.selected_note_id),
               selected_vault_item_id:
                 if(was_selected, do: nil, else: socket.assigns[:selected_vault_item_id]),
               editor_focus:
                 if(was_selected, do: :note, else: socket.assigns[:editor_focus] || :note),
               note_unlocked: if(was_selected, do: false, else: socket.assigns.note_unlocked),
               note_title: if(was_selected, do: "", else: socket.assigns.note_title),
               note_raw_content: if(was_selected, do: "", else: socket.assigns.note_raw_content),
               folder_sidebar_expanded: if(selected_folder_id, do: true, else: false),
               show_edit_folder_modal: false,
               editing_folder_id: nil,
               edit_folder_name: "",
               edit_folder_delete_confirm: false,
               info: "Folder deleted.",
               error: nil,
               new_note_form_highlight: false
             )
             |> broadcast_projects_sync()
             |> maybe_navigate_parent_to_projects()}

          {:error, changeset} ->
            {:noreply, assign(socket, error: ProjectVault.format_error(changeset), info: nil)}
        end
    end
  end

  defp list_vault_items_if(socket, folder_id) do
    if socket.assigns[:vault_item_ui_enabled?] and folder_id,
      do: ProjectVault.list_vault_items_by_folder(folder_id),
      else: []
  end

  defp broadcast_projects_sync(socket) do
    socket
    |> notify_parent_projects_changed()
    |> TrustedFolderEvents.notify_projects_changed()
  end

  defp notify_parent_projects_changed(socket) do
    with true <- socket.assigns[:embedded] == true,
         pid when is_pid(pid) <- socket.parent_pid do
      send(pid, :refresh_project_entries)
    else
      _ -> :ok
    end

    socket
  end

  defp maybe_navigate_parent_to_projects(socket) do
    with true <- socket.assigns[:embedded] == true,
         pid when is_pid(pid) <- socket.parent_pid do
      send(pid, {:parent, :navigate, :projects})
    else
      _ -> :ok
    end

    socket
  end
end
