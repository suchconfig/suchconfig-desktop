defmodule SuchConfigDesktopWeb.Sc.CommandPalette do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  alias SuchConfigDesktopWeb.Sc.CommandPalette.Commands

  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :cursor, :integer, default: 0
  attr :secrets_vault_enabled, :boolean, default: true
  attr :id, :string, default: "command-palette"

  def command_palette(assigns) do
    groups = Commands.groups(assigns.secrets_vault_enabled)
    filtered = Commands.filter(groups, assigns.query)
    flat = Commands.flat_items(filtered)
    cursor = min(max(assigns.cursor, 0), max(length(flat) - 1, 0))

    assigns =
      assigns
      |> assign(:filtered_groups, filtered)
      |> assign(:flat_items, flat)
      |> assign(:cursor, cursor)

    ~H"""
    <div :if={@open} id={@id} class="palette-overlay" phx-hook="CommandPalette">
      <button
        type="button"
        class="palette-overlay-backdrop"
        phx-click="close_command_palette"
        aria-label="Close"
        tabindex="-1"
      />
      <div class="palette" role="dialog" aria-modal="true" aria-label="Command palette">
        <div class="palette-search">
          <.icon name="sparkle" size={16} style="color: var(--accent)" />
          <input
            id="command-palette-input"
            type="text"
            name="q"
            value={@query}
            placeholder="what would you like to do?"
            phx-change="command_palette_query"
            phx-debounce="80"
            autocomplete="off"
            spellcheck="false"
          />
          <span class="kbd">esc</span>
        </div>
        <div class="palette-list" id="command-palette-list">
          <%= if @filtered_groups == [] do %>
            <div class="palette-empty">no results — try a different verb</div>
          <% else %>
            <%= for {group, group_idx} <- Enum.with_index(@filtered_groups) do %>
              <div class="palette-group">{group.group}</div>
              <%= for {item, item_idx} <- Enum.with_index(group.items) do %>
                <% flat_idx = flat_index(@filtered_groups, group_idx, item_idx) %>
                <button
                  type="button"
                  id={"command-palette-item-#{item.id}"}
                  class={["palette-item", flat_idx == @cursor && "cursor"]}
                  phx-click="command_palette_action"
                  phx-value-id={item.id}
                  phx-mouseenter="command_palette_hover"
                  phx-value-index={flat_idx}
                >
                  <span class="palette-item-icon">
                    <.icon name={item.icon} size={15} />
                  </span>
                  <span>{item.label}</span>
                  <span :if={item.hint != ""} class="hint mono">{item.hint}</span>
                </button>
              <% end %>
            <% end %>
          <% end %>
        </div>
        <div class="palette-foot">
          <span><span class="kbd">↑↓</span> navigate</span>
          <span><span class="kbd">↵</span> run</span>
          <span><span class="kbd">esc</span> close</span>
          <span class="faint" style="margin-left: auto">⌘K from anywhere</span>
        </div>
      </div>
    </div>
    """
  end

  defp flat_index(groups, group_idx, item_idx) do
    groups
    |> Enum.take(group_idx)
    |> Enum.reduce(0, fn g, acc -> acc + length(g.items) end)
    |> Kernel.+(item_idx)
  end
end
