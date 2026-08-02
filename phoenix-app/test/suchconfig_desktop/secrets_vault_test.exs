defmodule SuchConfigDesktop.SecretsVaultTest do
  use SuchConfigDesktop.DataCase

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.Folder
  alias SuchConfigDesktop.Vault.Crdt

  @password "test-vault-password-placeholder"
  @wrong_password "wrong-vault-password-placeholder"

  defp save_item!(folder, attrs, password \\ @password) do
    attrs =
      Map.merge(
        %{
          kind: "password",
          security_mode: "global_passkey",
          secrets_vault_folder_id: folder.id,
          body: "placeholder-body"
        },
        attrs
      )

    {:ok, item} = SecretsVault.save_item(attrs, password)
    item
  end

  describe "feature flags" do
    test "secrets_vault_enabled? reads application env" do
      prev = Application.get_env(:suchconfig_desktop, :secrets_vault_enabled)
      on_exit(fn -> Application.put_env(:suchconfig_desktop, :secrets_vault_enabled, prev) end)

      Application.put_env(:suchconfig_desktop, :secrets_vault_enabled, false)
      refute SecretsVault.secrets_vault_enabled?()

      Application.put_env(:suchconfig_desktop, :secrets_vault_enabled, true)
      assert SecretsVault.secrets_vault_enabled?()
    end
  end

  describe "folders" do
    test "ensure_unassociated_folder creates default folder once" do
      assert {:ok, %Folder{name: "Unassociated"}} = SecretsVault.ensure_unassociated_folder()
      assert {:ok, %Folder{name: "Unassociated"}} = SecretsVault.ensure_unassociated_folder()
    end

    test "create_folder, update_folder, delete_folder, list_folders" do
      assert {:ok, folder} =
               SecretsVault.create_folder(%{name: "Work", description: "Work creds"})

      assert folder.description == "Work creds"

      assert {:ok, updated} = SecretsVault.update_folder(folder, %{name: "Work updated"})
      assert updated.name == "Work updated"
      assert Enum.any?(SecretsVault.list_folders(), &(&1.id == updated.id))

      assert {:ok, _} = SecretsVault.delete_folder(updated)
      refute Enum.any?(SecretsVault.list_folders(), &(&1.id == updated.id))
    end
  end

  describe "save_item / decrypt / delete" do
    setup context do
      if Map.get(context, :crdt_nif_required, true) and not Crdt.available?() do
        {:skip, "Rustler NIF not loaded"}
      else
        {:ok, folder} = SecretsVault.ensure_uncategorized_folder()
        {:ok, folder: folder}
      end
    end

    test "persists and decrypts a password entry", %{folder: folder} do
      attrs = %{
        title: "Example login",
        kind: "password",
        body: "test-secret-body-value",
        frontmatter: %{"username" => "user@example.com", "url" => "https://example.com"}
      }

      item = save_item!(folder, attrs)

      assert item.title == "Example login"
      assert item.kind == "password"
      assert is_binary(item.crdt_snapshot_encrypted)
      assert byte_size(item.crdt_snapshot_encrypted) > 0

      assert {:ok, body} = SecretsVault.decrypt_item_body(item, @password)
      assert body == "test-secret-body-value"

      assert {:ok, fm} = SecretsVault.decrypt_item_frontmatter(item, @password)
      assert fm["username"] == "user@example.com"
      assert fm["url"] == "https://example.com"

      assert length(SecretsVault.list_items(folder.id)) == 1
    end

    @tag :crdt_nif_required
    test "supports all credential kinds", %{folder: folder} do
      for {kind, body} <- [
            {"password", "pw-value"},
            {"api_key", "sk-live-placeholder"},
            {"ssh_key", "-----BEGIN OPENSSH PRIVATE KEY-----\n"},
            {"secure_note", "Freeform note content"}
          ] do
        item = save_item!(folder, %{title: "Entry #{kind}", kind: kind, body: body})
        assert item.kind == kind
        assert {:ok, ^body} = SecretsVault.decrypt_item_body(item, @password)
      end

      assert length(SecretsVault.list_items(folder.id)) == 4
    end

    @tag :crdt_nif_required
    test "updates existing item body and frontmatter", %{folder: folder} do
      item =
        save_item!(folder, %{title: "Updatable", body: "v1", frontmatter: %{"username" => "old"}})

      assert {:ok, updated} =
               SecretsVault.save_item(
                 %{
                   id: item.id,
                   title: "Updatable",
                   kind: "password",
                   secrets_vault_folder_id: folder.id,
                   body: "v2",
                   frontmatter: %{"username" => "new"}
                 },
                 @password
               )

      assert updated.id == item.id
      assert {:ok, "v2"} = SecretsVault.decrypt_item_body(updated, @password)
      assert {:ok, fm} = SecretsVault.decrypt_item_frontmatter(updated, @password)
      assert fm["username"] == "new"
    end

    @tag :crdt_nif_required
    test "moves item to another folder on update", %{folder: folder} do
      {:ok, target} =
        SecretsVault.create_folder(%{name: "Target #{System.unique_integer([:positive])}"})

      item = save_item!(folder, %{title: "Movable", body: "secret"})

      assert {:ok, updated} =
               SecretsVault.save_item(
                 %{
                   id: item.id,
                   title: "Movable",
                   kind: "password",
                   secrets_vault_folder_id: target.id,
                   body: "secret"
                 },
                 @password
               )

      assert updated.secrets_vault_folder_id == target.id
      refute Enum.any?(SecretsVault.list_items(folder.id), &(&1.id == item.id))
      assert Enum.any?(SecretsVault.list_items(target.id), &(&1.id == item.id))
    end

    test "assigns unassociated folder when folder id omitted" do
      assert {:ok, item} =
               SecretsVault.save_item(
                 %{title: "Loose entry", kind: "password", body: "x"},
                 @password
               )

      assert item.secrets_vault_folder_id
      folder = Repo.get!(Folder, item.secrets_vault_folder_id)
      assert folder.name == Folder.unassociated_name()
    end

    test "search_items matches title and frontmatter", %{folder: folder} do
      save_item!(folder, %{
        title: "GitHub",
        body: "pw",
        frontmatter: %{"username" => "dev@corp.com"}
      })

      save_item!(folder, %{title: "Other", kind: "api_key", body: "key", frontmatter: %{}})

      assert [%{title: "GitHub"}] = SecretsVault.search_items(folder.id, "github", @password)
      assert [%{title: "GitHub"}] = SecretsVault.search_items(folder.id, "dev@corp", @password)
      assert SecretsVault.search_items(folder.id, "", @password) |> length() == 2
    end

    test "decrypt fails with wrong password", %{folder: folder} do
      item = save_item!(folder, %{title: "Secret", body: "hidden"})

      assert {:error, :invalid_password} = SecretsVault.decrypt_item_body(item, @wrong_password)

      assert {:error, :invalid_password} =
               SecretsVault.decrypt_item_frontmatter(item, @wrong_password)
    end

    test "delete_item removes row", %{folder: folder} do
      item = save_item!(folder, %{title: "To delete"})
      assert {:ok, _} = SecretsVault.delete_item(item.id)
      assert SecretsVault.get_item(item.id) == nil
    end

    test "delete_item returns not_found for missing id" do
      assert {:error, :not_found} = SecretsVault.delete_item(-1)
    end

    test "rejects empty password" do
      assert {:error, :invalid_password} =
               SecretsVault.save_item(%{title: "X", kind: "password", body: ""}, "")
    end

    test "rejects save when persistence disabled", %{folder: folder} do
      prev = Application.get_env(:suchconfig_desktop, :secrets_vault_crdt_persistence)

      on_exit(fn ->
        Application.put_env(:suchconfig_desktop, :secrets_vault_crdt_persistence, prev)
      end)

      Application.put_env(:suchconfig_desktop, :secrets_vault_crdt_persistence, false)

      assert {:error, :secrets_vault_persistence_disabled} =
               SecretsVault.save_item(
                 %{title: "X", kind: "password", secrets_vault_folder_id: folder.id, body: ""},
                 @password
               )
    end

    test "returns crdt_unavailable when NIF is not loaded", %{folder: folder} do
      unless Crdt.available?() do
        assert {:error, :crdt_unavailable} =
                 SecretsVault.save_item(
                   %{title: "X", kind: "password", secrets_vault_folder_id: folder.id, body: ""},
                   @password
                 )
      end
    end

    test "rejects invalid title" do
      assert {:error, :invalid_title} =
               SecretsVault.save_item(%{title: "  ", kind: "password", body: ""}, @password)
    end

    test "rejects unknown kind", %{folder: folder} do
      assert {:error, :unknown_kind} =
               SecretsVault.save_item(
                 %{
                   title: "Bad",
                   kind: "generic_note",
                   secrets_vault_folder_id: folder.id,
                   body: ""
                 },
                 @password
               )
    end
  end

  describe "format_error/1" do
    test "formats atoms and strings" do
      assert SecretsVault.format_error(:not_found) == "not found"
      assert SecretsVault.format_error("bad") == "bad"
    end
  end
end
