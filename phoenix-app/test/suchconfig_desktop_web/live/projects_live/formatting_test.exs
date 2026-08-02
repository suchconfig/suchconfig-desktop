defmodule SuchConfigDesktopWeb.ProjectsLive.FormattingTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.ProjectVault

  @live_opts [on_error: :warn]

  test "refresh_project_entries clears selection when selected folder is gone", %{conn: conn} do
    folder = project_folder_fixture(%{name: "Stale Selection Project"})
    conn = get(conn, ~p"/")
    {:ok, view, _html} = live(conn, "/", @live_opts)
    view |> element("button", "Proceed without unlocking") |> render_click()
    view |> element("#rail-projects-btn") |> render_click()
    view |> element("#project-card-#{folder.id}") |> render_click()

    assert has_element?(view, "#crumb-projects-btn")

    assert {:ok, _} = ProjectVault.delete_project_folder(folder)

    send(view.pid, :refresh_project_entries)
    html = render(view)

    refute html =~ "Stale Selection Project"
    refute has_element?(view, "#project-card-#{folder.id}")
  end
end
