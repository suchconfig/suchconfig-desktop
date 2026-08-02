defmodule SuchConfigDesktopWeb.Sc.UnlockModalTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Sc.UnlockModal

  @vault_key_id "suchconfig.project_manager.vault"

  describe "unlock_modal/1" do
    test "renders nothing when show is false" do
      html =
        render_component(&UnlockModal.unlock_modal/1,
          show: false,
          vault_key_id: @vault_key_id
        )

      refute html =~ "app-unlock-modal"
      refute html =~ "unlock-card"
    end

    test "renders unlock shell and primary actions when show is true" do
      html =
        render_component(&UnlockModal.unlock_modal/1,
          show: true,
          vault_key_id: @vault_key_id
        )

      assert html =~ ~s(id="app-unlock-modal")
      assert html =~ "unlock-card"
      assert html =~ ~s(id="unlock-title")
      assert html =~ ~s(id="native-global-passkey-auth-btn")
      assert html =~ "Proceed without unlocking"
      assert html =~ "SuchConfig is trying to unlock your vault"
      assert html =~ ~s(data-vault-key-id="#{@vault_key_id}")
      assert html =~ "Touch ID"
    end

    test "renders error and pending flashes when assigned" do
      html =
        render_component(&UnlockModal.unlock_modal/1,
          show: true,
          vault_key_id: @vault_key_id,
          vault_unlock_error: "Authentication failed.",
          vault_key_pending_store: true
        )

      assert html =~ "vault-flash err"
      assert html =~ "Authentication failed."
      assert html =~ "vault-flash ok"
      assert html =~ "Saving key to Keychain"
      assert html =~ "disabled"
    end
  end
end
