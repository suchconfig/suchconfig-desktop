defmodule SuchConfigDesktopWeb.Sc.EntryRow do
  @moduledoc false
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  attr :type, :string, default: "note"
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :meta, :string, default: nil
  attr :active, :boolean, default: false
  attr :rest, :global

  def entry_row(assigns) do
    ~H"""
    <div class={["entry", @active && "active"]} {@rest}>
      <.type_glyph type={@type} />
      <div>
        <div class="entry-title">{@title}</div>
        <div :if={@subtitle} class="entry-sub">{@subtitle}</div>
      </div>
      <div :if={@meta} class="entry-meta">{@meta}</div>
    </div>
    """
  end

  attr :type, :string, default: "note"
  attr :size, :integer, default: 32

  def type_glyph(assigns) do
    icon_name =
      case assigns.type do
        "login" -> "user"
        "api" -> "code"
        "ssh" -> "ssh"
        "note" -> "note"
        _ -> "diamond"
      end

    assigns = assign(assigns, :icon_name, icon_name)

    ~H"""
    <span class="entry-glyph" data-t={@type} style={"width: #{@size}px; height: #{@size}px"}>
      <.icon name={@icon_name} size={round(@size * 0.55)} />
    </span>
    """
  end
end
