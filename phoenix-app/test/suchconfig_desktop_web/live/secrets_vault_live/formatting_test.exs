defmodule SuchConfigDesktopWeb.SecretsVaultLive.FormattingTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting

  describe "kind_label/1" do
    test "maps known kinds" do
      assert Formatting.kind_label("password") == "Login"
      assert Formatting.kind_label("api_key") == "API key"
      assert Formatting.kind_label("ssh_key") == "SSH key"
      assert Formatting.kind_label("secure_note") == "Secure note"
    end

    test "falls back to raw kind for unknown" do
      assert Formatting.kind_label("custom") == "custom"
    end
  end

  describe "vault_stats/3" do
    test "aggregates kind counts across all items" do
      items = [
        %{kind: "password"},
        %{kind: "password"},
        %{kind: "api_key"},
        %{kind: "ssh_key"},
        %{kind: "secure_note"}
      ]

      folders = [%{id: 1}, %{id: 2}]

      stats = Formatting.vault_stats(items, folders, true)

      assert stats.total == 5
      assert stats.folder_count == 2
      assert stats.login_count == 2
      assert stats.api_count == 1
      assert stats.ssh_count == 1
      assert stats.note_count == 1
      assert stats.merge_conflicts == 0
      assert stats.crdt_enabled?
    end
  end

  describe "backup_label/1 and sync_status_label/2" do
    test "shows placeholders when backup or sync are unset" do
      assert Formatting.backup_label(nil) == "Not configured"

      assert Formatting.sync_status_label(nil, nil) == "Not synced"
      assert Formatting.sync_status_label(nil, "/Users/me/Vault") == "Not synced"
    end
  end

  describe "save_error_message/1" do
    test "maps known atoms to user-facing strings" do
      assert Formatting.save_error_message(:invalid_title) == "Title is required."

      assert Formatting.save_error_message(:invalid_password) ==
               "Unlock the vault to save secrets."

      assert Formatting.save_error_message(:secrets_vault_persistence_disabled) =~ "disabled"
    end
  end
end
