defmodule SuchConfigDesktopWeb.TrustedFolderEventsTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.TrustedFolder
  alias SuchConfigDesktop.Vault.Item, as: ProjectItem
  alias SuchConfigDesktopWeb.TrustedFolderEvents

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  describe "apply_status/2" do
    test "shows onboarding modal when unconfigured and user did not skip vault" do
      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "trusted_folder:status")

      socket =
        socket(%{show_unlock_overlay: false, vault_skipped: false})
        |> TrustedFolderEvents.apply_status(%{
          "trusted_folder_path" => nil,
          "watcher_running" => false
        })

      assert socket.assigns.show_trusted_folder_modal
      refute socket.assigns.trusted_folder_synced

      assert_receive {:trusted_folder_status, %{"trusted_folder_path" => nil}}
    end

    test "does not show onboarding modal when user proceeded without unlocking" do
      socket =
        socket(%{show_unlock_overlay: false, vault_skipped: true})
        |> TrustedFolderEvents.apply_status(%{
          "trusted_folder_path" => nil,
          "watcher_running" => false
        })

      refute socket.assigns.show_trusted_folder_modal
    end

    test "defers onboarding modal while unlock overlay is shown" do
      socket =
        socket(%{show_unlock_overlay: true, vault_skipped: false})
        |> TrustedFolderEvents.apply_status(%{
          "trusted_folder_path" => nil,
          "watcher_running" => false
        })

      refute socket.assigns.show_trusted_folder_modal
    end

    test "marks synced when path and watcher are set" do
      socket =
        socket(%{show_unlock_overlay: false, vault_skipped: true, vault_unlocked: true})
        |> TrustedFolderEvents.apply_status(%{
          "trusted_folder_path" => "/tmp/trusted-sync",
          "watcher_running" => true,
          "projects_enc_present" => true,
          "secrets_enc_present" => true
        })

      assert socket.assigns.trusted_folder_synced
      assert socket.assigns.trusted_folder_display_path == "/tmp/trusted-sync"
      refute socket.assigns.show_trusted_folder_modal
    end

    test "shows watching state when watcher runs but backups missing" do
      socket =
        socket(%{show_unlock_overlay: false, vault_skipped: true, vault_unlocked: false})
        |> TrustedFolderEvents.apply_status(%{
          "trusted_folder_path" => "/tmp/trusted-sync",
          "watcher_running" => true,
          "projects_enc_present" => false,
          "secrets_enc_present" => false
        })

      refute socket.assigns.trusted_folder_synced
      assert socket.assigns.trusted_folder_watcher_running
    end
  end

  describe "handle_setup_complete/2" do
    test "closes modal and flashes success" do
      socket =
        socket(%{show_trusted_folder_modal: true})
        |> TrustedFolderEvents.handle_setup_complete(%{
          "trusted_folder_path" => "/data/sync",
          "needs_initial_export" => true
        })

      refute socket.assigns.show_trusted_folder_modal
      refute socket.assigns.trusted_folder_synced
      assert Phoenix.Flash.get(socket.assigns.flash, :info) =~ "Trusted Folder activated"
    end

    test "change mode flashes location updated message" do
      socket =
        socket(%{show_trusted_folder_modal: true, trusted_folder_changing_path: true})
        |> TrustedFolderEvents.handle_setup_complete(%{
          "trusted_folder_path" => "/data/new-sync"
        })

      refute socket.assigns.trusted_folder_changing_path
      assert Phoenix.Flash.get(socket.assigns.flash, :info) =~ "location updated"
    end
  end

  describe "handle_import_snapshot/2" do
    test "imports projects bundle and flashes count" do
      folder = project_folder_fixture()

      %ProjectItem{}
      |> ProjectItem.changeset(%{
        title: "Import target",
        kind: "generic_note",
        security_mode: "global_passkey",
        project_folder_id: folder.id,
        crdt_snapshot_encrypted: <<2, 3, 4>>,
        crdt_snapshot_hash: "h",
        crdt_encryption_version: 1,
        crdt_schema_version: 1
      })
      |> Repo.insert!()

      {:ok, bundle} = TrustedFolder.export_bundle(:projects)
      b64 = Base.encode64(bundle)

      socket =
        socket(%{})
        |> TrustedFolderEvents.handle_import_snapshot(%{
          "vault" => "projects",
          "snapshot_base64" => b64
        })

      info = Phoenix.Flash.get(socket.assigns.flash, :info)
      assert info =~ "Project Vault"
      assert info =~ "merged 1 item"
    end

    test "shows error for invalid base64" do
      socket =
        socket(%{})
        |> TrustedFolderEvents.handle_import_snapshot(%{
          "vault" => "projects",
          "snapshot_base64" => "!!!"
        })

      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "Could not merge"
    end
  end

  describe "broadcast_sync/2" do
    test "publishes trusted_folder_sync on vault topic" do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "vault:#{session_id}")

      :ok = TrustedFolderEvents.broadcast_sync(session_id, "projects")

      assert_receive {:trusted_folder_sync, "projects"}
    end
  end

  describe "apply_status_to_settings/2" do
    test "preserves display path on health-only broadcast without path" do
      socket =
        socket(%{
          trusted_folder_path: "/Users/me/Dropbox/SuchConfig",
          trusted_folder_display_path: "~/Dropbox/SuchConfig",
          trusted_folder_synced: true,
          trusted_folder_watcher_running: true,
          trusted_folder_sync_busy: true,
          trusted_folder_last_error: nil,
          trusted_folder_integrity_message: nil
        })

      updated =
        TrustedFolderEvents.apply_status_to_settings(socket, %{
          "sync_busy" => false,
          "last_error" => nil
        })

      assert updated.assigns.trusted_folder_path == "/Users/me/Dropbox/SuchConfig"

      assert updated.assigns.trusted_folder_display_path ==
               TrustedFolder.display_path("/Users/me/Dropbox/SuchConfig")

      assert updated.assigns.trusted_folder_synced
      refute updated.assigns.trusted_folder_sync_busy
    end

    test "preserves configured path when status omits path" do
      socket =
        socket(%{
          trusted_folder_path: "/tmp/trusted-sync",
          trusted_folder_display_path: "/tmp/trusted-sync",
          trusted_folder_synced: true,
          trusted_folder_watcher_running: true
        })

      updated =
        TrustedFolderEvents.apply_status(socket, %{
          "watcher_running" => true,
          "projects_enc_present" => true,
          "secrets_enc_present" => true,
          "sync_busy" => false
        })

      assert updated.assigns.trusted_folder_path == "/tmp/trusted-sync"
      assert updated.assigns.trusted_folder_display_path == "/tmp/trusted-sync"
    end
  end

  describe "handle_synced/2" do
    test "refreshes trusted folder status from Tauri after sync" do
      socket =
        socket(%{
          trusted_folder_path: "/tmp/trusted-sync",
          trusted_folder_display_path: "/tmp/trusted-sync",
          trusted_folder_watcher_running: true,
          trusted_folder_synced: false,
          trusted_folder_sync_busy: true
        })

      updated = TrustedFolderEvents.handle_synced(socket, %{})

      assert updated.assigns.trusted_folder_synced
      refute updated.assigns.trusted_folder_sync_busy
      assert Phoenix.Flash.get(updated.assigns.flash, :info) =~ "backup synced"
    end
  end

  describe "ready_to_sync?/1 and notify_projects_changed/1" do
    test "ready_to_sync? requires configured watcher and unlocked vault" do
      ready =
        socket(%{
          trusted_folder_path: "/tmp/trusted-sync",
          trusted_folder_watcher_running: true,
          vault_unlocked: true
        })

      assert TrustedFolderEvents.ready_to_sync?(ready)

      refute TrustedFolderEvents.ready_to_sync?(
               socket(%{
                 trusted_folder_path: "/tmp/trusted-sync",
                 trusted_folder_watcher_running: true,
                 vault_unlocked: false
               })
             )
    end

    test "notify_projects_changed broadcasts when child socket is not ready" do
      session_id = "test-session-#{System.unique_integer([:positive])}"
      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "vault:#{session_id}")

      _ =
        socket(%{vault_session_id: session_id, vault_unlocked: false})
        |> TrustedFolderEvents.notify_projects_changed()

      assert_receive {:trusted_folder_sync, "projects"}
    end
  end
end
