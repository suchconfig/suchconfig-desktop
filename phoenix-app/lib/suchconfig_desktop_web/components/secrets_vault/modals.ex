defmodule SuchConfigDesktopWeb.Components.SecretsVault.Modals do
  @moduledoc false

  use SuchConfigDesktopWeb, :html

  attr :show, :boolean, default: false

  def new_folder_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="new-secrets-folder-modal"
      on_cancel="close_new_folder_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head title="New folder" on_close="close_new_folder_modal" />
      <.form for={%{}} phx-submit="create_folder" id="new-secrets-folder-form" class="modal-form">
        <.modal_body>
          <input type="text" name="folder[name]" placeholder="Folder name" autocomplete="off" autocorrect="off" autocapitalize="none" spellcheck="false" required />
          <input type="text" name="folder[description]" placeholder="Description (optional)" />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="close_new_folder_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Create
          </button>
        </.modal_foot>
      </.form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :edit_folder_name, :string, default: ""
  attr :edit_folder_description, :string, default: ""

  def edit_folder_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="edit-secrets-folder-modal"
      on_cancel="close_edit_folder_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head title="Rename folder" on_close="close_edit_folder_modal" />
      <.form for={%{}} phx-submit="update_folder" id="edit-secrets-folder-form" class="modal-form">
        <.modal_body>
          <input
            type="text"
            name="folder[name]"
            value={@edit_folder_name}
            placeholder="Folder name"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="none"
            spellcheck="false"
            required
            autofocus
          />
          <input
            type="text"
            name="folder[description]"
            value={@edit_folder_description}
            placeholder="Description (optional)"
          />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="close_edit_folder_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Save
          </button>
        </.modal_foot>
      </.form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :delete_folder_name, :string, default: ""
  attr :delete_folder_items_action, :atom, default: :move_to_deleted_items
  attr :delete_folder_busy, :boolean, default: false

  def delete_folder_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="delete-secrets-folder-modal"
      on_cancel="close_delete_folder_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head
        title="Confirm delete"
        on_close={if(@delete_folder_busy, do: nil, else: "close_delete_folder_modal")}
      />
      <.modal_body>
        <.modal_hint>
          Are you sure you want to delete <span class="strong">{@delete_folder_name}</span>?
        </.modal_hint>
        <.modal_hint>
          Secret items in this folder can either be permanently deleted, or stored in a
          <span class="strong">Deleted Items</span>
          folder so you can re-assign them to other folders later.
        </.modal_hint>
        <div style="margin-top: 12px; display: flex; flex-direction: column; gap: 10px">
          <label
            for="delete-folder-move-items"
            style="display: flex; align-items: flex-start; gap: 8px; cursor: pointer"
          >
            <input
              type="checkbox"
              id="delete-folder-move-items"
              name="delete_folder_items_action"
              value="move_to_deleted_items"
              checked={@delete_folder_items_action == :move_to_deleted_items}
              phx-click="set_delete_folder_items_action"
              phx-value-action="move_to_deleted_items"
              disabled={@delete_folder_busy}
              style="margin-top: 2px"
            />
            <span>
              <span style="font-weight: 500; color: var(--ink)">Store in Deleted Items</span>
              <span class="modal-hint" style="display: block; margin-top: 4px">
                Keep secrets so you can re-assign them to other folders.
              </span>
            </span>
          </label>
          <label
            for="delete-folder-permanent-items"
            style="display: flex; align-items: flex-start; gap: 8px; cursor: pointer"
          >
            <input
              type="checkbox"
              id="delete-folder-permanent-items"
              name="delete_folder_items_action"
              value="permanent_delete"
              checked={@delete_folder_items_action == :permanent_delete}
              phx-click="set_delete_folder_items_action"
              phx-value-action="permanent_delete"
              disabled={@delete_folder_busy}
              style="margin-top: 2px"
            />
            <span>
              <span style="font-weight: 500; color: var(--ink)">Permanently delete secret items</span>
              <span class="modal-hint" style="display: block; margin-top: 4px">
                Remove every secret in this folder. This cannot be undone.
              </span>
            </span>
          </label>
        </div>
        <p
          :if={@delete_folder_busy}
          id="delete-secrets-folder-status"
          class="modal-hint"
          style="margin-top: 12px"
        >
          Deleting folder…
        </p>
      </.modal_body>
      <.modal_foot>
        <button
          type="button"
          phx-click="close_delete_folder_modal"
          id="delete-secrets-folder-cancel"
          class={["btn sm", @delete_folder_busy && "is-disabled"]}
          disabled={@delete_folder_busy}
        >
          Cancel
        </button>
        <button
          type="button"
          phx-click="delete_folder"
          id="delete-secrets-folder-confirm"
          class={["btn sm danger", @delete_folder_busy && "is-disabled"]}
          disabled={@delete_folder_busy}
          phx-disable-with="Deleting folder…"
        >
          Confirm delete
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false

  def delete_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="delete-secret-modal"
      on_cancel="close_delete_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head title="Delete entry?" on_close="close_delete_modal" />
      <.modal_body>
        <.modal_hint>This cannot be undone.</.modal_hint>
      </.modal_body>
      <.modal_foot>
        <button type="button" phx-click="close_delete_modal" class="btn sm">
          Cancel
        </button>
        <button type="button" phx-click="confirm_delete" class="btn sm danger">
          Delete
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :stage, :atom, default: :idle
  attr :preview, :any, default: nil
  attr :result, :any, default: nil
  attr :duplicate_strategy, :atom, default: :keep_as_new
  attr :error, :string, default: nil
  attr :uploads, :any, required: true

  def manager_import_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="secrets-manager-import-modal"
      on_cancel="close_manager_import"
      size="lg"
      class="overlay--stack"
    >
      <.modal_head title="Import from password manager" on_close="close_manager_import" />
      <%= case @stage do %>
        <% :source -> %>
          <.modal_body>
            <.modal_hint>
              Import stays on this device. Start with a Bitwarden unencrypted JSON export.
            </.modal_hint>
            <div class="row" style="flex-wrap: wrap; gap: 8px; margin-top: 12px">
              <button
                type="button"
                id="manager-import-source-bitwarden"
                phx-click="manager_import_choose_source"
                phx-value-source="bitwarden"
                class="btn sm primary"
              >
                Bitwarden
              </button>
              <button type="button" class="btn sm" disabled title="Coming soon">1Password</button>
              <button type="button" class="btn sm" disabled title="Coming soon">LastPass</button>
              <button type="button" class="btn sm" disabled title="Coming soon">KeePass</button>
            </div>
            <.modal_hint>
              Bitwarden: Tools → Export vault → File format JSON → Export (unencrypted).
            </.modal_hint>
          </.modal_body>
          <.modal_foot>
            <button type="button" phx-click="close_manager_import" class="btn sm">Cancel</button>
          </.modal_foot>
        <% :file -> %>
          <.modal_body>
            <.modal_hint>Select your Bitwarden unencrypted .json export file.</.modal_hint>
            <form
              id="manager-import-upload-form"
              phx-change="manager_import_validate"
              phx-submit="manager_import_prepare_preview"
            >
              <div class="archive-file-input" id="manager-import-file-input">
                <.live_file_input upload={@uploads.manager_import_file} />
              </div>
              <div
                :for={entry <- @uploads.manager_import_file.entries}
                id={"manager-import-entry-#{entry.ref}"}
                class="muted"
                style="margin-top: 8px"
              >
                {entry.client_name}
                <span :if={entry.done?}> · ready</span>
                <span :if={not entry.done?}> · uploading   {entry.progress}%</span>
                <span :for={err <- upload_errors(@uploads.manager_import_file, entry)} class="err">
                  · {err}
                </span>
              </div>
            </form>
            <p :if={@error} id="manager-import-error" class="vault-flash err" style="margin-top: 12px">
              {@error}
            </p>
          </.modal_body>
          <.modal_foot>
            <button type="button" phx-click="manager_import_back_source" class="btn sm">
              Back
            </button>
            <button
              type="button"
              id="manager-import-preview-button"
              phx-click="manager_import_prepare_preview"
              class="btn sm primary"
            >
              Preview
            </button>
          </.modal_foot>
        <% :preview -> %>
          <.modal_body>
            <p :if={@error} id="manager-import-error" class="vault-flash err">{@error}</p>
            <.modal_hint>
              Ready to import <span class="strong">{@preview.item_count}</span>
              items into <span class="strong">{@preview.folder_count}</span>
              folders.
            </.modal_hint>
            <div
              :if={@preview.duplicate_count > 0}
              id="manager-import-duplicates"
              style="margin-top: 12px; padding: 12px; border: 1px solid var(--border, #ccc); border-radius: 8px"
            >
              <.modal_hint>
                <span class="strong">{@preview.duplicate_count}</span>
                possible duplicate(s) found (same folder, title, and type). Choose how to handle them:
              </.modal_hint>
              <div style="margin-top: 10px; display: flex; flex-direction: column; gap: 8px">
                <label class="row" style="align-items: flex-start; gap: 8px; cursor: pointer">
                  <input
                    type="radio"
                    name="duplicate_strategy"
                    id="manager-import-strategy-keep"
                    value="keep_as_new"
                    checked={@duplicate_strategy != :overwrite}
                    phx-click="manager_import_set_duplicate_strategy"
                    phx-value-strategy="keep_as_new"
                  />
                  <span>
                    <span class="strong">Keep as new items</span>
                    <span class="muted">
                      (default) — rename with “ (duplicate)” and do not merge.
                    </span>
                  </span>
                </label>
                <label class="row" style="align-items: flex-start; gap: 8px; cursor: pointer">
                  <input
                    type="radio"
                    name="duplicate_strategy"
                    id="manager-import-strategy-overwrite"
                    value="overwrite"
                    checked={@duplicate_strategy == :overwrite}
                    phx-click="manager_import_set_duplicate_strategy"
                    phx-value-strategy="overwrite"
                  />
                  <span>
                    <span class="strong">Overwrite duplicates</span>
                    <span class="muted">
                      — update existing Secrets Vault entries (CRDT replace).
                    </span>
                  </span>
                </label>
              </div>
              <ul class="muted mono" style="margin-top: 8px; max-height: 100px; overflow: auto">
                <li :for={dup <- @preview.duplicates}>
                  {dup.import_title} → existing “{dup.existing_title}”
                </li>
              </ul>
            </div>
            <ul :if={@preview.warnings != []} class="muted" style="margin-top: 8px">
              <li :for={w <- Enum.take(@preview.warnings, 5)}>{w}</li>
            </ul>
            <div class="mono" style="margin-top: 12px; max-height: 220px; overflow: auto">
              <div :for={item <- @preview.sample_items} style="padding: 4px 0">
                {item.title} · {item.kind}{if item.folder_name, do: " · #{item.folder_name}", else: ""}
              </div>
              <div :if={@preview.item_count > length(@preview.sample_items)} class="muted">
                …and {@preview.item_count - length(@preview.sample_items)} more
              </div>
            </div>
          </.modal_body>
          <.modal_foot>
            <button type="button" phx-click="manager_import_back_source" class="btn sm">
              Back
            </button>
            <button
              type="button"
              id="manager-import-confirm-button"
              phx-click="manager_import_confirm"
              class="btn sm primary"
            >
              Import all ({@preview.item_count})
            </button>
          </.modal_foot>
        <% :done -> %>
          <.modal_body>
            <.modal_hint>
              Imported <span class="strong">{@result.imported}</span>
              secrets <span :if={@result.created > 0}> ·   {@result.created} created</span>
              <span :if={@result.overwritten > 0}> ·   {@result.overwritten} overwritten</span>
              <span :if={@result.skipped > 0}> · {@result.skipped} skipped</span>.
            </.modal_hint>
          </.modal_body>
          <.modal_foot>
            <button
              type="button"
              id="manager-import-done-button"
              phx-click="close_manager_import"
              class="btn sm primary"
            >
              Done
            </button>
          </.modal_foot>
        <% _ -> %>
          <.modal_body>
            <.modal_hint>Closing…</.modal_hint>
          </.modal_body>
      <% end %>
    </.modal_shell>
    """
  end
end
