defmodule SuchConfigDesktopWeb.Sc.UnlockModal do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  attr :show, :boolean, required: true
  attr :id, :string, default: "app-unlock-modal"
  attr :vault_key_id, :string, required: true
  attr :vault_unlock_error, :string, default: nil
  attr :vault_key_pending_store, :boolean, default: false
  attr :on_cancel, :string, default: "proceed_without_unlock"
  attr :on_submit, :string, default: "confirm_global_passkey"
  attr :native_passkey_reason, :string, default: "Unlock your vault to use SuchConfig."
  attr :rest, :global, include: ~w(phx-hook)

  def unlock_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class="overlay overlay--unlock"
      data-native-passkey-reason={@native_passkey_reason}
      data-vault-key-id={@vault_key_id}
      {@rest}
    >
      <button
        type="button"
        class="overlay-backdrop"
        phx-click={@on_cancel}
        aria-label="Close"
        tabindex="-1"
      />
      <div class="unlock-card" role="dialog" aria-modal="true" aria-labelledby="unlock-title">
        <div class="unlock-head">
          <div>
            <div class="unlock-eyebrow">
              <span class="pulse"></span> Vault · Sealed
            </div>
            <h2 id="unlock-title" class="unlock-title">SuchConfig</h2>
          </div>
          <button
            type="button"
            class="unlock-close"
            phx-click={@on_cancel}
            aria-label="Dismiss"
            title="Dismiss"
          >
            <.icon name="x" size={14} />
          </button>
        </div>

        <form id="app-unlock-form">
          <div class="unlock-body">
            <div class="unlock-seal" aria-hidden="true">
              <.icon name="lock" size={26} />
            </div>
            <div class="unlock-content">
              <p class="unlock-lede">
                SuchConfig is trying to unlock your vault.
                <span class="touchid touchid-macos" aria-hidden="true">
                  <.icon name="touchid" size={14} /> Touch ID
                </span>
                or enter your password to allow this.
              </p>
              <p class="unlock-meta">
                You can also use the app without unlocking to open <b>About</b>
                and <b>Settings</b>. <span class="pin">Project Vault</span>
                requires an unlocked vault. Parsing and generator tools live in the separate
                <b>SuchUtils</b>
                desktop app.
              </p>
              <div :if={@vault_unlock_error} class="vault-flash err">
                {@vault_unlock_error}
              </div>
              <div :if={@vault_key_pending_store} class="vault-flash ok">
                Saving key to Keychain…
              </div>
            </div>
          </div>
          <div class="unlock-foot">
            <button type="button" phx-click={@on_cancel} class="btn sm">
              Proceed without unlocking
            </button>
            <div class="spacer"></div>
            <div class="hint">
              <span class="kbd">↵</span> to unlock
            </div>
            <button
              id="native-global-passkey-auth-btn"
              type="button"
              disabled={@vault_key_pending_store}
              class="btn sm primary"
            >
              Unlock
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
