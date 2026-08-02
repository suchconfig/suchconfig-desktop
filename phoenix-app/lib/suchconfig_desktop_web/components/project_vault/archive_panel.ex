defmodule SuchConfigDesktopWeb.Components.ProjectVault.ArchivePanel do
  @moduledoc """
  HEEx function components for the Project Vault archive modal: export and
  import-preview entry points.
  """

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  attr :mode, :atom, required: true
  attr :archive_password, :string, default: ""
  attr :archive_export_destination_path, :string, default: nil
  attr :uploads, :map, required: true
  attr :conflict_strategy, :string, default: "duplicate"

  def archive_panel(assigns) do
    ~H"""
    <.modal_shell
      show={@mode != :hidden}
      id="archive-panel"
      on_cancel="close_archive_panel"
      size="md"
    >
      <.modal_head on_close="close_archive_panel">
        <div class="archive-panel-head">
          <div class="archive-panel-glyph">
            <.icon name="archive" size={20} />
          </div>
          <div class="archive-panel-title">
            <h3>Secure Archive</h3>
            <span class="mono faint">.suchvault · AES-256-GCM</span>
          </div>
        </div>
      </.modal_head>

      <.modal_body>
        <%= if @mode == :export do %>
          <div class="archive-callout">
            <.icon name="lock" size={16} style="color: var(--plum)" />
            <p class="muted">
              Stored only on this device until you export. Export creates a password-protected file that can be shared outside this device—handle it like production secrets.
            </p>
          </div>
          <.export_form
            archive_password={@archive_password}
            archive_export_destination_path={@archive_export_destination_path}
          />
        <% else %>
          <.import_form uploads={@uploads} conflict_strategy={@conflict_strategy} />
        <% end %>
      </.modal_body>

      <.modal_foot>
        <button
          type="button"
          phx-click="close_archive_panel"
          id="archive-panel-cancel"
          class="btn sm"
        >
          Cancel
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end

  attr :archive_password, :string, default: ""
  attr :archive_export_destination_path, :string, default: nil

  def export_form(assigns) do
    ready? = archive_export_destination_ready?(assigns.archive_export_destination_path)
    assigns = assign(assigns, :export_ready?, ready?)

    ~H"""
    <div class="archive-panel-section">
      <.modal_hint>
        You are creating a file that can be shared outside this device. Choose where to save it using your system folder picker, then enter a strong archive password.
      </.modal_hint>

      <div class="archive-panel-block">
        <div class="row" style="flex-wrap: wrap">
          <button
            type="button"
            id="archive-export-choose-folder"
            phx-hook="ArchiveExportFolderPicker"
            class="btn sm"
          >
            <.icon name="folder" size={13} /> Choose export folder…
          </button>
          <button
            :if={Application.get_env(:suchconfig_desktop, :archive_export_test_controls)}
            type="button"
            id="archive-export-test-set-dest"
            phx-click="archive_export_folder_selected"
            phx-value-path="/tmp/suchvault-export-test"
            class="sr-only"
          >
            Set test export folder
          </button>
          <button
            :if={@export_ready?}
            type="button"
            phx-click="clear_archive_export_destination"
            class="btn sm ghost"
          >
            Clear folder
          </button>
        </div>
        <p
          :if={@export_ready?}
          id="archive-export-selected-path-display"
          class="mono"
          style="font-size: 12px; margin-top: 10px; word-break: break-all"
        >
          {@archive_export_destination_path}
        </p>
        <p :if={not @export_ready?} class="muted" style="font-size: 12px; margin-top: 10px">
          Pick a folder first — Export Secure Archive stays disabled until a destination folder is chosen.
        </p>
      </div>

      <form phx-submit="export_archive" class="archive-panel-form">
        <div class="field-row plain secret">
          <input
            type="password"
            name="archive_password"
            value={@archive_password}
            placeholder="Archive password"
          />
        </div>
        <button type="submit" class="btn sm primary" disabled={not @export_ready?}>
          <.icon name="up" size={13} /> Export Secure Archive
        </button>
      </form>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :conflict_strategy, :string, default: "duplicate"

  def import_form(assigns) do
    ~H"""
    <form phx-change="set_import_options" class="archive-panel-section">
      <.modal_label>When a note title already exists in the destination folder</.modal_label>
      <div class="field-row plain">
        <select name="conflict_strategy">
          <option value="duplicate" selected={@conflict_strategy == "duplicate"}>
            Save as a copy (duplicate title)
          </option>
          <option value="replace" selected={@conflict_strategy == "replace"}>
            Overwrite existing note
          </option>
          <option value="keep_existing" selected={@conflict_strategy == "keep_existing"}>
            Keep existing, skip imported copy
          </option>
        </select>
      </div>

      <div class="row" style="flex-wrap: wrap; margin-top: 4px">
        <div class="archive-file-input">
          <.live_file_input upload={@uploads.archive_file} />
        </div>
        <button
          type="button"
          id="prepare-import-archive-btn"
          phx-click="prepare_import_archive"
          class="btn sm primary"
        >
          <.icon name="archive" size={13} /> Import Archive
        </button>
      </div>

      <.modal_hint>
        Use a .suchvault or .suchconfig export. After decrypt, choose an existing folder from the list or a new folder name, then confirm import.
      </.modal_hint>
    </form>
    """
  end

  defp archive_export_destination_ready?(path) when is_binary(path), do: String.trim(path) != ""
  defp archive_export_destination_ready?(_), do: false
end
