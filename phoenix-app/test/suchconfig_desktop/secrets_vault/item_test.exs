defmodule SuchConfigDesktop.SecretsVault.ItemTest do
  use SuchConfigDesktop.DataCase

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.{Folder, Item}

  describe "Item.changeset/2" do
    setup do
      {:ok, folder} =
        SecretsVault.create_folder(%{name: "Test folder #{System.unique_integer([:positive])}"})

      {:ok, folder: folder}
    end

    test "valid credential attrs produce a valid changeset", %{folder: folder} do
      changeset =
        Item.changeset(%Item{}, %{
          title: "API token",
          kind: "api_key",
          security_mode: "global_passkey",
          secrets_vault_folder_id: folder.id
        })

      assert changeset.valid?
    end

    test "rejects project vault kinds", %{folder: folder} do
      changeset =
        Item.changeset(%Item{}, %{
          title: "Note",
          kind: "generic_note",
          security_mode: "global_passkey",
          secrets_vault_folder_id: folder.id
        })

      refute changeset.valid?
      assert %{kind: _} = errors_on(changeset)
    end

    test "rejects missing title", %{folder: folder} do
      changeset =
        Item.changeset(%Item{}, %{
          kind: "password",
          security_mode: "global_passkey",
          secrets_vault_folder_id: folder.id
        })

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "unique title per folder", %{folder: folder} do
      attrs = %{
        title: "Duplicate title",
        kind: "password",
        security_mode: "global_passkey",
        secrets_vault_folder_id: folder.id
      }

      assert {:ok, _} = Repo.insert(Item.changeset(%Item{}, attrs))

      assert {:error, changeset} = Repo.insert(Item.changeset(%Item{}, attrs))
      refute changeset.valid?
      assert %{title: _} = errors_on(changeset)
    end
  end

  describe "Folder.changeset/2" do
    test "requires name" do
      changeset = Folder.changeset(%Folder{}, %{})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "unassociated_name is stable" do
      assert Folder.unassociated_name() == "Unassociated"
      assert Folder.uncategorized_name() == "Unassociated"
    end
  end
end
