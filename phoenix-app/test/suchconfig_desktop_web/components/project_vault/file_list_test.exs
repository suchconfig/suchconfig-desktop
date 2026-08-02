defmodule SuchConfigDesktopWeb.Components.ProjectVault.FileListTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Components.ProjectVault.FileList

  describe "file_list/1 project settings" do
    test "renders settings trigger and archive actions" do
      html =
        render_component(&FileList.file_list/1,
          folders: [%{id: 42, name: "Main", linked_project_path: nil}],
          selected_folder_id: 42,
          vault_item_ui_enabled?: true
        )

      assert html =~ ~s(id="project-settings-button")
      assert html =~ ~s(phx-hook="TagPicker")
      assert html =~ ~s(id="open-project-settings")
      assert html =~ ~s(phx-click="open_edit_folder")
      assert html =~ "Project settings"
      assert html =~ ~s(id="note-open-archive-export")
      assert html =~ ~s(id="open-archive-import")
      assert html =~ "Export archive"
      assert html =~ "Import archive"
    end

    test "hides Project settings without selected folder" do
      html =
        render_component(&FileList.file_list/1,
          folders: [%{id: 42, name: "Main", linked_project_path: nil}],
          selected_folder_id: nil,
          vault_item_ui_enabled?: true
        )

      refute html =~ ~s(id="open-project-settings")
      refute html =~ ~s(phx-click="open_edit_folder")
    end

    test "shows Link project when folder selected and vault items enabled" do
      html =
        render_component(&FileList.file_list/1,
          folders: [%{id: 42, name: "Main", linked_project_path: nil}],
          selected_folder_id: 42,
          vault_item_ui_enabled?: true
        )

      assert html =~ ~s(id="link-project-button")
      assert html =~ "Link project"
      assert html =~ ~s(phx-click="open_link_project_modal")
    end

    test "hides Link project without selected folder" do
      html =
        render_component(&FileList.file_list/1,
          folders: [%{id: 42, name: "Main", linked_project_path: nil}],
          selected_folder_id: nil,
          vault_item_ui_enabled?: true
        )

      refute html =~ "Link project"
      refute html =~ ~s(id="link-project-button")
    end

    test "shows Update project link when folder already has linked path" do
      html =
        render_component(&FileList.file_list/1,
          folders: [
            %{id: 42, name: "Main", linked_project_path: "/Users/deeda/projects/my-app"}
          ],
          selected_folder_id: 42,
          vault_item_ui_enabled?: true
        )

      assert html =~ "Update project link"
      refute html =~ ">Link project<"
      assert html =~ ~s(phx-click="open_link_project_modal")
    end
  end
end
