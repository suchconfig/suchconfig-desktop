defmodule SuchConfigDesktopWeb.Sc.DividersMark do
  @moduledoc false

  use Phoenix.Component

  attr :variant, :string, default: "full", values: ~w(full micro disc)
  attr :class, :string, default: nil
  attr :id, :string, default: nil

  def dividers_mark(%{variant: "disc"} = assigns) do
    ~H"""
    <svg
      id={@id}
      class={["dm", @class]}
      viewBox="0 0 100 100"
      aria-hidden="true"
    >
      <circle class="disc" cx="50" cy="50" r="47" />
      <line
        class="cut-stroke"
        x1="50"
        y1="35"
        x2="32"
        y2="73"
        stroke-width="7.5"
        stroke-linecap="round"
      />
      <line
        class="cut-stroke"
        x1="50"
        y1="35"
        x2="68"
        y2="73"
        stroke-width="7.5"
        stroke-linecap="round"
      />
      <circle class="cut-fill" cx="50" cy="31" r="7.6" />
      <circle class="cut-fill" cx="32" cy="74" r="3" />
      <circle class="cut-fill" cx="68" cy="74" r="3" />
    </svg>
    """
  end

  def dividers_mark(%{variant: "micro"} = assigns) do
    ~H"""
    <svg
      id={@id}
      class={["dm", @class]}
      viewBox="0 0 100 100"
      aria-hidden="true"
    >
      <line class="leg" x1="50" y1="29" x2="31" y2="80" stroke-width="9" stroke-linecap="round" />
      <line class="leg-a" x1="50" y1="29" x2="69" y2="80" stroke-width="9" stroke-linecap="round" />
      <circle class="pivot" cx="50" cy="27" r="9" />
    </svg>
    """
  end

  def dividers_mark(assigns) do
    ~H"""
    <svg
      id={@id}
      class={["dm", @class]}
      viewBox="0 0 100 100"
      aria-hidden="true"
    >
      <path
        class="arc"
        d="M30 86 Q50 74 70 86"
        stroke-width="2.2"
        fill="none"
        opacity="0.4"
        stroke-dasharray="3 4"
      />
      <line class="leg" x1="50" y1="30" x2="30" y2="84" stroke-width="8" stroke-linecap="round" />
      <line class="leg-a" x1="50" y1="30" x2="70" y2="84" stroke-width="8" stroke-linecap="round" />
      <circle class="pivot" cx="50" cy="26" r="8" />
      <circle class="foot" cx="30" cy="84" r="3.4" />
      <circle class="foot-a" cx="70" cy="84" r="3.4" />
    </svg>
    """
  end
end
