defmodule SuchConfigDesktopWeb.ProjectsLive.FolderEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktopWeb.ProjectsLive.Formatting
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
       project_error: nil
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
       project_error: nil
     )}
  end

  def new_folder_form_change(params, socket) do
    {:noreply,
     assign(socket,
       folder_name: Map.get(params, "folder_name", "") |> to_string(),
       folder_description: Map.get(params, "folder_description", "") |> to_string(),
       folder_tags: Map.get(params, "folder_tags", "") |> to_string(),
       new_folder_run_sentinel: checkbox_checked?(params, "run_sentinel_scan"),
       project_error: nil
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
         project_error: nil
       )}
    end
  end

  def folder_select_error_for_new_project(message, socket) when is_binary(message) do
    {:noreply,
     assign(socket,
       new_folder_link_stage: :select_path,
       new_folder_link_path: nil,
       new_folder_link_error: message,
       project_error: nil
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
    open_link_preview? = link_path_present?(link_path)

    case ProjectVault.create_project_folder(attrs) do
      {:ok, folder} ->
        folder =
          if open_link_preview?, do: folder, else: maybe_link_new_folder(folder, link_path)

        folders = ProjectVault.list_project_folders()

        socket =
          socket
          |> assign(
            folders: folders,
            folder_name: "",
            folder_description: "",
            folder_tags: "",
            new_folder_link_path: nil,
            new_folder_link_stage: :idle,
            new_folder_link_error: nil,
            new_folder_run_sentinel: false,
            show_new_folder_modal: false,
            project_info: if(open_link_preview?, do: nil, else: create_success_info(link_path)),
            project_error: nil
          )
          |> Formatting.assign_project_entries()
          |> notify_projects_sync()

        socket =
          if open_link_preview? do
            socket
            |> assign(
              current_page: :project_vault,
              selected_project_id: folder.id,
              selected_project_name: folder.name,
              vault_activity_visible: false,
              pending_link_project_path: link_path,
              pending_link_project_run_sentinel: run_sentinel?
            )
          else
            if run_sentinel? and is_binary(link_path) do
              socket
              |> assign(
                current_page: :project_vault,
                selected_project_id: folder.id,
                selected_project_name: folder.name,
                vault_activity_visible: false
              )
              |> Phoenix.LiveView.push_event("invoke_sentinel_onboard", %{
                path: link_path,
                folder_id: folder.id
              })
            else
              socket
            end
          end

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           project_error: ProjectVault.format_error(changeset),
           project_info: nil,
           show_new_folder_modal: true
         )}
    end
  end

  defp link_path_present?(path) when is_binary(path), do: String.trim(path) != ""
  defp link_path_present?(_), do: false

  defp checkbox_checked?(params, key) do
    case Map.get(params, key) do
      true -> true
      "true" -> true
      "on" -> true
      _ -> false
    end
  end

  defp new_folder_link_path(socket, _params) do
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
    "Project created and linked."
  end

  defp create_success_info(_), do: "Project created."

  def open_edit(%{"id" => id}, socket) do
    folder_id = String.to_integer(id)
    folder = ProjectVault.get_project_folder!(folder_id)

    {:noreply,
     assign(socket,
       show_edit_folder_modal: true,
       editing_folder_id: folder.id,
       edit_folder_name: folder.name,
       edit_folder_delete_confirm: false,
       project_error: nil
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
       project_error: nil
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
        {:noreply, assign(socket, project_error: "Folder name is required.")}

      is_nil(folder_id) ->
        {:noreply,
         assign(socket, project_error: "No folder selected.", show_edit_folder_modal: false)}

      true ->
        folder = ProjectVault.get_project_folder!(folder_id)

        case ProjectVault.update_project_folder(folder, %{name: name}) do
          {:ok, _} ->
            folders = ProjectVault.list_project_folders()

            {:noreply,
             socket
             |> assign(
               folders: folders,
               show_edit_folder_modal: false,
               editing_folder_id: nil,
               edit_folder_name: "",
               edit_folder_delete_confirm: false,
               project_info: "Project updated.",
               project_error: nil
             )
             |> Formatting.assign_project_entries()
             |> notify_projects_sync()}

          {:error, changeset} ->
            {:noreply,
             assign(socket,
               project_error: ProjectVault.format_error(changeset),
               project_info: nil
             )}
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
        {:noreply, assign(socket, project_error: "No folder selected.")}

      true ->
        folder = ProjectVault.get_project_folder!(folder_id)

        case ProjectVault.delete_project_folder(folder) do
          {:ok, _} ->
            folders = ProjectVault.list_project_folders()

            {:noreply,
             socket
             |> assign(
               folders: folders,
               show_edit_folder_modal: false,
               editing_folder_id: nil,
               edit_folder_name: "",
               edit_folder_delete_confirm: false,
               project_info: "Project deleted.",
               project_error: nil
             )
             |> Formatting.assign_project_entries()
             |> notify_projects_sync()}

          {:error, changeset} ->
            {:noreply,
             assign(socket,
               project_error: ProjectVault.format_error(changeset),
               project_info: nil
             )}
        end
    end
  end

  defp notify_projects_sync(socket) do
    TrustedFolderEvents.notify_projects_changed(socket)
  end
end
