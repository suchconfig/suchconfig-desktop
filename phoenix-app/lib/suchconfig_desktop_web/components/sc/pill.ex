defmodule SuchConfigDesktopWeb.Sc.Pill do
  use Phoenix.Component

  attr :tone, :string, default: "ok", values: ~w(ok warn locked)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def pill(assigns) do
    ~H"""
    <span class={["pill", @tone, @class]}>
      <span class="dot" />
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :active, :boolean, default: false
  attr :color, :string, default: nil
  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={["tag", @active && "active"]}>
      <span :if={@color} class="dot" style={"background: #{@color}"} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  slot :inner_block, required: true

  def kbd(assigns) do
    ~H"""
    <span class="kbd">{render_slot(@inner_block)}</span>
    """
  end
end
