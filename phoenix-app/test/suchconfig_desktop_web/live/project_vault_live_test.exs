defmodule SuchConfigDesktopWeb.ProjectVaultLiveTest do
  use SuchConfigDesktopWeb.ConnCase

  import Phoenix.LiveViewTest
  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.ProjectVault

  @live_opts [on_error: :warn]

  defp unlocked_session_conn(%{conn: conn}) do
    conn = get(conn, ~p"/project-vault")
    vault_session_id = Plug.Conn.get_session(conn, "vault_session_id")
    SuchConfigDesktop.VaultSessionRegistry.put(vault_session_id, "shared-vault-pw")
    {:ok, conn: conn, vault_session_id: vault_session_id}
  end

  describe "mount" do
    test "renders project vault root with unlock overlay when locked", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/project-vault", @live_opts)

      assert html =~ "project-vault-root"
      assert has_element?(view, "#project-vault-root")
      assert html =~ "Unlock Global Passkey"
    end
  end

  describe "unlocked session" do
    setup context do
      if Map.get(context, :crdt_nif_required, false) and
           not SuchConfigDesktop.Vault.Crdt.available?() do
        {:skip, "Rustler NIF `vault_crdt` not loaded; run `mix deps.compile` with Rust toolchain"}
      else
        :ok
      end
    end

    setup [:unlocked_session_conn]

    test "shows archive panel and preview modal stages", %{conn: conn} do
      {:ok, _folder, _note} = seed_folder_with_note("shared-vault-pw")

      {:ok, view, html} = live(conn, ~p"/project-vault", @live_opts)

      refute html =~ "Secure Archive"

      view
      |> element("#open-archive-export")
      |> render_click()

      html = render(view)

      assert html =~ "Secure Archive"
      assert html =~ ".suchvault"
      assert html =~ "Choose export folder"
      assert html =~ "phx-hook=\"ArchiveExportFolderPicker\""

      assert has_element?(
               view,
               ~s(form[phx-submit="export_archive"] button[type="submit"][disabled])
             )

      refute has_element?(view, "#project-vault-root [phx-submit=\"preview_archive\"]")
    end

    test "export secure archive submit stays disabled until a destination folder is chosen", %{
      conn: conn
    } do
      _ = seed_folder_with_note("shared-vault-pw")

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-archive-export")
      |> render_click()

      assert has_element?(
               view,
               ~s(form[phx-submit="export_archive"] button[type="submit"][disabled])
             )

      assert render(view) =~ "Pick a folder first"

      view
      |> element("#archive-export-test-set-dest")
      |> render_click()

      refute has_element?(
               view,
               ~s(form[phx-submit="export_archive"] button[type="submit"][disabled])
             )

      assert has_element?(view, "#archive-export-selected-path-display")
      assert render(view) =~ "/tmp/suchvault-export-test"
    end

    test "clear_archive_export_destination disables export again", %{conn: conn} do
      _ = seed_folder_with_note("shared-vault-pw")

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-archive-export")
      |> render_click()

      view
      |> element("#archive-export-test-set-dest")
      |> render_click()

      refute has_element?(
               view,
               ~s(form[phx-submit="export_archive"] button[type="submit"][disabled])
             )

      view
      |> element("button", "Clear folder")
      |> render_click()

      assert has_element?(
               view,
               ~s(form[phx-submit="export_archive"] button[type="submit"][disabled])
             )

      refute has_element?(view, "#archive-export-selected-path-display")
      assert render(view) =~ "Pick a folder first"
    end

    test "closing archive panel clears export destination for next open", %{conn: conn} do
      _ = seed_folder_with_note("shared-vault-pw")

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-archive-export")
      |> render_click()

      view
      |> element("#archive-export-test-set-dest")
      |> render_click()

      assert has_element?(view, "#archive-export-selected-path-display")
      assert render(view) =~ "/tmp/suchvault-export-test"

      view
      |> element("#archive-panel-cancel")
      |> render_click()

      view
      |> element("#open-archive-export")
      |> render_click()

      assert has_element?(
               view,
               ~s(form[phx-submit="export_archive"] button[type="submit"][disabled])
             )

      refute has_element?(view, "#archive-export-selected-path-display")
    end

    test "export_archive shows error when archive password is empty", %{conn: conn} do
      _ = seed_folder_with_note("shared-vault-pw")

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-archive-export")
      |> render_click()

      view
      |> element("#archive-export-test-set-dest")
      |> render_click()

      view
      |> element("form[phx-submit=\"export_archive\"]")
      |> render_submit(%{"archive_password" => ""})

      assert render(view) =~ "Archive password is required for export."
    end

    test "export_archive pushes save_archive_export with .suchvault filename", %{conn: conn} do
      {:ok, folder, _note} = seed_folder_with_note("shared-vault-pw")

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-archive-export")
      |> render_click()

      view
      |> element("#archive-export-test-set-dest")
      |> render_click()

      view
      |> element("form[phx-submit=\"export_archive\"]")
      |> render_submit(%{"archive_password" => "shared-vault-pw"})

      assert_push_event(view, "save_archive_export", %{full_path: path, content_base64: b64})

      assert is_binary(b64)
      assert {:ok, decoded} = Base.decode64(b64)
      assert byte_size(decoded) > 0
      assert path =~ "/tmp/suchvault-export-test/"
      assert String.ends_with?(path, ".suchvault")
      assert path =~ "suchvault-"
      assert path =~ folder.name |> String.downcase()
    end

    @tag :crdt_nif_required
    test "link project flow scans folder and imports on confirm", %{conn: conn} do
      dir = Path.join(System.tmp_dir!(), "lv_link_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      File.write!(Path.join(dir, ".env"), "LIVEVIEW_KEY=1\n")

      folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#link-project-button")
      |> render_click()

      assert has_element?(view, "#link-project-modal")
      assert render(view) =~ "Drop a project folder"

      send(view.pid, {:link_project_scan_disk, dir})

      html = render(view)
      assert html =~ "Confirm"
      assert html =~ ".env"
      refute html =~ "Project Details preview"
      refute html =~ ~s(id="link-project-existing-notes")

      view
      |> element("button", "Confirm")
      |> render_click()

      out = render(view)
      assert out =~ "Imported"
      refute has_element?(view, "#link-project-modal")

      items = ProjectVault.list_vault_items_by_folder(folder.id)
      assert Enum.any?(items, &(&1.title == ".env" and &1.kind == "env_note"))
      assert Enum.any?(items, &(&1.title == "Project Details" and &1.kind == "guideline"))

      updated = ProjectVault.get_project_folder!(folder.id)
      assert updated.linked_project_path == dir
    end

    test "merge audit panel lists export after export_archive", %{conn: conn} do
      {:ok, _folder, _note} = seed_folder_with_note("shared-vault-pw")

      {:ok, view, html} = live(conn, ~p"/project-vault", @live_opts)

      refute html =~ "vault-merge-audit-panel"

      view
      |> element("#open-archive-export")
      |> render_click()

      view
      |> element("#archive-export-test-set-dest")
      |> render_click()

      view
      |> element("form[phx-submit=\"export_archive\"]")
      |> render_submit(%{"archive_password" => "shared-vault-pw"})

      view
      |> element("#vault-activity-button")
      |> render_click()

      out = render(view)
      assert out =~ "vault-merge-audit-panel"
      assert out =~ "Recent vault activity"
      assert out =~ "Secure archive exported"
    end

    test "vault activity toggle shows audit panel and back restores editor", %{conn: conn} do
      _folder = project_folder_fixture()

      {:ok, view, html} = live(conn, ~p"/project-vault", @live_opts)

      assert html =~ ~s(id="open-archive-export")
      refute html =~ "vault-merge-audit-panel"

      view
      |> element("#vault-activity-button")
      |> render_click()

      assert render(view) =~ "vault-merge-audit-panel"

      view
      |> element("#vault-activity-back-button")
      |> render_click()

      out = render(view)
      assert out =~ ~s(id="open-archive-export")
      refute out =~ "vault-merge-audit-panel"
    end

    @tag :crdt_nif_required
    test "new note opens vault item modal with tags instead of legacy category select", %{
      conn: conn
    } do
      _folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#pv-new-note-button")
      |> render_click()

      html = render(view)
      assert has_element?(view, "#new-note-modal")
      assert html =~ ~s(id="new-note-tags-input")
      assert html =~ ~s(id="new-note-type-env")
      refute html =~ "Environment Files"
    end

    @tag :crdt_nif_required
    test "saving new vault item modal persists tags and env kind", %{conn: conn} do
      alias SuchConfigDesktop.ProjectVault.VaultItemTags

      folder = project_folder_fixture()
      password = "shared-vault-pw"

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#pv-new-note-button")
      |> render_click()

      view
      |> form("#new-note-form", %{
        "note_title" => "staging.env",
        "note_raw_content" => "API_KEY=test\n",
        "note_category" => "generic_note",
        "new_note_tags" => "Environment"
      })
      |> render_submit()

      assert render(view) =~ "Vault item saved."

      items = ProjectVault.list_vault_items_by_folder(folder.id)
      item = Enum.find(items, &(&1.title == "staging.env"))
      assert item
      assert item.kind == "env_note"

      assert {:ok, raw_tags} = ProjectVault.vault_item_frontmatter(item, password, "tags")
      assert "Environment" in VaultItemTags.decode(raw_tags)
    end
  end

  defp seed_folder_with_note(password) do
    folder = project_folder_fixture()
    note = secure_note_fixture(password, %{folder: folder})
    _ = ProjectVault.list_notes_by_folder(folder.id)
    {:ok, folder, note}
  end

  describe "local broker panel" do
    setup context do
      previous = Application.get_env(:suchconfig_desktop, :local_broker_license_enabled)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:suchconfig_desktop, :local_broker_license_enabled)
        else
          Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, previous)
        end
      end)

      unlocked_session_conn(context)
    end

    test "shows upgrade card in modal when license disabled", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, false)
      _folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      assert has_element?(view, "#open-local-broker-button")
      refute has_element?(view, "#local-broker-modal")
      refute has_element?(view, "#broker-upgrade-card")

      view
      |> element("#open-local-broker-button")
      |> render_click()

      assert has_element?(view, "#local-broker-modal")
      assert has_element?(view, "#broker-upgrade-card")
      refute has_element?(view, "#project-broker-panel")

      view
      |> element("#broker-upgrade-close-button")
      |> render_click()

      refute has_element?(view, "#local-broker-modal")
    end

    test "shows project broker panel in modal and saves scope when licensed", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      refute has_element?(view, "#project-broker-panel")

      view
      |> element("#open-local-broker-button")
      |> render_click()

      assert has_element?(view, "#local-broker-modal")
      assert has_element?(view, "#project-broker-panel")
      refute has_element?(view, "#broker-upgrade-card")
      assert has_element?(view, "#broker-close-button")

      view
      |> form("#project-broker-form", %{
        "broker_scope_id" => "my-app-staging",
        "broker_allowed_domains" => "api.stripe.com",
        "broker_enabled" => "true"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Broker settings saved."
      assert html =~ "suchconfig broker start --scope my-app-staging"

      assert {:ok, scope} = ProjectVault.broker_scope_for_folder(folder.id)
      assert scope.scope_id == "my-app-staging"
      assert scope.allowed_domains == "api.stripe.com"
      assert scope.enabled
    end

    test "toggle enables broker for the selected project", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-local-broker-button")
      |> render_click()

      view
      |> element("#project-broker-form input[name=broker_enabled]")
      |> render_click()

      assert render(view) =~ "Local Broker enabled for project."
      assert ProjectVault.project_broker_enabled?(folder.id)

      view
      |> element("#project-broker-form input[name=broker_enabled]")
      |> render_click()

      assert render(view) =~ "Local Broker disabled for project."
      refute ProjectVault.project_broker_enabled?(folder.id)
    end

    test "form change updates CLI snippet before save", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      _folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-local-broker-button")
      |> render_click()

      view
      |> form("#project-broker-form", %{
        "broker_scope_id" => "suchconfig-api",
        "broker_allowed_domains" => "localhost"
      })
      |> render_change()

      html = render(view)
      assert has_element?(view, "#broker-cli-snippet")
      assert html =~ "suchconfig broker start --scope suchconfig-api"
    end

    test "copy CLI snippet pushes clipboard event after scope is set", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      _folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-local-broker-button")
      |> render_click()

      view
      |> form("#project-broker-form", %{"broker_scope_id" => "copy-me"})
      |> render_change()

      assert render_click(view, "copy_broker_cli_snippet") =~ "Copied"

      assert_push_event(view, "copy_to_clipboard", %{
        content: content
      })

      assert content =~ "suchconfig broker start --scope copy-me"
    end

    test "shows start broker controls when project broker is enabled", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      assert {:ok, _} =
               ProjectVault.update_project_broker(folder, %{
                 broker_enabled: true,
                 broker_scope_id: "my-app-staging",
                 broker_allowed_domains: "httpbin.org"
               })

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-local-broker-button")
      |> render_click()

      assert has_element?(view, "#broker-runtime")
      assert has_element?(view, "#broker-start-button")
      refute has_element?(view, "#broker-stop-button")
    end

    test "close button dismisses local broker modal", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      _folder = project_folder_fixture()

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-local-broker-button")
      |> render_click()

      assert has_element?(view, "#local-broker-modal")

      view
      |> element("#broker-close-button")
      |> render_click()

      refute has_element?(view, "#local-broker-modal")
    end

    test "start broker pushes invoke_broker_start event", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      assert {:ok, _} =
               ProjectVault.update_project_broker(folder, %{
                 broker_enabled: true,
                 broker_scope_id: "my-app-staging",
                 broker_allowed_domains: "httpbin.org"
               })

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      render_click(view, "start_project_broker")

      assert_push_event(view, "invoke_broker_start", %{
        scope_id: "my-app-staging",
        manifest: manifest
      })

      assert manifest["scope_id"] == "my-app-staging"
      assert manifest["enabled"] == true
    end
  end

  describe "security sentinel license" do
    setup context do
      previous = Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:suchconfig_desktop, :security_sentinel_license_enabled)
        else
          Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, previous)
        end
      end)

      unlocked_session_conn(context)
    end

    test "shows upgrade card when license disabled and scan clicked", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, false)
      path = "/tmp/suchconfig-sentinel-live-#{System.unique_integer([:positive])}"
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf(path) end)

      folder = project_folder_fixture()

      assert {:ok, _} =
               ProjectVault.update_project_folder(folder, %{
                 linked_project_path: path,
                 linked_sync_enabled: true
               })

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      assert has_element?(view, "#open-sentinel-scan-button")
      refute has_element?(view, "#sentinel-upgrade-card")

      view
      |> element("#open-sentinel-scan-button")
      |> render_click()

      assert has_element?(view, "#sentinel-report-card-modal")
      assert has_element?(view, "#sentinel-upgrade-card")
      refute has_element?(view, "#sentinel-report-card-modal button", "Rescan Project")

      view
      |> element("#sentinel-upgrade-close-button")
      |> render_click()

      refute has_element?(view, "#sentinel-upgrade-card")
    end

    test "starts rescan push_event when licensed", %{conn: conn} do
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, true)
      path = "/tmp/suchconfig-sentinel-live-ok-#{System.unique_integer([:positive])}"
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf(path) end)

      folder = project_folder_fixture()

      assert {:ok, _} =
               ProjectVault.update_project_folder(folder, %{
                 linked_project_path: path,
                 linked_sync_enabled: true
               })

      {:ok, view, _html} = live(conn, ~p"/project-vault", @live_opts)

      view
      |> element("#open-sentinel-scan-button")
      |> render_click()

      assert_push_event(view, "invoke_sentinel_rescan", %{
        path: ^path,
        folder_id: folder_id
      })

      assert folder_id == folder.id
      refute has_element?(view, "#sentinel-upgrade-card")
    end
  end
end
