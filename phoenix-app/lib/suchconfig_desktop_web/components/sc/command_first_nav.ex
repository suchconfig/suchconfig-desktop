defmodule SuchConfigDesktopWeb.Sc.CommandFirstNav do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill

  attr :current_page, :atom, required: true
  attr :vault_unlocked, :boolean, default: false
  attr :secrets_vault_enabled, :boolean, default: true
  attr :id, :string, default: "command-first-nav"

  def command_first_nav(assigns) do
    ~H"""
    <header class="command-first-nav" id={@id}>
      <div class="brand" style="padding: 0">
        <div class="brand-mark" style="width: 24px; height: 24px; font-size: 15px">S</div>
        <div class="brand-name" style="font-size: 16px">
          such<b>config</b>
        </div>
      </div>
      <button
        type="button"
        id="command-first-nav-trigger"
        class="command-first-trigger"
        phx-click="open_command_palette"
        phx-throttle="300"
      >
        <.icon name="sparkle" size={16} style="color: var(--accent)" />
        <span class="command-first-trigger-label">What would you like to do?</span>
        <span class="kbd">⌘K</span>
      </button>
      <div class="row" style="gap: 6px">
        <button
          :if={@secrets_vault_enabled}
          type="button"
          class={["btn", "sm", "ghost", @current_page == :secrets_vault && "is-active"]}
          phx-click="navigate"
          phx-value-page="secrets_vault"
          phx-throttle="300"
        >
          Secrets
        </button>
        <button
          type="button"
          class={["btn", "sm", "ghost", @current_page == :project_vault && "is-active"]}
          phx-click="navigate"
          phx-value-page="project_vault"
          phx-throttle="300"
        >
          Projects
        </button>
        <button
          :if={@secrets_vault_enabled}
          type="button"
          class="btn sm ghost"
          phx-click="command_palette_action"
          phx-value-id="nav.gen"
          phx-throttle="300"
        >
          Generator
        </button>
        <button
          type="button"
          class={["btn", "sm", "icon-only", "ghost", @current_page == :settings && "is-active"]}
          phx-click="navigate"
          phx-value-page="settings"
          phx-throttle="300"
          aria-label="Settings"
        >
          <.icon name="gear" size={14} />
        </button>
        <button
          type="button"
          class={["btn", "sm", "icon-only", "ghost", @current_page == :about && "is-active"]}
          phx-click="navigate"
          phx-value-page="about"
          phx-throttle="300"
          aria-label="About"
        >
          <.icon name="info" size={14} />
        </button>
        <.pill tone={if(@vault_unlocked, do: "ok", else: "locked")}>
          {if @vault_unlocked, do: "unlocked", else: "locked"}
        </.pill>
      </div>
    </header>
    """
  end
end
