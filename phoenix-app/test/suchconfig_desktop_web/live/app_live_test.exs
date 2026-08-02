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
end
