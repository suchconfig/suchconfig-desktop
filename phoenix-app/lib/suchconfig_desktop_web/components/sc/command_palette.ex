defmodule SuchConfigDesktopWeb.Sc.CommandPalette do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  alias SuchConfigDesktopWeb.Sc.CommandPalette.Commands

  attr :open, :boolean, default: false
  attr :cursor, :integer, default: 0
  attr :secrets_vault_enabled, :boolean, default: true
  attr :id, :string, default: "command-palette"

  def command_palette(assigns) do
    groups = Commands.groups(assigns.secrets_vault_enabled)
    flat = Commands.flat_items(groups)
    cursor = min(max(assigns.cursor, 0), max(length(flat) - 1, 0))

    assigns =
      assigns
      |> assign(:groups, groups)
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
      <div
        class="palette"
        id="command-palette-dialog"
        role="dialog"
        aria-modal="true"
        aria-label="Command palette"
        tabindex="0"
      >
        <div class="palette-head">
          <.icon name="sparkle" size={16} style="color: var(--accent)" />
          <span class="palette-head-title">Commands</span>
          <span class="kbd">esc</span>
        </div>
        <div class="palette-list" id="command-palette-list" role="listbox">
          <%= for {group, group_idx} <- Enum.with_index(@groups) do %>
            <div class="palette-group">{group.group}</div>
            <%= for {item, item_idx} <- Enum.with_index(group.items) do %>
              <% flat_idx = flat_index(@groups, group_idx, item_idx) %>
              <button
                type="button"
                id={"command-palette-item-#{item.id}"}
                role="option"
                aria-selected={flat_idx == @cursor}
                class={["palette-item", flat_idx == @cursor && "is-selected"]}
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
