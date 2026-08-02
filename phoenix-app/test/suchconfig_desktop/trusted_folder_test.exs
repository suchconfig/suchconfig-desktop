defmodule SuchConfigDesktop.TrustedFolderTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.Item, as: SecretsItem
  alias SuchConfigDesktop.TrustedFolder
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Item, as: ProjectItem

  describe "configured?/1 and display_path/1" do
    test "configured? is false for nil and blank" do
      refute TrustedFolder.configured?(nil)
      refute TrustedFolder.configured?("")
      refute TrustedFolder.configured?("   ")
    end

    test "configured? is true for non-empty path" do
      assert TrustedFolder.configured?("/tmp/sync")
    end

    test "display_path shortens HOME prefix" do
      home = System.get_env("HOME") || ""

      if home != "" do
        assert TrustedFolder.display_path("#{home}/Dropbox/SuchConfig") =~ "~/"
      else
        assert TrustedFolder.display_path("/var/sync") == "/var/sync"
      end
    end
  end

  describe "export_bundle/1" do
    test "projects bundle is valid JSON with format metadata" do
      assert {:ok, binary} = TrustedFolder.export_bundle(:projects)

      assert %{
               "format" => "suchconfig_trusted_sync",
               "format_version" => 1,
               "vault" => "projects"
             } =
               Jason.decode!(binary)
    end

    test "secrets bundle is valid JSON with format metadata" do
      assert {:ok, binary} = TrustedFolder.export_bundle(:secrets)

      assert %{
               "format" => "suchconfig_trusted_sync",
               "vault" => "secrets",
               "folders" => folders
             } =
               Jason.decode!(binary)

      assert is_list(folders)
    end

    test "secrets export includes secrets folders" do
      {:ok, _} = SecretsVault.ensure_uncategorized_folder()

      {:ok, folder} =
        %SuchConfigDesktop.SecretsVault.Folder{}
        |> SuchConfigDesktop.SecretsVault.Folder.changeset(%{
          name: "Synced secrets folder",
          description: "notes"
        })
        |> Repo.insert()

      assert {:ok, binary} = TrustedFolder.export_bundle(:secrets)
      %{"folders" => folders} = Jason.decode!(binary)

      assert Enum.any?(
               folders,
               &(&1["name"] == "Synced secrets folder" and &1["id"] == folder.id)
             )
    end

    test "projects export includes vault items" do
      folder = project_folder_fixture()

      _ =
        project_item_fixture(folder, %{
          title: "Export me",
          crdt_snapshot_encrypted: <<4, 5, 6>>
        })

      assert {:ok, binary} = TrustedFolder.export_bundle(:projects)
      %{"items" => items} = Jason.decode!(binary)
      assert Enum.any?(items, &(&1["title"] == "Export me"))
    end

    test "projects export includes project folders" do
      folder = project_folder_fixture(%{name: "Synced Project", description: "notes"})

      assert {:ok, binary} = TrustedFolder.export_bundle(:projects)
      %{"folders" => folders} = Jason.decode!(binary)
      assert Enum.any?(folders, &(&1["name"] == "Synced Project" and &1["id"] == folder.id))
    end
  end

  describe "import_bundle/2" do
    test "round-trip upserts project item by folder and title" do
      folder = project_folder_fixture()

      item =
        project_item_fixture(folder, %{
          title: "Round trip",
          crdt_snapshot_encrypted: <<10, 11>>
        })

      assert {:ok, exported} = TrustedFolder.export_bundle(:projects)
      Repo.delete!(item)

      assert {:ok, %{upserted: 1, skipped: 0}} = TrustedFolder.import_bundle(exported, :projects)

      imported =
        Repo.one!(
          from i in ProjectItem,
            where: i.project_folder_id == ^folder.id and i.title == "Round trip"
        )

      assert imported.crdt_snapshot_encrypted == <<10, 11>>
    end

    test "round-trip upserts project folders by name" do
      _folder = project_folder_fixture(%{name: "Cross-device project", description: "sync me"})

      assert {:ok, exported} = TrustedFolder.export_bundle(:projects)

      Repo.delete_all(from(f in SuchConfigDesktop.EnvManager.ProjectFolder))

      assert {:ok, _} = TrustedFolder.import_bundle(exported, :projects)

      imported =
        Repo.one!(
          from f in SuchConfigDesktop.EnvManager.ProjectFolder,
            where: f.name == "Cross-device project"
        )

      assert imported.description == "sync me"
    end

    test "round-trip upserts secrets item" do
      {:ok, folder} = SecretsVault.ensure_uncategorized_folder()

      item =
        secrets_item_fixture(folder, %{
          title: "Secret sync",
          crdt_snapshot_encrypted: <<7, 8, 9>>
        })

      assert {:ok, exported} = TrustedFolder.export_bundle(:secrets)
      Repo.delete!(item)

      assert {:ok, %{upserted: 1, skipped: 0}} = TrustedFolder.import_bundle(exported, :secrets)

      imported =
        Repo.one!(
          from i in SecretsItem,
            where: i.secrets_vault_folder_id == ^folder.id and i.title == "Secret sync"
        )

      assert imported.crdt_snapshot_encrypted == <<7, 8, 9>>
    end

    test "remaps secrets folder ids across import" do
      {:ok, _} = SecretsVault.ensure_uncategorized_folder()

      {:ok, source_folder} =
        %SuchConfigDesktop.SecretsVault.Folder{}
        |> SuchConfigDesktop.SecretsVault.Folder.changeset(%{
          name: "Handoff folder",
          description: "from source device"
        })
        |> Repo.insert()

      _item =
        secrets_item_fixture(source_folder, %{
          title: "In remapped folder",
          crdt_snapshot_encrypted: <<7, 8, 9>>
        })

      assert {:ok, exported} = TrustedFolder.export_bundle(:secrets)

      Repo.delete_all(from(i in SecretsItem))

      Repo.delete_all(
        from(f in SuchConfigDesktop.SecretsVault.Folder, where: f.name != "Unassociated")
      )

      assert {:ok, %{upserted: 1, skipped: 0}} = TrustedFolder.import_bundle(exported, :secrets)

      imported_folder =
        Repo.one!(
          from f in SuchConfigDesktop.SecretsVault.Folder,
            where: f.name == "Handoff folder"
        )

      imported_item =
        Repo.one!(
          from i in SecretsItem,
            where: i.title == "In remapped folder"
        )

      assert imported_item.secrets_vault_folder_id == imported_folder.id
    end

    test "import skips invalid secrets items without failing whole bundle" do
      {:ok, folder} = SecretsVault.ensure_uncategorized_folder()

      _good =
        secrets_item_fixture(folder, %{
          title: "Good secret",
          crdt_snapshot_encrypted: <<7, 8, 9>>
        })

      assert {:ok, exported} = TrustedFolder.export_bundle(:secrets)
      {:ok, decoded} = Jason.decode(exported)

      bad_item = %{
        "title" => "",
        "secrets_vault_folder_id" => folder.id,
        "crdt_snapshot_encrypted" => Base.encode64(<<1>>)
      }

      modified =
        decoded
        |> Map.put("items", decoded["items"] ++ [bad_item])
        |> Jason.encode!()

      assert {:ok, %{upserted: 1, skipped: 1}} = TrustedFolder.import_bundle(modified, :secrets)
    end

    test "legacy secrets bundle without folders still imports items" do
      {:ok, folder} = SecretsVault.ensure_uncategorized_folder()

      item =
        secrets_item_fixture(folder, %{
          title: "Legacy bundle item",
          crdt_snapshot_encrypted: <<7, 8, 9>>
        })

      assert {:ok, exported} = TrustedFolder.export_bundle(:secrets)
      {:ok, decoded} = Jason.decode(exported)
      legacy = decoded |> Map.delete("folders") |> Jason.encode!()
      Repo.delete!(item)

      assert {:ok, %{upserted: 1, skipped: 0}} = TrustedFolder.import_bundle(legacy, :secrets)

      assert Repo.one!(
               from i in SecretsItem,
                 where:
                   i.secrets_vault_folder_id == ^folder.id and i.title == "Legacy bundle item"
             )
    end

    test "prunes local items missing from imported projects bundle" do
      folder = project_folder_fixture()

      _kept =
        project_item_fixture(folder, %{
          title: "Keep me",
          crdt_snapshot_encrypted: <<10, 11>>
        })

      stale =
        project_item_fixture(folder, %{
          title: "Remove me",
          crdt_snapshot_encrypted: <<12, 13>>
        })

      assert {:ok, exported} = TrustedFolder.export_bundle(:projects)
      {:ok, decoded} = Jason.decode(exported)

      filtered =
        decoded
        |> Map.put("items", Enum.reject(decoded["items"], &(&1["title"] == "Remove me")))
        |> Jason.encode!()

      assert {:ok, stats} = TrustedFolder.import_bundle(filtered, :projects)
      assert stats.deleted_items == 1

      refute Repo.get(ProjectItem, stale.id)
    end

    test "prunes local project folders missing from imported bundle" do
      _kept = project_folder_fixture(%{name: "kept-folder"})
      _stale = project_folder_fixture(%{name: "stale-folder"})

      assert {:ok, exported} = TrustedFolder.export_bundle(:projects)
      {:ok, decoded} = Jason.decode(exported)

      filtered =
        decoded
        |> Map.put("folders", Enum.reject(decoded["folders"], &(&1["name"] == "stale-folder")))
        |> Jason.encode!()

      assert {:ok, stats} = TrustedFolder.import_bundle(filtered, :projects)
      assert stats.deleted_folders == 1

      refute Repo.one(
               from f in SuchConfigDesktop.EnvManager.ProjectFolder,
                 where: f.name == "stale-folder"
             )
    end

    test "rejects bundle for wrong vault atom" do
      assert {:ok, projects} = TrustedFolder.export_bundle(:projects)
      assert {:error, :invalid_bundle} = TrustedFolder.import_bundle(projects, :secrets)
    end

    test "rejects invalid JSON" do
      assert {:error, _} = TrustedFolder.import_bundle("not-json", :projects)
    end
  end

  describe "vault_atom/1" do
    test "maps known vault strings" do
      assert TrustedFolder.vault_atom("projects") == :projects
      assert TrustedFolder.vault_atom("secrets") == :secrets
      assert TrustedFolder.vault_atom("other") == nil
    end
  end

  describe "handoff export/import" do
    test "re-encrypts secrets items under receiver vault key" do
      skip_unless_crdt_available!()

      export_pw = "device-a-vault-key"
      import_pw = "device-b-vault-key"
      {:ok, folder} = SecretsVault.ensure_uncategorized_folder()

      {:ok, _} =
        SecretsVault.save_item(
          %{
            title: "Cross-device secret",
            kind: "password",
            secrets_vault_folder_id: folder.id,
            body: "super-secret-value"
          },
          export_pw
        )

      assert {:ok, exported} = TrustedFolder.export_handoff_bundle(:secrets, export_pw)

      decoded = Jason.decode!(exported)
      assert decoded["format"] == "suchconfig_handoff_sync"
      assert Enum.all?(decoded["items"], &Map.has_key?(&1, "crdt_snapshot_plain_b64"))
      refute Enum.any?(decoded["items"], &Map.has_key?(&1, "crdt_snapshot_encrypted"))

      Repo.delete_all(from(i in SecretsItem))

      assert {:ok, %{upserted: 1, skipped: 0}} =
               TrustedFolder.import_handoff_bundle(exported, :secrets, import_pw)

      imported =
        Repo.one!(
          from i in SecretsItem,
            where: i.secrets_vault_folder_id == ^folder.id and i.title == "Cross-device secret"
        )

      assert {:error, :invalid_password} = SecretsVault.decrypt_item_body(imported, export_pw)
      assert {:ok, "super-secret-value"} = SecretsVault.decrypt_item_body(imported, import_pw)
    end

    test "re-encrypts project items under receiver vault key" do
      skip_unless_crdt_available!()

      export_pw = "device-a-vault-key"
      import_pw = "device-b-vault-key"
      folder = project_folder_fixture()

      {:ok, _} =
        ProjectVault.save_vault_item(
          %{
            title: "Cross-device note",
            kind: "generic_note",
            security_mode: "global_passkey",
            project_folder_id: folder.id,
            body: "project body text"
          },
          export_pw
        )

      assert {:ok, exported} = TrustedFolder.export_handoff_bundle(:projects, export_pw)

      decoded = Jason.decode!(exported)
      assert decoded["format"] == "suchconfig_handoff_sync"

      Repo.delete_all(from(i in ProjectItem))

      assert {:ok, %{upserted: 1, skipped: 0}} =
               TrustedFolder.import_handoff_bundle(exported, :projects, import_pw)

      imported =
        Repo.one!(
          from i in ProjectItem,
            where: i.project_folder_id == ^folder.id and i.title == "Cross-device note"
        )

      assert {:error, :invalid_password} =
               ProjectVault.decrypt_vault_item_body(imported, export_pw)

      assert {:ok, "project body text"} =
               ProjectVault.decrypt_vault_item_body(imported, import_pw)
    end

    test "handoff import rejects trusted folder bundle format" do
      assert {:ok, trusted} = TrustedFolder.export_bundle(:secrets)

      assert {:error, :invalid_bundle} =
               TrustedFolder.import_handoff_bundle(trusted, :secrets, "key-b")
    end

    test "handoff export skips items that cannot decrypt with export password" do
      skip_unless_crdt_available!()

      export_pw = "device-a-vault-key"
      {:ok, folder} = SecretsVault.ensure_uncategorized_folder()

      {:ok, _} =
        SecretsVault.save_item(
          %{
            title: "Decryptable secret",
            kind: "password",
            secrets_vault_folder_id: folder.id,
            body: "visible"
          },
          export_pw
        )

      _opaque =
        secrets_item_fixture(folder, %{
          title: "Opaque blob",
          crdt_snapshot_encrypted: <<7, 8, 9>>
        })

      assert {:ok, exported} = TrustedFolder.export_handoff_bundle(:secrets, export_pw)
      %{"items" => items} = Jason.decode!(exported)
      assert Enum.any?(items, &(&1["title"] == "Decryptable secret"))
      refute Enum.any?(items, &(&1["title"] == "Opaque blob"))
    end
  end

  defp skip_unless_crdt_available! do
    unless Crdt.available?(), do: raise("NIF unavailable")
  end

  defp project_item_fixture(folder, attrs) do
    defaults = %{
      title: "Item #{System.unique_integer([:positive])}",
      kind: "generic_note",
      security_mode: "global_passkey",
      project_folder_id: folder.id,
      crdt_snapshot_encrypted: <<1, 2, 3>>,
      crdt_snapshot_hash: "hash",
      crdt_encryption_version: 1,
      crdt_schema_version: 1
    }

    %ProjectItem{}
    |> ProjectItem.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp secrets_item_fixture(folder, attrs) do
    defaults = %{
      title: "Secret #{System.unique_integer([:positive])}",
      kind: "password",
      security_mode: "global_passkey",
      secrets_vault_folder_id: folder.id,
      crdt_snapshot_encrypted: <<1, 2, 3>>,
      crdt_snapshot_hash: "hash",
      crdt_encryption_version: 1,
      crdt_schema_version: 1
    }

    %SecretsItem{}
    |> SecretsItem.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
