defmodule SuchConfigDesktopWeb.Sc.Rail do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.DividersMark
  import SuchConfigDesktopWeb.Sc.Icon

  attr :current_page, :atom, required: true
  attr :secrets_vault_enabled, :boolean, default: true
  attr :id, :string, default: "app-rail"

  def rail(assigns) do
    ~H"""
    <aside class="rail" id={@id}>
      <div class="rail-mark ctx-dark" aria-label="SuchConfig">
        <.dividers_mark variant="full" class="rail-mark-glyph" />
      </div>
      <button
        id="rail-command-btn"
        type="button"
        class="rail-btn"
        phx-click="open_command_palette"
        phx-throttle="300"
        title="Command palette"
      >
        <.icon name="search" size={17} />
        <span class="rail-tip">⌘K · search</span>
      </button>
      <div style="height: 10px" />
      <button
        id="rail-home-btn"
        type="button"
        class={["rail-btn", @current_page == :home && "active"]}
        phx-click="navigate"
        phx-value-page="home"
        phx-throttle="300"
      >
        <.icon name="home" size={17} />
        <span class="rail-tip">Dashboard</span>
      </button>
      <button
        :if={@secrets_vault_enabled}
        id="rail-secrets-btn"
        type="button"
        class={["rail-btn", @current_page == :secrets_vault && "active"]}
        phx-click="navigate"
        phx-value-page="secrets_vault"
        phx-throttle="300"
      >
        <.icon name="key" size={17} />
        <span class="rail-tip">Secrets Vault</span>
      </button>
      <button
        id="rail-projects-btn"
        type="button"
        class={["rail-btn", @current_page == :projects && "active"]}
        phx-click="navigate"
        phx-value-page="projects"
        phx-throttle="300"
      >
        <.icon name="folder" size={17} />
        <span class="rail-tip">Projects</span>
      </button>
      <button
        id="rail-generator-btn"
        type="button"
        class="rail-btn"
        phx-click="open_generator_drawer"
        phx-throttle="300"
        title="Password generator"
      >
        <.icon name="wand" size={17} />
        <span class="rail-tip">Generator</span>
      </button>
      <div style="flex: 1" />
      <button
        id="rail-docs-btn"
        type="button"
        class={["rail-btn", @current_page == :docs && "active"]}
        phx-click="navigate"
        phx-value-page="docs"
        phx-throttle="300"
      >
        <.icon name="book-open" size={17} />
        <span class="rail-tip">Docs</span>
      </button>
      <button
        id="rail-settings-btn"
        type="button"
        class={["rail-btn", @current_page == :settings && "active"]}
        phx-click="navigate"
        phx-value-page="settings"
        phx-throttle="300"
      >
        <.icon name="gear" size={17} />
        <span class="rail-tip">Settings</span>
      </button>
      <button
        id="rail-about-btn"
        type="button"
        class={["rail-btn", @current_page == :about && "active"]}
        phx-click="navigate"
        phx-value-page="about"
        phx-throttle="300"
      >
        <.icon name="info" size={17} />
        <span class="rail-tip">About</span>
      </button>
    </aside>
    """
  end
end
