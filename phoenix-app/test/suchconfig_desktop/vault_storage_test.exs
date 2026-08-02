defmodule SuchConfigDesktop.VaultStorageTest do
  use SuchConfigDesktop.DataCase, async: true

  alias SuchConfigDesktop.EnvManager.Note
  alias SuchConfigDesktop.EnvManagerFixtures
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.Item, as: SecretsItem
  alias SuchConfigDesktop.Vault.Item, as: VaultItem
  alias SuchConfigDesktop.VaultMergeAuditEvent
  alias SuchConfigDesktop.VaultStorage

  describe "format_size/1" do
    test "formats bytes, kilobytes, and megabytes" do
      assert VaultStorage.format_size(512) == {"512", "B"}
      assert VaultStorage.format_size(2048) == {"2", "KB"}
      assert VaultStorage.format_size(1_572_864) == {"1.5", "MB"}
    end
  end

  describe "summary/0" do
    test "counts project notes, secrets, projects, and archive events" do
      folder = EnvManagerFixtures.project_folder_fixture()

      %VaultItem{}
      |> VaultItem.changeset(%{
        title: "note-#{System.unique_integer([:positive])}",
        kind: "generic_note",
        security_mode: "global_passkey",
        project_folder_id: folder.id,
        crdt_snapshot_encrypted: <<1, 2, 3>>,
        crdt_snapshot_hash: "hash",
        crdt_encryption_version: 1,
        crdt_schema_version: 1
      })
      |> Repo.insert!()

      %Note{}
      |> Note.changeset(%{
        title: "legacy-#{System.unique_integer([:positive])}",
        project_folder_id: folder.id,
        note_type: "generic_note",
        security_mode: "global_passkey"
      })
      |> Repo.insert!()

      {:ok, secrets_folder} =
        SecretsVault.create_folder(%{name: "creds-#{System.unique_integer([:positive])}"})

      %SecretsItem{}
      |> SecretsItem.changeset(%{
        title: "secret-#{System.unique_integer([:positive])}",
        kind: "password",
        security_mode: "global_passkey",
        secrets_vault_folder_id: secrets_folder.id,
        crdt_snapshot_encrypted: <<4, 5, 6>>,
        crdt_snapshot_hash: "hash2",
        crdt_encryption_version: 1,
        crdt_schema_version: 1
      })
      |> Repo.insert!()

      %VaultMergeAuditEvent{}
      |> VaultMergeAuditEvent.changeset(%{
        operation: "export",
        project_folder_id: folder.id,
        metadata: %{}
      })
      |> Repo.insert!()

      summary = VaultStorage.summary()

      assert summary.secure_note_count >= 2
      assert summary.secrets_count >= 1
      assert summary.project_count >= 1
      assert summary.archive_event_count >= 1
      assert summary.bytes_on_disk > 0
      assert summary.size_value != ""
      assert summary.size_unit in ~w(B KB MB GB)
      assert summary.breakdown_label =~ "secure note"
      assert summary.breakdown_label =~ "secret"
      assert summary.breakdown_label =~ "project"
      assert summary.breakdown_label =~ "archive"
    end
  end
end
