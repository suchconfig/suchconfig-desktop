defmodule SuchConfigDesktopWeb.ProjectsLiveTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SuchConfigDesktop.EnvManagerFixtures

  @live_opts [on_error: :warn]

  defp projects_view(conn) do
    conn = get(conn, ~p"/")
    {:ok, view, _html} = live(conn, "/", @live_opts)
    view |> element("button", "Proceed without unlocking") |> render_click()
    view |> element("#rail-projects-btn") |> render_click()
    view
  end

  describe "embedded via AppLive" do
    test "shows projects page", %{conn: conn} do
      view = projects_view(conn)
      assert render(view) =~ "projects-page-root"
      assert render(view) =~ "New project"
    end

    test "open_new_folder_modal shows new project modal", %{conn: conn} do
      view = projects_view(conn)

      view
      |> element("#new-project-button")
      |> render_click()

      assert has_element?(view, "#new-folder-modal")
      assert has_element?(view, "#new-folder-form")
      assert has_element?(view, "#new-project-link-dropzone")
      assert render(view) =~ "New project"
      assert render(view) =~ "Choose a folder on this device"
    end

    test "new project modal shows sentinel checkbox only for Pro", %{conn: conn} do
      previous = Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:suchconfig_desktop, :security_sentinel_license_enabled)
        else
          Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, previous)
        end
      end)

      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, false)
      free_view = projects_view(conn)
      free_view |> element("#new-project-button") |> render_click()
      refute has_element?(free_view, "#new-folder-run-sentinel")

      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, true)
      pro_view = projects_view(conn)
      pro_view |> element("#new-project-button") |> render_click()
      assert has_element?(pro_view, "#new-folder-run-sentinel")
      assert render(pro_view) =~ "Run Security Sentinel Scan"

      assert render(pro_view) =~
               "You can always run the scan anytime from the Project Details view"
    end

    test "open_edit_folder from project settings shows edit folder modal", %{conn: conn} do
      folder = project_folder_fixture()

      conn = get(conn, ~p"/")
      session_id = get_session(conn, "vault_session_id")
      {:ok, view, _html} = live(conn, "/", @live_opts)
      view |> element("button", "Proceed without unlocking") |> render_click()
      SuchConfigDesktop.VaultSessionRegistry.put(session_id, "test-unlock-pw")

      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{session_id}",
        :vault_unlocked
      )

      view |> element("#rail-projects-btn") |> render_click()
      view |> element("#project-card-#{folder.id}") |> render_click()

      vault = find_live_child(view, "project_vault-#{folder.id}-false")
      assert vault

      vault
      |> element("#open-project-settings")
      |> render_click()

      assert has_element?(vault, "#edit-folder-modal")
      assert has_element?(vault, "#edit-folder-form")
      assert render(vault) =~ "Edit folder"
    end

    test "open project navigates to project vault with breadcrumb", %{conn: conn} do
      folder = project_folder_fixture()
      view = projects_view(conn)

      view
      |> element("#project-card-#{folder.id}")
      |> render_click()

      html = render(view)
      assert html =~ "project-vault-root"
      assert html =~ folder.name
      assert has_element?(view, "#crumb-projects-btn", "Projects")
    end

    test "projects crumb navigates back to projects view", %{conn: conn} do
      folder = project_folder_fixture()
      view = projects_view(conn)

      view
      |> element("#project-card-#{folder.id}")
      |> render_click()

      assert has_element?(view, "#crumb-projects-btn")

      view
      |> element("#crumb-projects-btn")
      |> render_click()

      assert has_element?(view, "#projects-page-root")
      refute has_element?(view, "#crumb-projects-btn")
    end
  end
end
