defmodule SuchConfigDesktopWeb.Sc.RailTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import SuchConfigDesktopWeb.Sc.Rail

  describe "rail/1" do
    test "renders primary navigation buttons with inline icons" do
      assigns = %{current_page: :home, secrets_vault_enabled: true}

      html =
        rendered_to_string(~H"""
        <.rail current_page={@current_page} secrets_vault_enabled={@secrets_vault_enabled} />
        """)

      assert html =~ ~s(id="rail-home-btn")
      assert html =~ ~s(id="rail-secrets-btn")
      assert html =~ ~s(id="rail-projects-btn")
      assert html =~ ~s(id="rail-generator-btn")
      assert html =~ ~s(id="rail-settings-btn")
      assert html =~ ~s(id="rail-docs-btn")
      assert html =~ ~s(id="rail-about-btn")
      assert html =~ "Projects"
      assert html =~ ~s(class="rail-mark ctx-dark")
      assert html =~ ~s(viewBox="0 0 100 100")
      refute html =~ ">S<"
    end

    test "projects button is active on projects page" do
      assigns = %{current_page: :projects, secrets_vault_enabled: true}

      html =
        rendered_to_string(~H"""
        <.rail current_page={@current_page} secrets_vault_enabled={@secrets_vault_enabled} />
        """)

      assert html =~ ~s(id="rail-projects-btn")
      assert html =~ "rail-btn active"
      assert html =~ "M20 20a2 2 0 0 0 2-2V8"
    end

    test "hides secrets vault button when disabled" do
      assigns = %{current_page: :home, secrets_vault_enabled: false}

      html =
        rendered_to_string(~H"""
        <.rail current_page={@current_page} secrets_vault_enabled={@secrets_vault_enabled} />
        """)

      refute html =~ ~s(id="rail-secrets-btn")
      assert html =~ ~s(id="rail-projects-btn")
    end
  end
end
