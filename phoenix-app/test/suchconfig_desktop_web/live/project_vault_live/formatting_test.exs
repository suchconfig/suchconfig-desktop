defmodule SuchConfigDesktopWeb.ProjectVaultLive.FormattingTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  describe "project_details_vault_item?/2" do
    test "matches guideline project details vault items" do
      assert Formatting.project_details_vault_item?("Project Details", "guideline")
      assert Formatting.project_details_vault_item?(" Project Details ", "guideline")
      assert Formatting.project_details_vault_item?("Project Details (import)", "guideline")
      assert Formatting.project_details_vault_item?("Project Details (2)", "guideline")
    end

    test "rejects non-project-details titles and non-guideline kinds" do
      refute Formatting.project_details_vault_item?("Project Notes", "guideline")
      refute Formatting.project_details_vault_item?("Project Details", "generic_note")
      refute Formatting.project_details_vault_item?("Project Details", "prompt_template")
      refute Formatting.project_details_vault_item?(nil, "guideline")
      refute Formatting.project_details_vault_item?("Project Details", nil)
    end
  end

  describe "env_display_mode?/2" do
    test "includes legacy environment_files and vault env_note kinds" do
      assert Formatting.env_display_mode?("environment_files")
      assert Formatting.env_display_mode?("env_note")
      refute Formatting.env_display_mode?("generic_note")
      refute Formatting.env_display_mode?("guideline")
    end

    test "activates from Environment user tag on generic notes" do
      assert Formatting.env_display_mode?("generic_note", ["Environment"])
      refute Formatting.env_display_mode?("generic_note", ["Notes"])
    end
  end

  describe "default_display_mode/2" do
    test "defaults env items to copy display mode" do
      assert Formatting.default_display_mode("env_note") == :copy
      assert Formatting.default_display_mode("environment_files") == :copy
      assert Formatting.default_display_mode("generic_note", ["Environment"]) == :copy
    end

    test "defaults non-env items to input mode" do
      assert Formatting.default_display_mode("generic_note") == :input
      assert Formatting.default_display_mode("guideline") == :input
      assert Formatting.default_display_mode("generic_note", ["Notes"]) == :input
    end
  end

  describe "selected_folder_linked_path/2" do
    test "returns trimmed linked path for selected folder" do
      folders = [
        %{id: 1, linked_project_path: nil},
        %{id: 2, linked_project_path: "  /tmp/my-app  "}
      ]

      assert Formatting.selected_folder_linked_path(folders, 2) == "/tmp/my-app"
      assert Formatting.selected_folder_linked_path(folders, 1) == nil
      assert Formatting.selected_folder_linked_path(folders, 99) == nil
      assert Formatting.selected_folder_linked_path(folders, nil) == nil
    end
  end
end
