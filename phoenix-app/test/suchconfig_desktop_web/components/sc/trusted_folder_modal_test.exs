defmodule SuchConfigDesktopWeb.Sc.TrustedFolderModalTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Sc.TrustedFolderModal

  describe "trusted_folder_modal/1" do
    test "renders nothing when show is false" do
      html = render_component(&TrustedFolderModal.trusted_folder_modal/1, show: false)

      refute html =~ "trusted-folder-onboarding-modal"
      refute html =~ "Choose Trusted Folder"
    end

    test "renders onboarding copy and actions when show is true" do
      html = render_component(&TrustedFolderModal.trusted_folder_modal/1, show: true)

      assert html =~ ~s(id="trusted-folder-onboarding-modal")
      assert html =~ "Trusted Folder Sync"
      assert html =~ ~s(id="trusted-folder-setup-btn")
      assert html =~ "begin_trusted_folder_setup"
      assert html =~ "dismiss_trusted_folder_modal"
      assert html =~ "Choose Trusted Folder"
    end

    test "renders error and busy state" do
      html =
        render_component(&TrustedFolderModal.trusted_folder_modal/1,
          show: true,
          busy: true,
          error: "Permission denied."
        )

      assert html =~ "Permission denied."
      assert html =~ "Opening picker"
      assert html =~ "disabled"
    end

    test "renders change-folder copy when changing is true" do
      html =
        render_component(&TrustedFolderModal.trusted_folder_modal/1,
          show: true,
          changing: true
        )

      assert html =~ "Change Trusted Folder"
      assert html =~ "Choose new folder"
      assert html =~ "Choose a new folder"
    end
  end
end
