defmodule SuchConfigDesktop.LanSyncTest do
  use SuchConfigDesktop.DataCase

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.LanSync
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.Vault.Crdt

  describe "handoff bundles" do
    test "export and import re-wrap secrets under receiver vault key" do
      skip_unless_crdt_available!()

      export_pw = "lan-export-key"
      import_pw = "lan-import-key"
      {:ok, folder} = SecretsVault.ensure_unassociated_folder()

      {:ok, _} =
        SecretsVault.save_item(
          %{
            title: "LAN handoff secret",
            kind: "password",
            secrets_vault_folder_id: folder.id,
            body: "handoff-body"
          },
          export_pw
        )

      bundles = LanSync.export_handoff_bundles(export_pw)
      bundle = Enum.find(bundles, &(&1.vault == "secrets"))
      assert bundle != nil

      assert {:ok, %{upserted: upserted}} =
               LanSync.import_handoff_bundle(bundle.vault, bundle.snapshot_base64, import_pw)

      assert upserted >= 1

      item =
        SuchConfigDesktop.Repo.one!(
          from i in SuchConfigDesktop.SecretsVault.Item,
            where: i.title == "LAN handoff secret"
        )

      assert {:ok, "handoff-body"} = SecretsVault.decrypt_item_body(item, import_pw)
    end
  end

  describe "sync_apply/3" do
    test "applies a Loro delta to an existing secrets item" do
      skip_unless_crdt_available!()

      password = "lan-sync-test-password"

      {:ok, snap_a} = Crdt.new_doc("password")
      {:ok, snap_a} = Crdt.set_body(snap_a, "alpha")
      {:ok, snap_b} = Crdt.new_doc("password")
      {:ok, snap_b} = Crdt.set_body(snap_b, "beta")
      {:ok, delta} = Crdt.diff_from(snap_b, snap_a)

      {:ok, %{id: folder_id}} = SecretsVault.ensure_unassociated_folder()

      {:ok, item} =
        SecretsVault.save_item(
          %{
            title: "LAN Sync Test",
            kind: "password",
            secrets_vault_folder_id: folder_id,
            body: "alpha"
          },
          password
        )

      key = LanSync.item_key("secrets", folder_id, "LAN Sync Test")

      update = %{
        "vault" => "secrets",
        "item_key" => key,
        "delta_base64" => Base.encode64(delta)
      }

      assert {:ok, %{applied: 1}} =
               LanSync.sync_apply("peer-device-1", [update], password)

      item = SuchConfigDesktop.Repo.reload!(item)
      assert item.crdt_snapshot_hash != nil
      {:ok, body} = SecretsVault.decrypt_item_body(item, password)
      assert body != "alpha"
      assert String.contains?(body, "beta")
    end
  end

  defp skip_unless_crdt_available! do
    unless Crdt.available?(), do: raise("NIF unavailable")
  end
end
