defmodule SuchConfigDesktopWeb.Components.SecretsVault.FolderToolbar do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  attr :folders, :list, required: true
  attr :selected_folder_id, :any, default: nil

  def folder_toolbar(assigns) do
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
    </div>
    """
  end
end
