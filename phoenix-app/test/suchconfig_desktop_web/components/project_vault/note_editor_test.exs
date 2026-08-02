defmodule SuchConfigDesktopWeb.Components.ProjectVault.NoteEditorTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Components.ProjectVault.NoteEditor
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  describe "note_actions_bar/1 project settings" do
    test "does not show project-level link or archive actions" do
      html =
        render_component(&NoteEditor.note_actions_bar/1,
          selected_folder_id: 42,
          vault_item_ui_enabled?: true,
          selected_note_id: nil,
          selected_vault_item_id: nil,
          editor_focus: :note,
          note_unlocked: false,
          note_category: "generic_note",
          display_mode: :input,
          note_raw_content: "",
          security_mode: "global_passkey",
          global_passkey_unlocked: true,
          copy_all_copied: false
        )

      refute html =~ ~s(id="link-project-button")
      refute html =~ ~s(id="note-open-archive-export")
      refute html =~ ~s(id="open-archive-import")
      refute html =~ "Link project"
      refute html =~ "Export archive"
      refute html =~ "Import archive"
    end
  end

  describe "note_actions_bar/1 env display mode" do
    test "shows edit and display mode toggles for env vault items" do
      html =
        render_component(&NoteEditor.note_actions_bar/1,
          selected_folder_id: 42,
          vault_item_ui_enabled?: true,
          selected_note_id: nil,
          selected_vault_item_id: 7,
          editor_focus: :vault_item,
          note_unlocked: true,
          note_category: "env_note",
          display_mode: :input,
          note_raw_content: "API_KEY=1\n",
          security_mode: "global_passkey",
          global_passkey_unlocked: true,
          copy_all_copied: false
        )

      assert html =~ ~s(phx-click="set_display_mode" phx-value-mode="input")
      assert html =~ ~s(phx-click="set_display_mode" phx-value-mode="copy")
      assert html =~ ~r/>\s*Edit\s*</
      assert html =~ ~r/>\s*Display\s*</
      assert html =~ "Copy env"
    end
  end

  describe "item_tag_picker/1" do
    test "renders tag icon dropdown with create form and suggestions" do
      html =
        render_component(&NoteEditor.item_tag_picker/1,
          item_tags: ["Environment"],
          tag_suggestions: ["Environment", "Secrets", "Guideline"]
        )

      assert html =~ ~s(id="vault-item-tag-picker")
      assert html =~ ~s(phx-hook="TagPicker")
      assert html =~ ~s(id="vault-item-tag-picker-form")
      assert html =~ ~s(phx-submit="add_item_tag_from_input")
      assert html =~ ~s(phx-click="add_item_tag")
      assert html =~ "Secrets"
      assert html =~ "Guideline"
      refute html =~ ~s(phx-value-tag="Environment")
    end
  end

  describe "item_tag_bar/1" do
    test "renders tags without inline add controls" do
      html =
        render_component(&NoteEditor.item_tag_bar/1,
          item_tags: ["Secrets"]
        )

      assert html =~ "Secrets"
      assert html =~ ~s(phx-click="remove_item_tag")
      refute html =~ ~s(phx-submit="add_item_tag_from_input")
      refute html =~ "Add tag"
    end
  end

  describe "note_form/1 security manifest" do
    test "shows helpful callout and report card action" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: "Security Manifest",
          note_category: "security_manifest",
          note_raw_content: ~s({"findings":[]}),
          expand_vertically?: false,
          markdown_workspace?: false,
          hide_note_category_select?: true,
          vault_item_ui_enabled?: true,
          global_passkey_unlocked: true
        )

      assert html =~ ~s(id="security-manifest-editor-hint")
      assert html =~ "Durable Security Sentinel record"
      assert html =~ ~s(phx-click="sentinel_open_report_from_manifest")
      assert html =~ "Open Report Card"
      assert html =~ "Updated by Sentinel Scan"
      refute html =~ "Stored only on this device. Vault items use a local CRDT snapshot."
    end
  end

  describe "note_form/1 markdown workspace" do
    test "renders split-pane markdown workspace for project details vault items" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: "Project Details",
          note_category: "guideline",
          note_raw_content: "```typescript\nconst ok = true\n```",
          expand_vertically?: true,
          markdown_workspace?: true,
          hide_note_category_select?: true,
          global_passkey_unlocked: true
        )

      assert html =~ ~s(id="markdown-workspace")
      assert html =~ ~s(phx-hook="MarkdownWorkspace")
      assert html =~ ~s(data-default-mode="split")
      assert html =~ ~s(data-md-mode="edit")
      assert html =~ ~s(data-md-mode="split")
      assert html =~ ~s(data-md-mode="preview")
      assert html =~ "gen-mode-switch md-mode-switch"
      assert html =~ "btn sm gen-mode-btn active"
      assert html =~ ~s(data-md-panes)
      assert html =~ ~s(data-md-editor-wrap)
      assert html =~ ~s(data-md-preview-wrap)
      assert html =~ ~s(data-md-preview)
      assert html =~ ~s(phx-update="ignore")
      assert html =~ ~s(name="note_raw_content")
      assert html =~ ~s(type="hidden")
      assert html =~ ~s(name="note_category")
      assert html =~ "Stored only on this device. Vault items use a local CRDT snapshot."
      refute html =~ "<select"
      refute html =~ ~s(type="text"\n          name="note_title")
      refute html =~ "border-indigo-500"
    end

    test "shows linked project path in file detail header" do
      path = "/Users/deeda/projects/llm_engineering"

      html =
        render_component(&SuchConfigDesktopWeb.Components.ProjectVault.FileDetail.file_detail/1,
          folders: [%{id: 1, name: "Main", linked_project_path: path}],
          notes: [%{id: 10, updated_at: ~U[2026-01-01 00:00:00Z]}],
          selected_folder_id: 1,
          selected_vault_item_id: 20,
          editor_focus: :vault_item,
          note_title: "Project Details",
          note_category: "guideline",
          note_raw_content: "# Guide",
          vault_item_ui_enabled?: true,
          global_passkey_unlocked: true
        )

      assert html =~ "Project Details"
      assert html =~ path
      assert html =~ ~s(class="linked-path")
      assert html =~ ~s(title="#{path}")
    end

    test "does not show linked project path in markdown workspace bar" do
      path = "/Users/deeda/projects/llm_engineering"

      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: "Project Details",
          note_category: "guideline",
          note_raw_content: "# Guide",
          expand_vertically?: true,
          markdown_workspace?: true,
          hide_note_category_select?: true,
          global_passkey_unlocked: true
        )

      refute html =~ path
    end

    test "renders env copy panel for env vault items in display mode" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: ".env",
          note_category: "env_note",
          note_raw_content: "API_KEY=secret\n",
          display_mode: :copy,
          expand_vertically?: true,
          global_passkey_unlocked: true
        )

      assert html =~ "API_KEY"
      assert html =~ "Copy Value"
      refute html =~ ~s(name="note_raw_content")
      refute html =~ ~s(id="env-broker-keys-panel")
    end

    test "renders broker toggles in display mode when broker UI is enabled" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: ".env",
          note_category: "env_note",
          note_raw_content: "API_KEY=secret\nOTHER=1\n",
          display_mode: :copy,
          expand_vertically?: true,
          global_passkey_unlocked: true,
          broker_ui_enabled?: true,
          selected_vault_item_id: 7,
          broker_env_enabled_keys: ["API_KEY"]
        )

      assert html =~ ~s(id="env-broker-keys-panel")
      assert html =~ ~s(id="env-broker-toggle-API_KEY")
      assert html =~ ~s(id="env-broker-toggle-OTHER")
      assert html =~ ~s(phx-click="toggle_env_broker_key")
      assert html =~ "__API_KEY__"
      assert html =~ "Check keys to enable for Local Broker"
      assert html =~ "secret"
    end

    test "hides broker toggles for free users without broker feature" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: ".env",
          note_category: "env_note",
          note_raw_content: "API_KEY=secret\n",
          display_mode: :copy,
          expand_vertically?: true,
          global_passkey_unlocked: true,
          broker_ui_enabled?: false,
          selected_vault_item_id: 7,
          broker_env_enabled_keys: ["API_KEY"]
        )

      assert html =~ "API_KEY"
      assert html =~ "secret"
      assert html =~ "Copy Value"
      refute html =~ ~s(id="env-broker-keys-panel")
      refute html =~ ~s(id="env-broker-toggle-API_KEY")
      refute html =~ ~s(phx-click="toggle_env_broker_key")
      refute html =~ "__API_KEY__"
      refute html =~ "Check keys to enable for Local Broker"
    end

    test "hides broker toggles in edit mode even when broker UI is enabled" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.vault_item_category_options(),
          editor_focus: :vault_item,
          note_title: ".env",
          note_category: "env_note",
          note_raw_content: "API_KEY=secret\n",
          display_mode: :input,
          expand_vertically?: true,
          global_passkey_unlocked: true,
          broker_ui_enabled?: true,
          selected_vault_item_id: 7,
          broker_env_enabled_keys: ["API_KEY"]
        )

      refute html =~ ~s(id="env-broker-keys-panel")
      refute html =~ ~s(id="env-broker-toggle-API_KEY")
      assert html =~ ~s(name="note_raw_content")
    end

    test "renders plain textarea when markdown workspace is disabled" do
      html =
        render_component(&NoteEditor.note_form/1,
          note_categories: Formatting.note_categories(),
          editor_focus: :note,
          note_title: "Regular note",
          note_category: "generic_note",
          note_raw_content: "plain text",
          expand_vertically?: true,
          markdown_workspace?: false,
          global_passkey_unlocked: true
        )

      refute html =~ ~s(id="markdown-workspace")
      refute html =~ ~s(phx-hook="MarkdownWorkspace")
      refute html =~ ~s(data-md-preview)
      assert html =~ ~s(name="note_raw_content")
      assert html =~ "Secure notes use Global Passkey"
    end
  end
end
