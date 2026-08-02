defmodule SuchConfigDesktopWeb.Sc.IconTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Sc.Icon

  describe "icon/1" do
    test "renders inline svg for a direct lucide name" do
      html = render_icon("pencil", 11)

      assert html =~ ~s(<svg)
      assert html =~ ~s(width="11")
      assert html =~ ~s(height="11")
      assert html =~ "M21.174 6.812"
    end

    test "resolves short aliases to lucide svg paths" do
      html = render_icon("home", 17)

      assert html =~ "M15 21v-8"
      refute html =~ "lucide-house"
    end

    test "maps vault alias to folder-kanban" do
      html = render_icon("vault", 14)

      assert html =~ "M16 10v6"
      assert html =~ "M8 10v4"
    end

    test "maps touchid alias to fingerprint paths" do
      html = render_icon("touchid", 14)

      assert html =~ "M2 12a10"
    end

    test "falls back to info icon for unknown names" do
      html = render_icon("not-a-real-icon", 16)

      assert html =~ ~s(<svg)
      assert html =~ "M12 16v-4"
    end
  end

  defp render_icon(name, size) do
    render_component(&Icon.icon/1, name: name, size: size)
  end
end
