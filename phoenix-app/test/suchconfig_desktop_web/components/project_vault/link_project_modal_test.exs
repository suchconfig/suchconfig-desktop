defmodule SuchConfigDesktopWeb.Components.ProjectVault.LinkProjectModalTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Components.ProjectVault.LinkProjectModal

  describe "link_project_modal/1" do
    test "renders AI tooling panel with scaffold toggles" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :preview,
          scan_path: "/tmp/my-app",
          project_name: "my-app",
          vault_candidates: [],
          vault_selected: %{},
          ai_tooling: %{
            folder_tags: ["Cursor"],
            found: ["AGENTS.md"],
            recommendations: [
              %{
                path: ".cursorignore",
                tool: "Cursor",
                reason: "Cursor project is missing .cursorignore",
                default_selected: true
              }
            ]
          },
          scaffold_selected: %{".cursorignore" => true},
          existing_notes_strategy: nil,
          folder_has_items: false,
          error: nil
        )

      assert html =~ ~s(id="link-project-ai-tooling-panel")
      assert html =~ "AI tooling"
      assert html =~ "Cursor"
      assert html =~ "AGENTS.md"
      assert html =~ "Recommended create"
      assert html =~ ~s(id="link-project-scaffold-0")
      assert html =~ ~s(phx-click="link_project_scaffold_toggle")
      assert html =~ ".cursorignore"
    end

    test "renders dropzone in select_path stage" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :select_path,
          scan_path: nil,
          project_name: nil,
          vault_candidates: [],
          vault_selected: %{},
          error: nil
        )

      assert html =~ "Link Project"
      assert html =~ ~s(id="vault-link-project-dropzone")
      assert html =~ ~s(phx-hook="DropZone")
      refute html =~ "Setup guide"
      refute html =~ "AI context"
    end

    test "renders preview, candidates, and confirm in preview stage" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :preview,
          scan_path: "/tmp/my-app",
          project_name: "my-app",
          vault_candidates: [
            %{
              relative_path: ".env",
              gitignored: true,
              note_type: "environment_files"
            }
          ],
          vault_selected: %{".env" => true},
          existing_notes_strategy: nil,
          folder_has_items: true,
          error: nil
        )

      assert html =~ "Linked folder"
      assert html =~ "/tmp/my-app"
      refute html =~ "Project Details preview"
      assert html =~ "Config files to import"
      assert html =~ ".env"
      assert html =~ ~s(id="link-project-existing-notes-form")
      assert html =~ ~s(id="link-project-existing-notes")
      assert html =~ "Overwrite existing vault items"
      assert html =~ "Create duplicate vault items"
      assert html =~ ~s(phx-change="link_project_existing_notes_change")
      assert html =~ ~s(phx-click="cancel_link_project_modal")
      assert html =~ ~s(id="link-project-confirm-button")
      assert html =~ ~s(phx-click="confirm_link_project")
      assert html =~ "Confirm"
      assert html =~ "Cancel"
    end

    test "hides existing notes form when folder has no items" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :preview,
          scan_path: "/tmp/my-app",
          project_name: "my-app",
          vault_candidates: [],
          vault_selected: %{},
          existing_notes_strategy: nil,
          folder_has_items: false,
          error: nil
        )

      refute html =~ ~s(id="link-project-existing-notes-form")
      refute html =~ ~s(id="link-project-existing-notes")
      assert html =~ ~s(id="link-project-confirm-button")
    end

    test "confirm button stays clickable before strategy is selected" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :preview,
          scan_path: "/tmp/my-app",
          project_name: "my-app",
          vault_candidates: [],
          vault_selected: %{},
          existing_notes_strategy: nil,
          error: nil
        )

      assert html =~ ~s(id="link-project-confirm-button")
      assert html =~ ~s(phx-click="confirm_link_project")
      refute html =~ ~s(id="link-project-confirm-button-disabled")
    end

    test "confirm button renders when existing notes strategy is selected" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :preview,
          scan_path: "/tmp/my-app",
          project_name: "my-app",
          vault_candidates: [],
          vault_selected: %{},
          existing_notes_strategy: "duplicate",
          folder_has_items: true,
          error: nil
        )

      assert html =~ ~s(id="link-project-confirm-button")
      assert html =~ ~s(phx-click="confirm_link_project")
      refute html =~ ~s(id="link-project-confirm-button-disabled")
    end

    test "shows modal error banner" do
      html =
        render_component(&LinkProjectModal.link_project_modal/1,
          show: true,
          stage: :select_path,
          error: "Folder selection requires the desktop app",
          scan_path: nil,
          project_name: nil,
          vault_candidates: [],
          vault_selected: %{}
        )

      assert html =~ "Folder selection requires the desktop app"
    end
  end
end
