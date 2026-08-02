defmodule SuchConfigDesktopWeb.Sc.Topbar do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill
  import SuchConfigDesktopWeb.Sc.TrustedFolderBadge

  alias Phoenix.LiveView.JS

  attr :current_page, :atom, required: true
  attr :vault_unlocked, :boolean, default: false
  attr :project_name, :string, default: nil
  attr :trusted_folder_display_path, :string, default: nil
  attr :trusted_folder_synced, :boolean, default: false
  attr :trusted_folder_watcher_running, :boolean, default: false
  attr :id, :string, default: "app-topbar"

  def topbar(assigns) do
    ~H"""
    <div class="topbar" id={@id}>
      <div class="crumbs">
        <.icon name="compass" size={13} style="color: var(--ink-3)" />
        <%= if @current_page == :project_vault and is_binary(@project_name) and @project_name != "" do %>
          <button
            id="crumb-projects-btn"
            type="button"
            class="crumb-link"
            phx-click="navigate"
            phx-value-page="projects"
            phx-throttle="300"
          >
            Projects
          </button>
          <span class="sep">›</span>
          <b>{@project_name}</b>
        <% else %>
          <span>SuchConfig</span>
          <span class="sep">›</span>
          <b>{page_label(@current_page)}</b>
        <% end %>
      </div>
      <div id="topbar-command-btn" class="topbar-search">
        <.icon name="search" size={13} />
        <input
          id="topbar-command-input"
          type="text"
          placeholder="Commands…"
          readonly
          phx-click="open_command_palette"
          phx-focus="open_command_palette"
          phx-throttle="300"
        />
        <span class="kbd">⌘K</span>
      </div>
      <div class="topbar-right">
        <.trusted_folder_badge
          id="trusted-folder-status-badge"
          display_path={@trusted_folder_display_path}
          synced={@trusted_folder_synced}
          watcher_running={@trusted_folder_watcher_running}
        />
        <.pill :if={!@vault_unlocked} tone="locked">Vault locked</.pill>
        <button
          :if={@vault_unlocked}
          id="topbar-lock-vault-btn"
          type="button"
          class="btn sm"
          phx-click="lock_global_passkey_from_settings"
          phx-throttle="300"
          title="Lock vault"
        >
          <.icon name="unlock" size={13} style="color: var(--moss)" />
          <span>Vault unlocked</span>
        </button>
        <button
          :if={!@vault_unlocked}
          id="topbar-unlock-vault-btn"
          type="button"
          class="btn sm"
          phx-click="request_unlock"
          phx-throttle="300"
          title="Unlock vault"
        >
          <.icon name="lock" size={13} style="color: var(--ink-2)" />
          <span>Unlock</span>
        </button>
        <div id="topbar-theme-toggle" phx-hook="ThemeToggle">
          <button
            type="button"
            class="btn sm icon-only"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="dark"
            title="Switch to dark mode"
            aria-label="Switch to dark mode"
            id="theme-toggle-light"
          >
            <.icon name="moon" size={13} />
          </button>
          <button
            type="button"
            class="btn sm icon-only hidden"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="light"
            title="Switch to light mode"
            aria-label="Switch to light mode"
            id="theme-toggle-dark"
          >
            <.icon name="sun" size={13} />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp page_label(:home), do: "Dashboard"
  defp page_label(:projects), do: "Projects"
  defp page_label(:project_vault), do: "Project Vault"
  defp page_label(:secrets_vault), do: "Secrets Vault"
  defp page_label(:settings), do: "Settings"
  defp page_label(:docs), do: "Docs"
  defp page_label(:about), do: "About"
  defp page_label(_), do: "Home"
end
