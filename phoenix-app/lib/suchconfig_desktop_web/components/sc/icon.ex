defmodule SuchConfigDesktopWeb.Sc.Icon do
  @moduledoc false

  use Phoenix.Component

  @lucide_dir Path.expand("../../../../deps/lucide/icons", __DIR__)

  @aliases %{
    "home" => "house",
    "gear" => "settings",
    "touchid" => "fingerprint",
    "ssh" => "terminal",
    "note" => "sticky-note",
    "more" => "ellipsis",
    "chev-r" => "chevron-right",
    "chev-d" => "chevron-down",
    "chev-l" => "chevron-left",
    "up" => "arrow-up-to-line",
    "unlock" => "lock-open",
    "refresh" => "refresh-cw",
    "vault" => "folder-kanban",
    "sparkle" => "sparkles",
    "wand" => "wand-sparkles",
    "stats" => "chart-column"
  }

  @extra_icons ~w(
    key search plus x lock eye eye-off copy user code moon sun compass diamond
    clock tag history folder folder-open file archive check minus pencil info
    fingerprint sparkles folder-kanban wand-sparkles chart-column filter folder-plus
    book-open settings-2 columns-2 shield
  )

  @icon_files @aliases |> Map.values() |> Enum.concat(@extra_icons) |> Enum.uniq()

  @svg_paths (for name <- @icon_files, into: %{} do
                path = Path.join(@lucide_dir, "#{name}.svg")

                inner =
                  if File.exists?(path) do
                    path
                    |> File.read!()
                    |> String.replace(~r/^[\s\S]*?<svg[^>]*>/, "")
                    |> String.trim_trailing()
                    |> String.replace(~r/<\/svg>\s*$/, "")
                    |> String.replace("stroke-width=\"2\"", "stroke-width=\"1.5\"")
                  else
                    ~s(<circle cx="12" cy="12" r="9"/>)
                  end

                {name, inner}
              end)

  attr :name, :string, required: true
  attr :size, :integer, default: 16
  attr :class, :string, default: nil
  attr :style, :string, default: nil

  def icon(assigns) do
    lucide_name =
      assigns.name
      |> String.replace_prefix("lucide-", "")
      |> then(&Map.get(@aliases, &1, &1))

    svg_inner = Map.get(@svg_paths, lucide_name, Map.get(@svg_paths, "info"))

    assigns =
      assigns
      |> assign(:svg_inner, svg_inner)

    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      style={icon_style(@style)}
      aria-hidden="true"
    >
      {Phoenix.HTML.raw(@svg_inner)}
    </svg>
    """
  end

  defp icon_style(nil), do: "flex-shrink: 0"
  defp icon_style(style), do: "flex-shrink: 0; #{style}"
end
