defmodule SuchConfigDesktopWeb.Sc.TrustedFolderModal do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  attr :show, :boolean, required: true
  attr :busy, :boolean, default: false
  attr :error, :string, default: nil
  attr :changing, :boolean, default: false

  def trusted_folder_modal(assigns) do
    ~H"""
    <.modal_shell
      :if={@show}
      id="trusted-folder-onboarding-modal"
      show={@show}
      on_cancel="dismiss_trusted_folder_modal"
      size="md"
    >
      <.modal_head
        title={if @changing, do: "Change Trusted Folder", else: "Trusted Folder Sync"}
        on_close="dismiss_trusted_folder_modal"
      />
      <.modal_body>
        <div class="archive-callout" style="margin-bottom: 16px">
          <.icon name="lock" size={16} style="color: var(--plum)" />
          <p class="muted" style="margin: 0">
            Your Vault stays on this device. SuchConfig never hosts your data — you pick a folder you
            already trust (Dropbox, iCloud Drive, Google Drive, a NAS, or any local path) and we keep
            encrypted CRDT backups in sync automatically.
          </p>
        </div>
        <p :if={!@changing} class="muted">
          Select your <span class="strong">Trusted Folder</span>
          once. Every save exports encrypted vault snapshots; when backup files change on disk, the app imports them and mirrors that snapshot locally (including removals).
        </p>
        <p :if={@changing} class="muted">
          Choose a new folder for encrypted backups. The app will watch
          <span class="mono">.suchconfig</span>
          under that path. Your previous backup folder is not deleted — it simply stops receiving updates.
        </p>
        <div :if={@error} class="vault-flash err" style="margin-top: 12px">
          {@error}
        </div>
      </.modal_body>
      <.modal_foot>
        <button
          type="button"
          phx-click="dismiss_trusted_folder_modal"
          class="btn sm"
          disabled={@busy}
        >
          Cancel
        </button>
        <button
          type="button"
          id="trusted-folder-setup-btn"
          phx-click="begin_trusted_folder_setup"
          class="btn sm primary"
          disabled={@busy}
        >
          {if @busy,
            do: "Opening picker…",
            else: if(@changing, do: "Choose new folder", else: "Choose Trusted Folder")}
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end
end
