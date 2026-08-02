defmodule SuchConfigDesktop.ProjectVaultTest do
  use SuchConfigDesktop.DataCase

  import Ecto.Query
  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Item
  alias SuchConfigDesktop.VaultMergeAuditEvent

  describe "merge audit" do
    test "export_secure_archive inserts an export row" do
      password = "audit-export-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})

      before = Repo.one(from e in VaultMergeAuditEvent, select: count(e.id))

      assert {:ok, _archive} = ProjectVault.export_secure_archive([folder.id], password)

      after_count = Repo.one(from e in VaultMergeAuditEvent, select: count(e.id))
      assert after_count == before + 1

      row =
        Repo.one(
          from e in VaultMergeAuditEvent,
            where: e.operation == "export",
            order_by: [desc: e.inserted_at],
            limit: 1
        )

      assert row.project_folder_id == folder.id
      assert meta(row.metadata, "archive_version") == 1
      assert meta(row.metadata, "format") == "suchvault"
      assert meta(row.metadata, "format_version") == 3
      assert meta(row.metadata, "folder_count") == 1
    end

    test "import_secure_archive inserts an import row" do
      password = "audit-import-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})

      assert {:ok, archive} = ProjectVault.export_secure_archive([folder.id], password)

      before = Repo.one(from e in VaultMergeAuditEvent, select: count(e.id))

      assert {:ok, _folders} = ProjectVault.import_secure_archive(archive, password, "duplicate")

      after_count = Repo.one(from e in VaultMergeAuditEvent, select: count(e.id))
      assert after_count == before + 1

      row =
        Repo.one(
          from e in VaultMergeAuditEvent,
            where: e.operation == "import",
            order_by: [desc: e.inserted_at],
            limit: 1
        )

      assert meta(row.metadata, "archive_version") == 1
      assert meta(row.metadata, "conflict_strategy") == "duplicate"
      assert is_integer(meta(row.metadata, "imported_folder_count"))
      assert meta(row.metadata, "format") == "suchvault"
      assert meta(row.metadata, "format_version") == 3

      routing_summary = meta(row.metadata, "folder_routing_summary")
      assert is_map(routing_summary)
      assert get_in_map(routing_summary, "created") + get_in_map(routing_summary, "merged") >= 1
      assert is_integer(get_in_map(routing_summary, "notes_imported"))
    end

    test "import_with_routing records folder_routing_summary and honors routing" do
      password = "routing-audit-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})

      assert {:ok, archive} = ProjectVault.export_secure_archive([folder.id], password)

      target =
        project_folder_fixture(%{name: "merge-target-#{System.unique_integer([:positive])}"})

      routing = %{0 => {:merge_into, target.id}}

      assert {:ok, summary} =
               ProjectVault.import_with_routing(archive, password, routing, "keep_existing")

      assert summary.merged == 1
      assert summary.created == 0

      row =
        Repo.one(
          from e in VaultMergeAuditEvent,
            where: e.operation == "import",
            order_by: [desc: e.inserted_at],
            limit: 1
        )

      routing_summary = meta(row.metadata, "folder_routing_summary")
      assert get_in_map(routing_summary, "merged") == 1
      assert get_in_map(routing_summary, "created") == 0
      assert meta(row.metadata, "conflict_strategy") == "keep_existing"
    end
  end

  defp get_in_map(map, key) when is_map(map) do
    Map.get(map, key) ||
      case key do
        k when is_binary(k) -> Map.get(map, String.to_existing_atom(k))
        _ -> nil
      end
  end

  defp meta(metadata, key) when is_binary(key) do
    Map.get(metadata, key) || Map.get(metadata, String.to_existing_atom(key))
  end

  describe "format_error" do
    test "formats atom and binary reasons" do
      assert ProjectVault.format_error(:missing) == "missing"
      assert ProjectVault.format_error("bad") == "bad"
    end
  end

  describe "vault_items" do
    test "list_vault_items_by_folder returns empty when none" do
      folder = project_folder_fixture()
      assert ProjectVault.list_vault_items_by_folder(folder.id) == []
    end

    test "list_vault_items_by_folder returns rows ordered by title" do
      folder = project_folder_fixture()

      {:ok, _} =
        %Item{}
        |> Item.changeset(%{
          title: "Zebra",
          kind: "generic_note",
          security_mode: "global_passkey",
          project_folder_id: folder.id
        })
        |> Repo.insert()

      {:ok, _} =
        %Item{}
        |> Item.changeset(%{
          title: "Alpha",
          kind: "generic_note",
          security_mode: "global_passkey",
          project_folder_id: folder.id
        })
        |> Repo.insert()

      titles =
        folder.id
        |> ProjectVault.list_vault_items_by_folder()
        |> Enum.map(& &1.title)

      assert titles == ["Alpha", "Zebra"]
    end
  end

  describe "save_vault_item / decrypt_vault_item_body" do
    setup context do
      if Map.get(context, :crdt_nif_required, false) and not Crdt.available?() do
        {:skip, "Rustler NIF `vault_crdt` not loaded; run `mix deps.compile` with Rust toolchain"}
      else
        :ok
      end
    end

    test "returns disabled when vault_item_crdt_persistence is false" do
      prev = Application.get_env(:suchconfig_desktop, :vault_item_crdt_persistence)

      on_exit(fn ->
        Application.put_env(:suchconfig_desktop, :vault_item_crdt_persistence, prev)
      end)

      Application.put_env(:suchconfig_desktop, :vault_item_crdt_persistence, false)
      folder = project_folder_fixture()

      assert {:error, :vault_item_persistence_disabled} =
               ProjectVault.save_vault_item(
                 %{
                   title: "t",
                   kind: :generic_note,
                   security_mode: :global_passkey,
                   project_folder_id: folder.id,
                   body: "x"
                 },
                 "password"
               )
    end

    test "returns crdt_unavailable when NIF is not loaded" do
      unless Crdt.available?() do
        folder = project_folder_fixture()

        assert {:error, :crdt_unavailable} =
                 ProjectVault.save_vault_item(
                   %{
                     title: "t",
                     kind: :generic_note,
                     security_mode: :global_passkey,
                     project_folder_id: folder.id,
                     body: "x"
                   },
                   "password"
                 )
      end
    end

    test "rejects empty password" do
      assert {:error, :invalid_password} =
               ProjectVault.save_vault_item(
                 %{
                   title: "t",
                   kind: :generic_note,
                   security_mode: :global_passkey,
                   project_folder_id: 1
                 },
                 ""
               )
    end

    @tag :crdt_nif_required
    test "creates vault item and decrypts body" do
      folder = project_folder_fixture()
      password = "vault-save-pw-#{System.unique_integer([:positive])}"

      assert {:ok, item} =
               ProjectVault.save_vault_item(
                 %{
                   title: "CRDT item",
                   kind: :generic_note,
                   security_mode: :global_passkey,
                   project_folder_id: folder.id,
                   body: "hello snapshot"
                 },
                 password
               )

      assert item.title == "CRDT item"
      assert is_binary(item.crdt_snapshot_encrypted)
      assert byte_size(item.crdt_snapshot_encrypted) > 0
      assert {:ok, "hello snapshot"} == ProjectVault.decrypt_vault_item_body(item, password)
    end

    @tag :crdt_nif_required
    test "updates vault item body" do
      folder = project_folder_fixture()
      password = "vault-up-pw-#{System.unique_integer([:positive])}"

      assert {:ok, created} =
               ProjectVault.save_vault_item(
                 %{
                   title: "Up",
                   kind: :generic_note,
                   security_mode: :global_passkey,
                   project_folder_id: folder.id,
                   body: "v1"
                 },
                 password
               )

      assert {:ok, updated} =
               ProjectVault.save_vault_item(
                 %{
                   id: created.id,
                   title: "Up",
                   kind: :generic_note,
                   security_mode: :global_passkey,
                   project_folder_id: folder.id,
                   body: "v2"
                 },
                 password
               )

      assert updated.id == created.id
      assert {:ok, "v2"} == ProjectVault.decrypt_vault_item_body(updated, password)
    end

    @tag :crdt_nif_required
    test "decrypt_vault_item_body rejects wrong password" do
      folder = project_folder_fixture()
      password = "right-pw-#{System.unique_integer([:positive])}"

      assert {:ok, item} =
               ProjectVault.save_vault_item(
                 %{
                   title: "Secret",
                   kind: :generic_note,
                   security_mode: :global_passkey,
                   project_folder_id: folder.id,
                   body: "x"
                 },
                 password
               )

      assert {:error, :invalid_password} = ProjectVault.decrypt_vault_item_body(item, "wrong")
    end
  end

  describe "recent_merge_audit" do
    test "returns at most limit rows newest first" do
      for i <- 1..5 do
        {:ok, _} =
          %VaultMergeAuditEvent{}
          |> VaultMergeAuditEvent.changeset(%{
            operation: "export",
            metadata: %{"n" => i}
          })
          |> Repo.insert()
      end

      ids =
        ProjectVault.recent_merge_audit(3)
        |> Enum.map(& &1.id)

      assert length(ids) == 3
      assert ids == Enum.sort(ids, :desc)
    end
  end

  describe "local broker project settings" do
    setup do
      previous_license = Application.get_env(:suchconfig_desktop, :local_broker_license_enabled)

      previous_persistence =
        Application.get_env(:suchconfig_desktop, :vault_item_crdt_persistence)

      on_exit(fn ->
        restore_env(:local_broker_license_enabled, previous_license)
        restore_env(:vault_item_crdt_persistence, previous_persistence)
      end)

      :ok
    end

    defp restore_env(key, previous) do
      if is_nil(previous) do
        Application.delete_env(:suchconfig_desktop, key)
      else
        Application.put_env(:suchconfig_desktop, key, previous)
      end
    end

    test "license stub gates local_broker_enabled?" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, false)
      refute ProjectVault.local_broker_license_enabled?()
      refute ProjectVault.local_broker_enabled?()

      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      assert ProjectVault.local_broker_license_enabled?()
      assert ProjectVault.local_broker_enabled?()
    end

    test "local_broker_enabled? requires vault item persistence" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      Application.put_env(:suchconfig_desktop, :vault_item_crdt_persistence, false)

      assert ProjectVault.local_broker_license_enabled?()
      refute ProjectVault.local_broker_enabled?()
    end

    test "update_project_broker and broker_scope_for_folder round-trip when licensed" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      assert {:ok, updated} =
               ProjectVault.update_project_broker(folder, %{
                 broker_enabled: true,
                 broker_scope_id: "uat-demo",
                 broker_allowed_domains: "api.example.com"
               })

      assert updated.broker_enabled
      assert updated.broker_scope_id == "uat-demo"
      assert updated.broker_allowed_domains == "api.example.com"
      assert ProjectVault.project_broker_enabled?(folder.id)

      assert {:ok, scope} = ProjectVault.broker_scope_for_folder(folder.id)
      assert scope.enabled
      assert scope.scope_id == "uat-demo"
      assert scope.allowed_domains == "api.example.com"
      assert scope.folder_id == folder.id

      assert ProjectVault.broker_cli_snippet("uat-demo") =~
               "suchconfig broker start --scope uat-demo"
    end

    test "update_project_broker accepts string keys and trims blank scope to nil" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      assert {:ok, updated} =
               ProjectVault.update_project_broker(folder.id, %{
                 "broker_enabled" => "true",
                 "broker_scope_id" => "  scoped-app  ",
                 "broker_allowed_domains" => "  localhost  "
               })

      assert updated.broker_enabled
      assert updated.broker_scope_id == "scoped-app"
      assert updated.broker_allowed_domains == "localhost"

      assert {:ok, cleared} =
               ProjectVault.update_project_broker(folder.id, %{
                 "broker_scope_id" => "   ",
                 "broker_allowed_domains" => ""
               })

      assert cleared.broker_scope_id == nil
      assert cleared.broker_allowed_domains == nil
    end

    test "project_broker_enabled? is false when folder broker is off" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      refute ProjectVault.project_broker_enabled?(folder.id)
      refute ProjectVault.project_broker_enabled?(nil)
    end

    test "broker_scope_for_folder returns not_found for missing folder" do
      assert {:error, :not_found} = ProjectVault.broker_scope_for_folder(9_999_999)
      assert {:error, :invalid_folder} = ProjectVault.broker_scope_for_folder("bad")
    end

    test "broker_cli_snippet is empty without a scope id" do
      assert ProjectVault.broker_cli_snippet("") == ""
      assert ProjectVault.broker_cli_snippet("   ") == ""
      assert ProjectVault.broker_cli_snippet(nil) == ""

      snippet = ProjectVault.broker_cli_snippet("my-scope")
      assert snippet =~ "suchconfig broker start --scope my-scope"
      assert snippet =~ "suchconfig broker run --scope my-scope -- <command>"
      assert snippet =~ "suchconfig broker start --scope my-scope --enable-proxy"
      assert snippet =~ "suchconfig broker run --scope my-scope --enable-proxy -- <command>"
    end

    test "parse_broker_allowed_domains normalizes comma-separated hosts" do
      assert ProjectVault.parse_broker_allowed_domains("api.GitHub.com, localhost") == [
               "api.github.com",
               "localhost"
             ]

      assert ProjectVault.parse_broker_allowed_domains("") == []
    end

    test "broker_scope_manifest_for_folder exports v1 manifest when enabled" do
      unless Crdt.available?() do
        :ok
      else
        Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
        folder = project_folder_fixture()
        password = "broker-manifest-test-password"

        assert {:ok, updated} =
                 ProjectVault.update_project_broker(folder, %{
                   broker_enabled: true,
                   broker_scope_id: "my-app-staging",
                   broker_allowed_domains: "httpbin.org, api.stripe.com"
                 })

        assert updated.broker_enabled

        assert {:ok, _item} =
                 ProjectVault.save_vault_item(
                   %{
                     title: "UAT API Key",
                     kind: "generic_note",
                     security_mode: "global_passkey",
                     project_folder_id: folder.id,
                     body: "uat-secret-value",
                     frontmatter: %{
                       "broker_enabled" => "true",
                       "broker_placeholder" => "__uat_test_key__"
                     }
                   },
                   password
                 )

        assert {:ok, manifest} =
                 ProjectVault.broker_scope_manifest_for_folder(folder.id, password)

        assert manifest.scope_id == "my-app-staging"
        assert manifest.enabled
        assert manifest.allowed_domains == ["httpbin.org", "api.stripe.com"]
        assert manifest.folder_id == folder.id
        assert manifest.credentials == %{"__uat_test_key__" => "uat-secret-value"}

        assert ProjectVault.broker_manifest_path("my-app-staging") =~
                 "my-app-staging.manifest.json"
      end
    end

    test "set_vault_item_broker_enabled persists frontmatter" do
      unless Crdt.available?() do
        :ok
      else
        Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
        folder = project_folder_fixture()
        password = "broker-item-test-password"

        assert {:ok, item} =
                 ProjectVault.save_vault_item(
                   %{
                     title: "Stripe",
                     kind: "generic_note",
                     security_mode: "global_passkey",
                     project_folder_id: folder.id,
                     body: "sk_test_example"
                   },
                   password
                 )

        assert {:ok, updated} =
                 ProjectVault.set_vault_item_broker_enabled(
                   item,
                   true,
                   %{
                     placeholder: "__stripe_sk__",
                     credential_kind: "api_key",
                     inject_as: "header"
                   },
                   password
                 )

        state = ProjectVault.vault_item_broker_state(updated, password)
        assert state.enabled
        assert state.placeholder == "__stripe_sk__"

        assert ProjectVault.broker_scope_manifest_credentials(folder.id, password) == %{
                 "__stripe_sk__" => "sk_test_example"
               }
      end
    end

    test "broker_scope_manifest_for_folder requires enabled broker and scope id" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      folder = project_folder_fixture()

      assert {:error, :broker_disabled} =
               ProjectVault.broker_scope_manifest_for_folder(folder.id)

      assert {:ok, _} =
               ProjectVault.update_project_broker(folder, %{
                 broker_enabled: true,
                 broker_scope_id: " "
               })

      assert {:error, :scope_id_required} =
               ProjectVault.broker_scope_manifest_for_folder(folder.id)
    end

    test "update_project_broker refuses without license" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, false)
      folder = project_folder_fixture()

      assert {:error, :license_local_broker_required} =
               ProjectVault.update_project_broker(folder, %{broker_enabled: true})
    end
  end

  describe "security sentinel license stub" do
    setup do
      previous = Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

      on_exit(fn ->
        if is_nil(previous) do
          Application.delete_env(:suchconfig_desktop, :security_sentinel_license_enabled)
        else
          Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, previous)
        end
      end)

      :ok
    end

    test "security_sentinel_license_enabled?/0 reads app env" do
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, false)
      refute ProjectVault.security_sentinel_license_enabled?()

      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, true)
      assert ProjectVault.security_sentinel_license_enabled?()
    end

    test "defaults to false when unset" do
      Application.delete_env(:suchconfig_desktop, :security_sentinel_license_enabled)
      refute ProjectVault.security_sentinel_license_enabled?()
    end
  end
end
