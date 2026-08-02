defmodule SuchConfigDesktopWeb.Components.ProjectVault.ProjectsGridTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Components.ProjectVault.ProjectsGrid

  describe "projects_grid/1" do
    test "renders clickable project card without open/edit controls" do
      folder = %{id: 42, name: "My Project"}

      entry = %{
        folder: folder,
        item_count: 2,
        sealed_count: 0,
        children: [%{id: "note-1", name: "README", kind: "file"}]
      }

      html =
        render_component(&ProjectsGrid.projects_grid/1,
          project_entries: [entry],
          expanded_projects: %{42 => true},
          vault_activity_visible: false,
          total_item_count: 2,
          vault_unlocked: true
        )

      assert html =~ "xl:grid-cols-4"
      assert html =~ "w-full"
      assert html =~ ~s(id="project-card-42")
      assert html =~ ~s(phx-click="open_project")
      assert html =~ ~s(phx-value-id="42")
      refute html =~ ~s(id="project-open-42")
      refute html =~ ~s(id="project-edit-42")
      refute html =~ ~s(id="project-card-lock-42")
      assert html =~ "README"
    end

    test "shows lock icon on project cards when vault is locked" do
      folder = %{id: 7, name: "Locked Project"}

      entry = %{
        folder: folder,
        item_count: 0,
        sealed_count: 0,
        children: []
      }

      html =
        render_component(&ProjectsGrid.projects_grid/1,
          project_entries: [entry],
          expanded_projects: %{},
          vault_activity_visible: false,
          total_item_count: 0,
          vault_unlocked: false
        )

      assert html =~ ~s(id="project-card-7")
      assert html =~ "is-locked"
      assert html =~ ~s(id="project-card-lock-7")
      assert html =~ "Vault locked"
    end

    test "marks activity toolbar button active when visible" do
      html =
        render_component(&ProjectsGrid.projects_grid/1,
          project_entries: [],
          expanded_projects: %{},
          vault_activity_visible: true,
          total_item_count: 0,
          vault_unlocked: true
        )

      assert html =~ ~s(id="projects-activity-button")
      assert html =~ "btn sm primary"
    end
  end
end
