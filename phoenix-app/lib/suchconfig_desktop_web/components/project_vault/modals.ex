defmodule SuchConfigDesktopWeb.Components.ProjectVault.Modals do
  @moduledoc """
  HEEx modal components for Project Vault: Global Passkey prompt, per-note
  save/unlock, delete confirmation, and the new two-stage import flow
  (password → preview + routing).
  """

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  import SuchConfigDesktopWeb.ProjectVaultLive.Formatting,
    only: [native_passkey_reason: 1, note_type_badge_class: 1, note_type_badge_label: 1]

  attr :show, :boolean, default: false
  attr :global_passkey_purpose, :any, default: nil
  attr :vault_key_id, :string, required: true
  attr :native_passkey_supported, :boolean, default: false
  attr :native_passkey_platform, :string, default: "unknown"

  def passkey_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="global-passkey-modal"
      on_cancel="cancel_global_passkey_modal"
      size="sm"
      class="overlay--stack"
      phx-hook="GlobalPasskeyNative"
      data-native-passkey-reason={native_passkey_reason(@global_passkey_purpose)}
      data-vault-key-id={@vault_key_id}
    >
      <.modal_head title="Unlock Global Passkey" on_close="cancel_global_passkey_modal" />
      <form phx-submit="confirm_global_passkey" class="modal-form">
        <.modal_body>
          <.modal_hint>
            Click Unlock to sign in with Touch ID or your Mac password. Your password is never sent to the app; the system verifies it.
          </.modal_hint>
          <.modal_hint>
            {if @native_passkey_supported,
              do: "Touch ID is available on this device.",
              else: "Use your system password when prompted."} ({@native_passkey_platform})
          </.modal_hint>
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="cancel_global_passkey_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Unlock
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :note_save_password, :string, default: ""

  def save_modal(assigns) do
    ~H"""
    <.modal_shell show={@show} on_cancel="cancel_save_modal" size="sm">
      <.modal_head title="Secure Note Password" on_close="cancel_save_modal" />
      <form phx-submit="confirm_save_note" class="modal-form">
        <.modal_body>
          <.modal_hint>Enter a password to encrypt this note locally before saving.</.modal_hint>
          <input
            type="password"
            name="note_save_password"
            value={@note_save_password}
            placeholder="Password"
            autofocus
          />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="cancel_save_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Save Secure Note
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :pending_unlock_note_title, :string, default: ""
  attr :unlock_password, :string, default: ""

  def unlock_modal(assigns) do
    ~H"""
    <.modal_shell show={@show} on_cancel="cancel_unlock_modal" size="sm">
      <.modal_head title="Unlock Secure Note" on_close="cancel_unlock_modal" />
      <form phx-submit="confirm_unlock_note" class="modal-form">
        <.modal_body>
          <.modal_hint>
            Enter the password for <span class="strong">{@pending_unlock_note_title}</span>.
          </.modal_hint>
          <button type="button" phx-click="unlock_note_with_global_passkey" class="modal-link">
            Unlock with Global Passkey (Touch ID or system password)
          </button>
          <input
            type="password"
            name="unlock_password"
            value={@unlock_password}
            placeholder="Password"
            autofocus
          />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="cancel_unlock_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Unlock Note
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :pending_delete_note_title, :string, default: ""
  attr :delete_modal_target, :atom, default: :note

  def delete_modal(assigns) do
    title =
      if assigns.delete_modal_target == :vault_item,
        do: "Delete Vault Item",
        else: "Delete Note"

    assigns = assign(assigns, :title, title)

    ~H"""
    <.modal_shell show={@show} on_cancel="cancel_delete_modal" size="sm">
      <.modal_head title={@title} on_close="cancel_delete_modal" />
      <.modal_body>
        <.modal_hint>
          Are you sure you want to delete <span class="strong">{@pending_delete_note_title}</span>? This action cannot be undone.
        </.modal_hint>
      </.modal_body>
      <.modal_foot>
        <button type="button" phx-click="cancel_delete_modal" class="btn sm">
          Cancel
        </button>
        <button type="button" phx-click="confirm_delete_note" class="btn sm danger">
          Delete
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :polyglot_base_name, :string, default: ""

  def polyglot_scaffold_modal(assigns) do
    ~H"""
    <.modal_shell show={@show} on_cancel="cancel_polyglot_modal" size="sm">
      <.modal_head title="Polyglot scaffold" on_close="cancel_polyglot_modal" />
      <form phx-submit="submit_polyglot_scaffold" phx-change="polyglot_form_change" class="modal-form">
        <.modal_body>
          <.modal_hint>
            Creates flat folders named <span class="strong font-mono">YourName / …</span>. Nested tree UI needs a future
            <span class="strong font-mono">parent_id</span>
            migration.
          </.modal_hint>
          <input
            type="text"
            name="polyglot_base_name"
            value={@polyglot_base_name}
            placeholder="Project name (e.g. Acme)"
            autocomplete="off"
          />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="cancel_polyglot_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Create folders
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :edit_folder_name, :string, default: ""
  attr :edit_folder_delete_confirm, :boolean, default: false

  def edit_folder_modal(assigns) do
    save_disabled = String.trim(assigns.edit_folder_name || "") == ""
    assigns = assign(assigns, :save_disabled, save_disabled)

    ~H"""
    <.modal_shell show={@show} id="edit-folder-modal" on_cancel="cancel_edit_folder" size="md">
      <.modal_head
        title={if @edit_folder_delete_confirm, do: "Delete folder?", else: "Edit folder"}
        on_close="cancel_edit_folder"
      />
      <%= if @edit_folder_delete_confirm do %>
        <.modal_body>
          <.modal_hint>
            Are you sure you want to delete this folder? This cannot be undone.
          </.modal_hint>
          <.modal_hint>All notes in this folder will be permanently removed.</.modal_hint>
        </.modal_body>
        <.modal_foot>
          <button
            type="button"
            phx-click="cancel_delete_folder_confirm"
            id="edit-folder-delete-back"
            class="btn sm"
          >
            Back
          </button>
          <button
            type="button"
            phx-click="delete_folder"
            id="edit-folder-delete-confirm"
            class="btn sm danger"
          >
            Delete folder
          </button>
        </.modal_foot>
      <% else %>
        <form
          phx-submit="save_edit_folder"
          phx-change="edit_folder_input"
          id="edit-folder-form"
          class="modal-form"
        >
          <.modal_body>
            <div class="modal-field">
              <.modal_label for="edit-folder-name-input">Project Name (required)</.modal_label>
              <input
                type="text"
                name="name"
                id="edit-folder-name-input"
                value={@edit_folder_name}
                placeholder="Folder name"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="none"
                spellcheck="false"
              />
            </div>
            <.modal_hint>
              Best practice: keep the project name the same as the linked folder name.
            </.modal_hint>
          </.modal_body>
          <.modal_foot class="modal-foot--split">
            <button
              type="button"
              phx-click="request_delete_folder"
              id="edit-folder-delete"
              class="btn sm danger"
              aria-label="Delete folder"
            >
              Delete
            </button>
            <div class="foot-actions">
              <button
                type="button"
                phx-click="cancel_edit_folder"
                id="edit-folder-cancel"
                class="btn sm"
              >
                Cancel
              </button>
              <button type="submit" disabled={@save_disabled} class="btn sm primary">
                Save
              </button>
            </div>
          </.modal_foot>
        </form>
      <% end %>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :folder_name, :string, default: ""
  attr :folder_description, :string, default: ""
  attr :folder_tags, :string, default: ""
  attr :link_stage, :atom, default: :idle
  attr :link_path, :string, default: nil
  attr :link_error, :string, default: nil
  attr :run_sentinel_scan, :boolean, default: false
  attr :pro_plan?, :boolean, default: false

  def new_folder_modal(assigns) do
    save_disabled = String.trim(assigns.folder_name || "") == ""
    link_stage = assigns.link_stage || :idle

    assigns =
      assigns
      |> assign(:save_disabled, save_disabled)
      |> assign(:show_link_dropzone, link_stage in [:idle, :select_path, :scanning, :ready])

    ~H"""
    <.modal_shell show={@show} id="new-folder-modal" on_cancel="cancel_new_folder_modal" size="lg">
      <.modal_head title="New project" on_close="cancel_new_folder_modal" />
      <form
        phx-submit="create_folder"
        phx-change="new_folder_form_change"
        id="new-folder-form"
        class="modal-form"
      >
        <.modal_body>
          <input
            type="text"
            name="folder_name"
            id="new-folder-name-input"
            value={@folder_name}
            placeholder="Name"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="none"
            spellcheck="false"
          />
          <input
            type="text"
            name="folder_description"
            value={@folder_description}
            placeholder="Description"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="none"
            spellcheck="false"
          />
          <input
            type="text"
            name="folder_tags"
            value={@folder_tags}
            placeholder="Tags (comma-separated)"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="none"
            spellcheck="false"
          />
          <div class="modal-field" style="margin-top: 8px">
            <p class="modal-hint" style="margin: 0 0 8px">
              Choose a folder on this device. We scan it locally to create Project Details and config notes in your vault.
            </p>
            <div :if={@link_error} class="vault-flash err" role="alert">
              {@link_error}
            </div>
            <div
              :if={@show_link_dropzone}
              id="new-project-link-dropzone"
              phx-hook="DropZone"
              class="link-project-dropzone"
            >
              <%= if @link_stage == :scanning do %>
                <p style="margin: 0; font-weight: 500; color: var(--ink)">Linking project…</p>
                <p :if={@link_path} class="link-project-panel-path" style="margin-top: 8px">
                  {@link_path}
                </p>
              <% else %>
                <%= if @link_stage == :ready and is_binary(@link_path) do %>
                  <p style="margin: 0; font-weight: 500; color: var(--ink)">Folder selected</p>
                  <p class="link-project-panel-path" style="margin-top: 8px">{@link_path}</p>
                  <p class="modal-hint" style="margin-top: 8px">
                    Drop another folder or click to change.
                  </p>
                <% else %>
                  <p style="margin: 0">Drop a project folder here or click to browse.</p>
                <% end %>
              <% end %>
            </div>
          </div>
          <div :if={@pro_plan?} class="modal-field" style="margin-top: 12px">
            <label
              for="new-folder-run-sentinel"
              style="display: flex; align-items: flex-start; gap: 8px; cursor: pointer"
            >
              <input
                type="checkbox"
                name="run_sentinel_scan"
                id="new-folder-run-sentinel"
                value="true"
                checked={@run_sentinel_scan}
                style="margin-top: 2px"
              />
              <span>
                <span style="font-weight: 500; color: var(--ink)">Run Security Sentinel Scan</span>
                <span class="modal-hint" style="display: block; margin-top: 4px">
                  You can always run the scan anytime from the Project Details view.
                </span>
              </span>
            </label>
          </div>
        </.modal_body>
        <.modal_foot>
          <button
            type="button"
            phx-click="cancel_new_folder_modal"
            id="new-folder-cancel"
            class="btn sm"
          >
            Cancel
          </button>
          <button type="submit" disabled={@save_disabled} class="btn sm primary">
            Create project
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :stage, :atom, default: :idle
  attr :archive_password, :string, default: ""

  def import_password_modal(assigns) do
    ~H"""
    <.modal_shell show={@stage == :password} on_cancel="cancel_import_modal" size="sm">
      <.modal_head title="Decrypt Archive" on_close="cancel_import_modal" />
      <form phx-submit="preview_archive" class="modal-form">
        <.modal_body>
          <.modal_hint>
            Enter the archive password. We'll decrypt it in memory and show you a preview before any folders are created.
          </.modal_hint>
          <input
            type="password"
            name="archive_password"
            value={@archive_password}
            placeholder="Archive password"
            autofocus
          />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="cancel_import_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Preview Archive
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :stage, :atom, default: :idle
  attr :preview, :any, default: nil
  attr :routing, :map, default: %{}
  attr :folders, :list, default: []
  attr :conflict_strategy, :string, default: "duplicate"

  def import_preview_modal(assigns) do
    ~H"""
    <.modal_shell show={@stage == :preview and @preview} on_cancel="cancel_import_modal" size="lg">
      <.modal_head>
        <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; width: 100%">
          <div style="flex: 1; min-width: 0">
            <h3 style="display: flex; align-items: center; gap: 8px; margin: 0">
              <.icon name="archive" size={18} /> Import Preview
            </h3>
            <p class="modal-hint" style="margin-top: 4px">
              Decide how each archive folder should land in your vault.
            </p>
          </div>
          <button
            type="button"
            class="btn ghost sm icon-only close"
            phx-click="cancel_import_modal"
            aria-label="Close"
          >
            <.icon name="x" size={14} />
          </button>
        </div>
      </.modal_head>
      <form phx-submit="confirm_import_archive" class="modal-form">
        <.modal_body>
          <div class="import-preview-meta">
            <p>Format: <span>{@preview.format} v{@preview.format_version}</span></p>
            <p>
              {@preview.folder_count} folder{if @preview.folder_count == 1, do: "", else: "s"} · {@preview.note_count} note{if @preview.note_count ==
                                                                                                                                 1,
                                                                                                                               do:
                                                                                                                                 "",
                                                                                                                               else:
                                                                                                                                 "s"}
            </p>
            <p :if={@preview.created_at}>Created: {@preview.created_at}</p>
          </div>

          <div class="modal-field">
            <.preview_folder_row
              :for={folder <- @preview.folders}
              folder={folder}
              routing={@routing}
              vault_folders={@folders}
            />
          </div>

          <div class="modal-field">
            <.modal_label>When a note title already exists in the destination folder</.modal_label>
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
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="cancel_import_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Import
          </button>
        </.modal_foot>
      </form>
    </.modal_shell>
    """
  end

  attr :folder, :map, required: true
  attr :routing, :map, default: %{}
  attr :vault_folders, :list, default: []

  defp preview_folder_row(assigns) do
    assigns =
      assign(assigns, :decision, Map.get(assigns.routing, assigns.folder.index, :create_new))

    assigns = assign(assigns, :decision_value, decision_to_value(assigns.decision))

    assigns =
      assign(assigns, :new_folder_name, new_folder_name_value(assigns.decision, assigns.folder))

    ~H"""
    <div class="import-preview-row">
      <div
        class="row"
        style="flex-wrap: wrap; align-items: flex-start; justify-content: space-between; gap: 12px"
      >
        <div style="min-width: 0; flex: 1">
          <p class="import-preview-row-title">{@folder.name}</p>
          <p :if={@folder.description} class="import-preview-row-desc">{@folder.description}</p>
          <div class="row" style="margin-top: 6px; flex-wrap: wrap; gap: 4px">
            <span style="font-size: 10px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--ink-3)">
              {@folder.note_count} note{if @folder.note_count == 1, do: "", else: "s"}:
            </span>
            <span :for={{type, count} <- @folder.note_types} class={note_type_badge_class(type)}>
              {count} {note_type_badge_label(type)}
            </span>
          </div>
        </div>
        <div style="flex-shrink: 0; min-width: min(100%, 280px); display: flex; flex-direction: column; gap: 10px">
          <div class="modal-field">
            <.modal_label>Destination</.modal_label>
            <select
              name="decision"
              phx-change="set_import_routing"
              phx-value-index={@folder.index}
            >
              <option value="create_new" selected={@decision_value == "create_new"}>
                New project folder (name below)
              </option>
              <option
                :for={vault_folder <- @vault_folders}
                value={"merge:#{vault_folder.id}"}
                selected={@decision_value == "merge:#{vault_folder.id}"}
              >
                Add to existing: {vault_folder.name}
              </option>
              <option value="skip" selected={@decision_value == "skip"}>
                Skip
              </option>
            </select>
          </div>
          <div :if={show_new_folder_name_input?(@decision)} class="modal-field">
            <.modal_label>New folder name</.modal_label>
            <input
              type="text"
              name="name"
              value={@new_folder_name}
              phx-change="set_import_routing_name"
              phx-value-index={@folder.index}
              phx-debounce="300"
              autocomplete="off"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp show_new_folder_name_input?(:create_new), do: true
  defp show_new_folder_name_input?({:create_new, _}), do: true
  defp show_new_folder_name_input?(_), do: false

  defp new_folder_name_value({:create_new, name}, folder) when is_binary(name) do
    if String.trim(name) != "", do: name, else: Map.get(folder, :name, "")
  end

  defp new_folder_name_value(_, folder), do: Map.get(folder, :name, "")

  defp decision_to_value(:create_new), do: "create_new"
  defp decision_to_value({:create_new, _name}), do: "create_new"
  defp decision_to_value(:skip), do: "skip"
  defp decision_to_value({:merge_into, id}), do: "merge:#{id}"
  defp decision_to_value(_), do: "create_new"
end
