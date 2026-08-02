defmodule SuchConfigDesktop.Vault.ItemTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.Vault.{Item, ItemLink}

  describe "Item.changeset/2 — required fields and allow-lists" do
    test "valid attrs produce a valid changeset" do
      folder = project_folder_fixture()

      changeset =
        Item.changeset(%Item{}, %{
          title: "OAuth policy",
          kind: "guideline",
          security_mode: "global_passkey",
          project_folder_id: folder.id
        })

      assert changeset.valid?
    end

    test "missing title is rejected" do
      folder = project_folder_fixture()

      changeset =
        Item.changeset(%Item{}, %{kind: "generic_note", project_folder_id: folder.id})

      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "kind must be one of the allow-list" do
      folder = project_folder_fixture()

      changeset =
        Item.changeset(%Item{}, %{
          title: "x",
          kind: "not_a_kind",
          security_mode: "global_passkey",
          project_folder_id: folder.id
        })

      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :kind)
    end

    test "security_mode must be one of the allow-list" do
      folder = project_folder_fixture()

      changeset =
        Item.changeset(%Item{}, %{
          title: "x",
          kind: "generic_note",
          security_mode: "no_security",
          project_folder_id: folder.id
        })

      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :security_mode)
    end

    test "unique (project_folder_id, title) is enforced" do
      folder = project_folder_fixture()

      {:ok, _first} =
        %Item{}
        |> Item.changeset(%{
          title: "README",
          kind: "generic_note",
          security_mode: "global_passkey",
          project_folder_id: folder.id
        })
        |> Repo.insert()

      {:error, changeset} =
        %Item{}
        |> Item.changeset(%{
          title: "README",
          kind: "generic_note",
          security_mode: "global_passkey",
          project_folder_id: folder.id
        })
        |> Repo.insert()

      assert Map.has_key?(errors_on(changeset), :title)
    end
  end

  describe "Item.kind_atom/1" do
    test "returns the atom form for allow-listed kinds" do
      item = %Item{kind: "prompt_template"}
      assert Item.kind_atom(item) == :prompt_template
    end

    test "returns nil for legacy/corrupt rows" do
      assert Item.kind_atom(%Item{kind: "legacy_garbage"}) == nil
      assert Item.kind_atom(nil) == nil
    end
  end

  describe "ItemLink.changeset/2" do
    test "valid link between two items" do
      folder = project_folder_fixture()
      {:ok, a} = insert_item(folder.id, "a")
      {:ok, b} = insert_item(folder.id, "b")

      changeset =
        ItemLink.changeset(%ItemLink{}, %{
          source_id: a.id,
          target_id: b.id,
          link_kind: "references"
        })

      assert changeset.valid?
      assert {:ok, _} = Repo.insert(changeset)
    end

    test "rejects self-links" do
      folder = project_folder_fixture()
      {:ok, a} = insert_item(folder.id, "a")

      changeset =
        ItemLink.changeset(%ItemLink{}, %{
          source_id: a.id,
          target_id: a.id,
          link_kind: "references"
        })

      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :target_id)
    end

    test "rejects unknown link_kind" do
      folder = project_folder_fixture()
      {:ok, a} = insert_item(folder.id, "a")
      {:ok, b} = insert_item(folder.id, "b")

      changeset =
        ItemLink.changeset(%ItemLink{}, %{source_id: a.id, target_id: b.id, link_kind: "mystery"})

      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :link_kind)
    end
  end

  defp insert_item(folder_id, title) do
    %Item{}
    |> Item.changeset(%{
      title: title,
      kind: "generic_note",
      security_mode: "global_passkey",
      project_folder_id: folder_id
    })
    |> Repo.insert()
  end
end
