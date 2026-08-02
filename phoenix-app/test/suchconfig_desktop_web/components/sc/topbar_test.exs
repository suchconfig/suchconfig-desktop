defmodule SuchConfigDesktopWeb.Sc.TopbarTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import SuchConfigDesktopWeb.Sc.Topbar

  describe "topbar/1 vault state" do
    test "renders Vault unlocked when vault_unlocked is true" do
      assigns = %{current_page: :home, vault_unlocked: true, project_name: nil}

      html =
        rendered_to_string(~H"""
        <.topbar
          current_page={@current_page}
          vault_unlocked={@vault_unlocked}
          project_name={@project_name}
        />
        """)

      assert html =~ "Vault unlocked"
      assert html =~ "lock_global_passkey_from_settings"
      assert html =~ "topbar-lock-vault-btn"
      refute html =~ "Vault locked"
      refute html =~ "topbar-unlock-vault-btn"
    end

    test "renders Vault locked when vault_unlocked is false" do
      assigns = %{current_page: :home, vault_unlocked: false, project_name: nil}

      html =
        rendered_to_string(~H"""
        <.topbar
          current_page={@current_page}
          vault_unlocked={@vault_unlocked}
          project_name={@project_name}
        />
        """)

      assert html =~ "Vault locked"
      assert html =~ "Unlock"
      assert html =~ "request_unlock"
      assert html =~ "topbar-unlock-vault-btn"
      refute html =~ "Vault unlocked"
      refute html =~ "topbar-lock-vault-btn"
    end

    test "renders project breadcrumb on project vault page" do
      assigns = %{
        current_page: :project_vault,
        vault_unlocked: true,
        project_name: "Platform"
      }

      html =
        rendered_to_string(~H"""
        <.topbar
          current_page={@current_page}
          vault_unlocked={@vault_unlocked}
          project_name={@project_name}
        />
        """)

      assert html =~ "crumb-projects-btn"
      assert html =~ "Projects"
      assert html =~ "Platform"
      assert html =~ ~s(phx-value-page="projects")
      refute html =~ "SuchConfig"
      refute html =~ "Project Vault"
    end
  end
end
