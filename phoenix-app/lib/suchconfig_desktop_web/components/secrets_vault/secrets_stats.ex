defmodule SuchConfigDesktopWeb.Components.SecretsVault.SecretsStats do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill

  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting

  attr :vault_stats, :map, required: true
  attr :folder_name, :string, default: "Vault"

  def secrets_stats(assigns) do
    assigns =
      assigns
      |> assign(
        :merge_conflicts_label,
        Formatting.merge_conflicts_label(
          assigns.vault_stats.merge_conflicts,
          assigns.vault_stats.crdt_enabled?
        )
      )
      |> assign(
        :merge_conflicts_color,
        Formatting.merge_conflicts_color(
          assigns.vault_stats.merge_conflicts,
          assigns.vault_stats.crdt_enabled?
        )
      )
      |> assign(
        :devices_label,
        if(assigns.vault_stats.crdt_enabled?, do: "3 · synced", else: "local")
      )
      |> assign(:backup_label, Formatting.backup_label(assigns.vault_stats.last_backup_at))
      |> assign(
        :sync_status_label,
        Formatting.sync_status_label(
          assigns.vault_stats.last_sync_at,
          assigns.vault_stats.trusted_folder_path
        )
      )

    ~H"""
    <div class="detail" id="secrets-vault-stats">
      <div class="detail-head">
        <div class="icon-lg" data-t="login">
          <.icon name="vault" size={22} />
        </div>
        <div style="min-width: 0; flex: 1">
          <h2>Vault overview</h2>
          <div class="subline">
            <.pill tone="ok">local-first</.pill>
            <span>
              <.icon name="vault" size={12} style="vertical-align: -2px; margin-right: 4px" />
              {@folder_name}
            </span>
            <span>·</span>
            <span>
              <b>{@vault_stats.total}</b> entries across <b>{@vault_stats.folder_count}</b> folders
            </span>
          </div>
        </div>
      </div>

      <div class="meta-strip">
        <div class="meta-cell">
          <div class="k">Logins</div>
          <div class="v" style="color: var(--accent)">{@vault_stats.login_count}</div>
        </div>
        <div class="meta-cell">
          <div class="k">API keys</div>
          <div class="v" style="color: var(--moss)">{@vault_stats.api_count}</div>
        </div>
        <div class="meta-cell">
          <div class="k">SSH keys</div>
          <div class="v" style="color: var(--plum)">{@vault_stats.ssh_count}</div>
        </div>
        <div class="meta-cell">
          <div class="k">Notes</div>
          <div class="v">{@vault_stats.note_count}</div>
        </div>
      </div>

      <div class="meta-strip">
        <div class="meta-cell">
          <div class="k">Total entries</div>
          <div class="v">{@vault_stats.total}</div>
        </div>
        <div class="meta-cell">
          <div class="k">Folders</div>
          <div class="v">{@vault_stats.folder_count}</div>
        </div>
        <div class="meta-cell">
          <div class="k">Merge conflicts</div>
          <div class="v" style={"color: #{@merge_conflicts_color}"}>{@merge_conflicts_label}</div>
        </div>
        <div class="meta-cell">
          <div class="k">Devices</div>
          <div class="v">{@devices_label}</div>
        </div>
      </div>

      <div class="detail-body">
        <div :if={@vault_stats.merge_conflicts > 0} class="stats-alert">
          <.icon name="info" size={16} />
          <div>
            <strong>{@vault_stats.merge_conflicts} merge conflicts need review</strong>
            <p class="muted">Resolve conflicting edits before syncing to other devices.</p>
          </div>
        </div>

        <div class="stats-info-grid">
          <div class="stats-info-card">
            <div class="stats-info-k">Last vault backup</div>
            <div class="stats-info-v">{@backup_label}</div>
            <p class="stats-info-hint muted">Encrypted archive copy to a trusted folder.</p>
          </div>
          <div class="stats-info-card">
            <div class="stats-info-k">Vault synced to</div>
            <div class="stats-info-v mono">{@sync_status_label}</div>
            <p class="stats-info-hint muted">Trusted folder path and last sync time.</p>
          </div>
        </div>

        <div class="stats-empty-hint">
          <p class="muted">
            Select an entry from the list to view or edit it, or use
            <span class="mono">New entry</span>
            to add credentials.
          </p>
        </div>
      </div>
    </div>
    """
  end
end
