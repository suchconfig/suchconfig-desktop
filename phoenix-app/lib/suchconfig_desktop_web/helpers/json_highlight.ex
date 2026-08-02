defmodule SuchConfigDesktopWeb.Helpers.JsonHighlight do
  @moduledoc false

  def highlight(source) when is_binary(source) do
    lexer = Module.concat(["Elixir", "MakeupJson"])

    if Code.ensure_loaded?(lexer) do
      source
      |> Makeup.highlight_inner_html(
        lexer: lexer,
        formatter_options: [css_class: "json-highlight"]
      )
      |> then(&{:safe, &1})
    else
      Phoenix.HTML.html_escape(source)
    end
  end

  def highlight(nil), do: {:safe, ""}
  def highlight(""), do: {:safe, ""}

  def stylesheet do
    Makeup.stylesheet(:default_style, "json-highlight")
  end
end
