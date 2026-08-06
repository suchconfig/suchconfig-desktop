defmodule SuchConfigDesktopWeb.Components.SecretsVault.FolderToolbar do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  alias SuchConfigDesktop.SecretsVault.Folder

  attr :folders, :list, required: true
  attr :selected_folder_id, :any, default: nil

  def folder_toolbar(assigns) do
    selected_folder =
      Enum.find(assigns.folders, fn folder -> folder.id == assigns.selected_folder_id end)

    assigns =
      assigns
      |> assign(:selected_folder, selected_folder)
      |> assign(
        :folder_actions_enabled?,
        is_integer(assigns.selected_folder_id) and selected_folder != nil
      )
      |> assign(
        :system_folder?,
        selected_folder != nil and Folder.system_folder?(selected_folder)
      )

    ~H"""
    <div class="list-toolbar-folders" id="secrets-folder-toolbar">
      <.form
        for={%{}}
        phx-change="folder_toolbar_change"
        id="secrets-folder-toolbar-form"
        class="list-toolbar-folder-form"
      >
        <select
          name="folder_id"
          id="secrets-folder-select"
          class="list-toolbar-folder-select"
          aria-label="Folder"
        >
          <option value="all" selected={@selected_folder_id == :all}>
            Show all
          </option>
          <option
            :for={folder <- @folders}
            value={folder.id}
            selected={folder.id == @selected_folder_id}
          >
            {folder.name}
          </option>
        </select>
      </.form>
      <button
        type="button"
        phx-click="open_new_folder_modal"
        id="new-secrets-folder-toolbar-button"
        class="btn xs icon-only"
        title="New folder"
        aria-label="New folder"
      >
        <.icon name="folder-plus" size={14} />
      </button>
      <div
        :if={@folder_actions_enabled?}
        id="secrets-folder-settings-picker"
        class="tag-picker"
        phx-hook="TagPicker"
      >
        <button
          type="button"
          data-tag-picker-trigger
          id="secrets-folder-settings-button"
          class="btn xs icon-only"
          title="Folder settings"
          aria-label="Folder settings"
          aria-haspopup="menu"
          aria-expanded="false"
        >
          <.icon name="settings-2" size={14} />
        </button>
        <div data-tag-picker-menu class="tag-picker-menu" role="menu">
          <ul class="tag-picker-list">
            <li>
              <button
                type="button"
                role="menuitem"
                phx-click="open_rename_folder"
                phx-value-id={@selected_folder_id}
                id="secrets-folder-rename"
                class="tag-picker-option"
                disabled={@system_folder?}
                title={
                  if(@system_folder?,
                    do: "System folders cannot be renamed",
                    else: "Rename folder"
                  )
                }
              >
                <.icon name="pencil" size={12} />
                <span>Rename folder</span>
              </button>
            </li>
            <li>
              <button
                type="button"
                role="menuitem"
                phx-click="open_delete_folder_modal"
                phx-value-id={@selected_folder_id}
                id="secrets-folder-delete"
                class="tag-picker-option"
                disabled={@system_folder?}
                title={
                  if(@system_folder?,
                    do: "System folders cannot be deleted",
                    else: "Delete folder"
                  )
                }
              >
                <.icon name="trash-2" size={12} />
                <span>Delete folder</span>
              </button>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
