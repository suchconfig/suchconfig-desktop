defmodule SuchConfigDesktopWeb.Sc.Field do
  @moduledoc false
  use Phoenix.Component

  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :mono, :boolean, default: false
  attr :read_only, :boolean, default: true
  attr :copyable, :boolean, default: true
  attr :placeholder, :string, default: nil

  def text_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-label"><span>{@label}</span></div>
      <div class={["field-row", !@mono && "plain"]}>
        <input
          type="text"
          readonly={@read_only}
          value={@value}
          placeholder={@placeholder}
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: ""

  def secret_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-label"><span>{@label}</span></div>
      <div class="field-row secret masked">
        <input type="password" readonly value={@value} />
      </div>
    </div>
    """
  end
end
