defmodule SuchConfigDesktopWeb.Sc.TrustedFolderBadgeTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Sc.TrustedFolderBadge

  describe "trusted_folder_badge/1" do
    test "renders nothing without display path" do
      html = render_component(&TrustedFolderBadge.trusted_folder_badge/1, display_path: nil)

      refute html =~ "trusted-folder-status-badge"
    end

    test "renders synced pill when path and backed up" do
      html =
        render_component(&TrustedFolderBadge.trusted_folder_badge/1,
          id: "trusted-folder-status-badge",
          display_path: "~/Dropbox/SuchConfig",
          synced: true,
          watcher_running: true
        )

      assert html =~ ~s(id="trusted-folder-status-badge")
      assert html =~ "~/Dropbox/SuchConfig"
      assert html =~ "Backed up"
    end

    test "renders watching pill when watcher runs without backups" do
      html =
        render_component(&TrustedFolderBadge.trusted_folder_badge/1,
          display_path: "/tmp/sync",
          synced: false,
          watcher_running: true
        )

      assert html =~ "Watching"
      refute html =~ "Backed up"
    end

    test "renders paused pill when watcher is not running" do
      html =
        render_component(&TrustedFolderBadge.trusted_folder_badge/1,
          display_path: "/tmp/sync",
          synced: true,
          watcher_running: false
        )

      assert html =~ "Paused"
    end
  end
end
