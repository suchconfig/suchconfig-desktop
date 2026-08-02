defmodule SuchConfigDesktopWeb.Sc.Modal do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  attr :show, :boolean, required: true
  attr :id, :string, default: nil
  attr :on_cancel, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg xl)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def modal_shell(assigns) do
    ~H"""
    <div :if={@show} id={@id} class={["overlay", @class]} {@rest}>
      <button
        type="button"
        class="overlay-backdrop"
        phx-click={@on_cancel}
        aria-label="Close"
        tabindex="-1"
      />
      <div class={["modal", modal_size_class(@size)]} role="dialog" aria-modal="true">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :title, :string, default: nil
  attr :on_close, :string, default: nil
  slot :inner_block

  def modal_head(assigns) do
    ~H"""
    <div class="modal-head">
      <h3 :if={@title}>{@title}</h3>
      <div :if={!@title} style="flex: 1">{render_slot(@inner_block)}</div>
      <button
        :if={@on_close}
        type="button"
        class="btn ghost sm icon-only close"
        phx-click={@on_close}
        aria-label="Close"
      >
        <.icon name="x" size={14} />
      </button>
    </div>
    """
  end

  slot :inner_block, required: true

  def modal_body(assigns) do
    ~H"""
    <div class="modal-body">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def modal_foot(assigns) do
    ~H"""
    <div class={["modal-foot", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :for, :string, default: nil
  attr :rest, :global
  slot :inner_block

  def modal_label(assigns) do
    ~H"""
    <label for={@for} class="modal-label">
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :rest, :global
  slot :inner_block

  def modal_hint(assigns) do
    ~H"""
    <p class="modal-hint" {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  defp modal_size_class("sm"), do: "modal--sm"
  defp modal_size_class("lg"), do: "modal--lg"
  defp modal_size_class("xl"), do: "modal--xl"
  defp modal_size_class(_), do: nil
end
