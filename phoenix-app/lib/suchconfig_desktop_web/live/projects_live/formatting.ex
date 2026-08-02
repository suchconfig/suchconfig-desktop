defmodule SuchConfigDesktopWeb.ProjectsLive.Formatting do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault

  def assign_project_entries(socket) do
    vault_item_ui_enabled? = socket.assigns[:vault_item_ui_enabled?] || false
    folders = socket.assigns[:folders] || ProjectVault.list_project_folders()
    entries = project_entries(folders, vault_item_ui_enabled?)
    total_item_count = Enum.reduce(entries, 0, fn entry, acc -> acc + entry.item_count end)

    assign(socket,
      folders: folders,
      project_entries: entries,
      total_item_count: total_item_count
    )
  end

  def refresh_project_entries(socket) do
    folders = ProjectVault.list_project_folders()

    socket =
      case socket.assigns[:selected_project_id] do
        nil ->
          assign(socket, folders: folders)

        id ->
          case Enum.find(folders, &(&1.id == id)) do
            nil ->
              assign(socket,
                folders: folders,
                selected_project_id: nil,
                selected_project_name: nil
              )

            folder ->
              assign(socket, folders: folders, selected_project_name: folder.name)
          end
      end

    assign_project_entries(socket)
  end

  def project_entries(folders, vault_item_ui_enabled?) when is_list(folders) do
    Enum.map(folders, fn folder ->
      notes = ProjectVault.list_notes_by_folder(folder.id)

      vault_items =
        if vault_item_ui_enabled? do
          ProjectVault.list_vault_items_by_folder(folder.id)
        else
          []
        end

      children = project_children(notes, vault_items)
      sealed_count = Enum.count(vault_items, &(&1.kind == "archive"))

      %{
        folder: folder,
        item_count: length(notes) + length(vault_items),
        sealed_count: sealed_count,
        children: children
      }
    end)
  end

  defp project_children(notes, vault_items) do
    note_children =
      Enum.map(notes, fn note ->
        %{id: "note-#{note.id}", name: note.title, kind: "file"}
      end)

    vault_children =
      Enum.map(vault_items, fn item ->
        kind = if item.kind == "archive", do: "archive", else: "file"
        %{id: "vault-#{item.id}", name: item.title, kind: kind}
      end)

    note_children ++ vault_children
  end

  def default_expanded_projects(_folders), do: %{}
end
