defmodule SuchConfigDesktopWeb.LayoutsTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  alias SuchConfigDesktopWeb.Layouts

  describe "app/1" do
    test "renders inner block content in main area" do
      assigns = %{flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.app flash={@flash}>
          Inner content
        </Layouts.app>
        """)

      assert html =~ "Inner content"
    end

    test "main_class px-0 removes horizontal padding from main" do
      assigns = %{flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.app flash={@flash} main_class="px-0">
          Inner
        </Layouts.app>
        """)

      assert html =~ ~r/<main[^>]*class="[^"]*\bpx-0\b/
      refute html =~ ~r/<main[^>]*class="[^"]*lg:px-8/
    end
  end

  describe "flash_group/1" do
    test "renders fixed bottom-right toast container" do
      assigns = %{flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      assert html =~ ~r/class="[^"]*sc-toast-group/
    end

    test "renders info flash with toast styling" do
      assigns = %{flash: %{"info" => "Trusted Folder backup synced."}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      assert html =~ "Trusted Folder backup synced."
      assert html =~ "sc-toast sc-toast--info"
      assert html =~ "sc-toast-body"
      assert html =~ ~r/id="flash-info"[^>]*phx-hook="ToastAutoDismiss"/
      assert html =~ ~r/id="flash-info"[^>]*data-autoclose-ms="10000"/
    end

    test "renders error flash with toast styling" do
      assigns = %{flash: %{"error" => "trusted folder error: failed to write archive"}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      assert html =~ "trusted folder error"
      assert html =~ "sc-toast--error"
      assert html =~ ~r/id="flash-error"[^>]*phx-hook="ToastAutoDismiss"/
    end

    test "reconnect toasts do not auto-dismiss" do
      assigns = %{flash: %{}}

      html =
        rendered_to_string(~H"""
        <Layouts.flash_group flash={@flash} />
        """)

      refute html =~ ~r/id="client-error"[^>]*phx-hook="ToastAutoDismiss"/
      refute html =~ ~r/id="server-error"[^>]*phx-hook="ToastAutoDismiss"/
    end
  end
end
