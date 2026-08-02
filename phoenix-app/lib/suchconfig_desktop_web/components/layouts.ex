defmodule SuchConfigDesktopWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SuchConfigDesktopWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_page, :atom, default: :home, doc: "the current page for navigation highlighting"
  attr :navigation_items, :list, default: [], doc: "list of navigation items"

  attr :vault_unlocked, :boolean,
    default: false,
    doc: "whether the global passkey vault is unlocked"

  attr :main_class, :string,
    default: "px-4 sm:px-6 lg:px-8",
    doc:
      "horizontal padding for main; use px-0 for full-bleed shells (e.g. sidebar flush to viewport)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="sc-app flex-1 flex flex-col min-h-0">
      <main class={["flex-1 min-h-0 flex flex-col", @main_class]}>
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="sc-toast-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Lost connection to the local app")}
        autoclose={false}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting to SuchConfig…")}
        <.icon name="lucide-loader-circle" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        autoclose={false}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting to SuchConfig…")}
        <.icon name="lucide-loader-circle" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <button
      type="button"
      class="relative p-2 rounded-lg text-gray-500 hover:text-gray-700 hover:bg-gray-100 dark:text-slate-400 dark:hover:text-slate-200 dark:hover:bg-slate-700 transition-colors duration-200"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="dark"
      title="Switch to dark mode"
      aria-label="Switch to dark mode"
      id="theme-toggle-light"
    >
      <.icon name="lucide-moon" class="size-5" />
    </button>
    <button
      type="button"
      class="relative p-2 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-700 dark:text-slate-400 dark:hover:text-slate-200 dark:hover:bg-slate-700 transition-colors duration-200 hidden"
      phx-click={JS.dispatch("phx:set-theme")}
      data-phx-theme="light"
      title="Switch to light mode"
      aria-label="Switch to light mode"
      id="theme-toggle-dark"
    >
      <.icon name="lucide-sun" class="size-5" />
    </button>
    """
  end
end
