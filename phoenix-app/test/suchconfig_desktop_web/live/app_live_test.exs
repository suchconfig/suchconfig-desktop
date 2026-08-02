defmodule SuchConfigDesktopWeb.AppLiveTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SuchConfigDesktop.EnvManagerFixtures

  @live_opts [on_error: :warn]

  defp live_with_unlocked_vault(conn) do
    conn = get(conn, ~p"/")
    session_id = get_session(conn, "vault_session_id")
    SuchConfigDesktop.VaultSessionRegistry.put(session_id, "trusted-folder-test-key")
    live(conn, "/", @live_opts)
  end

  defp live_with_vault_skipped(conn) do
    conn = get(conn, ~p"/")
    {:ok, view, _html} = live(conn, "/", @live_opts)
    view |> element("button", "Proceed without unlocking") |> render_click()
    view
  end

  describe "mount" do
    test "shows unlock overlay when no key and no vault_skipped cookie", %{conn: conn} do
      conn = get(conn, ~p"/")
      {:ok, view, html} = live(conn, "/", @live_opts)

      assert has_element?(view, "#app-unlock-modal")
      assert has_element?(view, "#unlock-title")
      assert has_element?(view, "#native-global-passkey-auth-btn")
      assert html =~ "unlock-card"
      assert html =~ "Proceed without unlocking"
      assert html =~ "SuchConfig is trying to unlock your vault"
    end

    test "shows unlock overlay even when legacy vault_skipped cookie is set", %{conn: conn} do
      conn =
        conn
        |> put_req_header("cookie", "suchconfig_vault_skipped=1")
        |> get(~p"/")

      {:ok, view, html} = live(conn, "/", @live_opts)

      assert has_element?(view, "#app-unlock-modal")
      assert html =~ "Proceed without unlocking"
    end
  end

  describe "vault_key_not_found" do
    test "starts first-time unlock when keychain and database are empty", %{conn: conn} do
      conn = get(conn, ~p"/")
      {:ok, view, _html} = live(conn, "/", @live_opts)

      render_hook(view, "vault_key_not_found", %{})

      assert_push_event(view, "vault_key_from_db", %{})
      refute render(view) =~ "No vault key found"
    end
  end

  describe "proceed_without_unlock" do
    test "hides overlay for the current session", %{conn: conn} do
      conn = get(conn, ~p"/")
      {:ok, view, _html} = live(conn, "/", @live_opts)

      assert view
             |> element("button", "Proceed without unlocking")
             |> render_click() =~ "Vault locked"

      refute render(view) =~ "app-unlock-modal"
      refute render(view) =~ "Proceed without unlocking"
    end
  end

  describe "navigate" do
    test "changes current page when nav button is clicked", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      assert view |> element("#rail-settings-btn") |> render_click()
      assert render(view) =~ "Settings"
    end

    test "sidebar About shows embedded AboutLive", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      view |> element("#rail-about-btn") |> render_click()
      assert render(view) =~ "about-live-root"
      assert render(view) =~ "local-first vault for developers"
      assert render(view) =~ "very local"
    end

    test "home card navigates to Projects", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      view |> element("button", "Open Projects →") |> render_click()
      assert render(view) =~ "projects-page-root"
    end
  end

  describe "lock_global_passkey_from_settings" do
    test "sets vault_unlocked to false and shows Vault locked when Lock is clicked", %{conn: conn} do
      conn = get(conn, ~p"/")
      session_id = get_session(conn, "vault_session_id")
      SuchConfigDesktop.VaultSessionRegistry.put(session_id, "test-key")

      {:ok, view, html} = live(conn, "/", @live_opts)

      assert html =~ "Vault unlocked"
      assert has_element?(view, "#topbar-lock-vault-btn")

      view |> element("#topbar-lock-vault-btn") |> render_click()
      html = render(view)
      assert html =~ "Vault locked"
      assert html =~ "Unlock"
    end
  end

  describe "request_unlock" do
    test "navbar Unlock button is present when vault is locked", %{conn: conn} do
      view = live_with_vault_skipped(conn)
      html = render(view)

      assert html =~ "Unlock"
      assert has_element?(view, "#topbar-unlock-vault-btn")
    end
  end

  describe "handle_info :vault_locked" do
    test "shows unlock overlay when receiving :vault_locked", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      send(view.pid, :vault_locked)
      html = render(view)

      assert has_element?(view, "#app-unlock-modal")
      assert html =~ "unlock-card"
      assert html =~ "Proceed without unlocking"
    end
  end

  describe "handle_info :do_lock_global_passkey" do
    test "hides overlay and shows Vault locked when receiving :do_lock_global_passkey", %{
      conn: conn
    } do
      view = live_with_vault_skipped(conn)

      send(view.pid, :do_lock_global_passkey)
      html = render(view)

      refute html =~ "app-unlock-modal"
      assert html =~ "Vault locked"
    end
  end

  describe "trusted folder sync" do
    test "uses separate phx-hook host elements under app-live-root", %{conn: conn} do
      view = live_with_vault_skipped(conn)
      html = render(view)

      assert html =~ ~s(id="app-hook-trusted-folder-sync")
      assert html =~ ~s(phx-hook="TrustedFolderSync")
      assert html =~ ~s(id="app-hook-global-passkey-native")
      assert html =~ ~s(phx-hook="GlobalPasskeyNative")
      refute html =~ "phx-hook=\"VaultKeyStore CommandPaletteHotkey"
    end

    test "pushes fetch_trusted_folder on connect", %{conn: conn} do
      conn = get(conn, ~p"/")
      {:ok, view, _html} = live(conn, "/", @live_opts)

      assert_push_event(view, "fetch_trusted_folder", %{})
    end

    test "trusted_folder_status shows onboarding when unconfigured", %{conn: conn} do
      {:ok, view, _html} = live_with_unlocked_vault(conn)

      render_hook(view, "trusted_folder_status", %{
        "trusted_folder_path" => nil,
        "watcher_running" => false
      })

      assert has_element?(view, "#trusted-folder-onboarding-modal")
    end

    test "begin_trusted_folder_setup pushes invoke_setup_trusted_folder", %{conn: conn} do
      {:ok, view, _html} = live_with_unlocked_vault(conn)

      render_hook(view, "trusted_folder_status", %{
        "trusted_folder_path" => nil,
        "watcher_running" => false
      })

      view |> element("#trusted-folder-setup-btn") |> render_click()

      assert_push_event(view, "invoke_setup_trusted_folder", %{})
    end

    test "dismiss_trusted_folder_modal hides onboarding", %{conn: conn} do
      {:ok, view, _html} = live_with_unlocked_vault(conn)

      render_hook(view, "trusted_folder_status", %{
        "trusted_folder_path" => nil,
        "watcher_running" => false
      })

      assert has_element?(view, "#trusted-folder-onboarding-modal")

      view |> element("#trusted-folder-onboarding-modal button", "Cancel") |> render_click()

      refute has_element?(view, "#trusted-folder-onboarding-modal")
    end
  end

  describe "embedded ProjectVaultLive vault sync" do
    test "receives :vault_unlocked and unlocks embedded project vault", %{conn: conn} do
      folder = project_folder_fixture()

      conn = get(conn, ~p"/")
      session_id = get_session(conn, "vault_session_id")
      {:ok, view, _html} = live(conn, "/", @live_opts)
      view |> element("button", "Proceed without unlocking") |> render_click()
      SuchConfigDesktop.VaultSessionRegistry.put(session_id, "embedded-unlock-pw")

      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{session_id}",
        :vault_unlocked
      )

      view |> element("#rail-projects-btn") |> render_click()
      view |> element("#project-card-#{folder.id}") |> render_click()

      html = render(view)
      refute html =~ "Unlock Global Passkey"
      assert has_element?(view, "#link-project-button")
    end
  end

  describe "command palette" do
    test "opens without search input and lists commands", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_click(view, "open_command_palette")
      html = render(view)

      assert has_element?(view, "#command-palette")
      assert has_element?(view, "#command-palette-list")
      refute has_element?(view, "#command-palette-input")
      assert html =~ "Open Projects"
      assert html =~ "Open Settings"
      assert html =~ "New project"
      assert html =~ "Password Generator"
      assert html =~ "New login entry"
      assert html =~ "Import sealed archive"
      assert html =~ "N then P"
      assert html =~ "G then ,"
      assert has_element?(view, "#command-palette-list .palette-item.is-selected")
    end

    test "arrow keys move the selected highlight", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_click(view, "open_command_palette")

      first = view |> element("#command-palette-list .palette-item.is-selected") |> render()

      view
      |> element("#command-palette")
      |> render_hook("command_palette_key", %{"key" => "ArrowDown"})

      second = view |> element("#command-palette-list .palette-item.is-selected") |> render()
      refute first == second

      view
      |> element("#command-palette")
      |> render_hook("command_palette_key", %{"key" => "ArrowUp"})

      restored = view |> element("#command-palette-list .palette-item.is-selected") |> render()
      assert restored == first
    end

    test "Enter runs the highlighted command", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_click(view, "open_command_palette")
      render_click(view, "command_palette_hover", %{"index" => "1"})

      view
      |> element("#command-palette")
      |> render_hook("command_palette_key", %{"key" => "Enter"})

      html = render(view)
      refute has_element?(view, "#command-palette")
      assert html =~ "projects-page-root"
    end

    test "clicking Open Docs navigates to docs", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_click(view, "open_command_palette")
      view |> element("button[id='command-palette-item-nav.docs']") |> render_click()

      refute has_element?(view, "#command-palette")
      assert has_element?(view, "#docs-live-root")
    end

    test "Open Settings command navigates to settings", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_click(view, "command_palette_action", %{"id" => "nav.settings"})

      refute has_element?(view, "#command-palette")
      assert has_element?(view, "#settings-live-root")
    end

    test "settings chord navigates to settings", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_hook(view, "keyboard_chord", %{"id" => "nav.settings"})
      assert has_element?(view, "#settings-live-root")
    end

    test "new project command opens new folder modal on Projects", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_click(view, "command_palette_action", %{"id" => "new.proj"})

      assert has_element?(view, "#projects-page-root")
      assert has_element?(view, "#new-folder-modal")
      assert render(view) =~ "New project"
    end

    test "new project chord opens modal while staying in Project Vault", %{conn: conn} do
      folder = project_folder_fixture(%{name: "Chord Project"})
      view = live_with_vault_skipped(conn)

      view |> element("#rail-projects-btn") |> render_click()
      view |> element("#project-card-#{folder.id}") |> render_click()

      render_hook(view, "keyboard_chord", %{"id" => "new.proj"})

      assert has_element?(view, "#crumb-projects-btn")
      assert has_element?(view, "#new-folder-modal")
      assert render(view) =~ "Choose a folder on this device"
    end

    test "keyboard_chord navigates with G then W semantics", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_hook(view, "keyboard_chord", %{"id" => "nav.projects"})
      assert render(view) =~ "projects-page-root"
    end

    test "generator chord toggles the password generator drawer", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_hook(view, "keyboard_chord", %{"id" => "nav.gen"})
      assert has_element?(view, "#generator-drawer")

      render_hook(view, "keyboard_chord", %{"id" => "nav.gen"})
      refute has_element?(view, "#generator-drawer")
    end

    test "Escape closes the password generator drawer", %{conn: conn} do
      view = live_with_vault_skipped(conn)

      render_hook(view, "keyboard_chord", %{"id" => "nav.gen"})
      assert has_element?(view, "#generator-drawer")

      view |> element("#generator-drawer") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#generator-drawer")
    end

    test "lock chord locks an unlocked vault", %{conn: conn} do
      conn = get(conn, ~p"/")
      session_id = get_session(conn, "vault_session_id")
      SuchConfigDesktop.VaultSessionRegistry.put(session_id, "palette-lock-key")
      {:ok, view, _html} = live(conn, "/", @live_opts)

      render_hook(view, "keyboard_chord", %{"id" => "lock"})
      html = render(view)

      assert html =~ "Vault locked"
      refute SuchConfigDesktop.VaultSessionRegistry.get(session_id)
    end

    test "lock chord shows lock icons on project cards", %{conn: conn} do
      folder = project_folder_fixture(%{name: "Lock Icon Project"})
      conn = get(conn, ~p"/")
      session_id = get_session(conn, "vault_session_id")
      SuchConfigDesktop.VaultSessionRegistry.put(session_id, "palette-lock-cards-key")
      {:ok, view, _html} = live(conn, "/", @live_opts)

      view |> element("#rail-projects-btn") |> render_click()
      refute has_element?(view, "#project-card-lock-#{folder.id}")

      render_hook(view, "keyboard_chord", %{"id" => "lock"})

      assert has_element?(view, "#project-card-#{folder.id}")
      assert has_element?(view, "#project-card-lock-#{folder.id}")
    end
  end
end
