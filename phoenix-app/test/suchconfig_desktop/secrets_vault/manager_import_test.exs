defmodule SuchConfigDesktop.SecretsVault.ManagerImportTest do
  use SuchConfigDesktop.DataCase

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.ManagerImport
  alias SuchConfigDesktop.Vault.Crdt

  @password "test-vault-password-placeholder"
  @fixture Path.expand(
             "../../../../../suchconfig-core/test/fixtures/importers/bitwarden_sample.json",
             __DIR__
           )

  setup do
    if not Crdt.available?() do
      {:skip, "Rustler NIF not loaded"}
    else
      :ok
    end
  end

  test "preview_bitwarden_export returns counts and samples" do
    json = File.read!(@fixture)
    assert {:ok, preview} = ManagerImport.preview_bitwarden_export(json)
    assert preview.source == :bitwarden
    assert preview.folder_count == 1
    assert preview.item_count == 6
    assert preview.duplicate_count == 0
    assert length(preview.sample_items) == 6
    assert Enum.any?(preview.warnings, &String.contains?(&1, "Card"))
  end

  test "preview rejects encrypted export" do
    assert {:error, :encrypted_export} =
             ManagerImport.preview_bitwarden_export(~s({"encrypted":true,"items":[]}))
  end

  test "import_normalized creates folders and items" do
    json = File.read!(@fixture)
    assert {:ok, preview} = ManagerImport.preview_bitwarden_export(json)
    assert {:ok, result} = ManagerImport.import_normalized(preview.import_data, :all, @password)

    assert result.imported == 6
    assert result.created == 6
    assert result.overwritten == 0
    assert result.skipped == 0
    assert is_binary(result.batch_id)

    folders = SecretsVault.list_folders()
    assert Enum.any?(folders, &(&1.name == "Work"))

    work = Enum.find(folders, &(&1.name == "Work"))
    titles = SecretsVault.list_items(work.id) |> Enum.map(& &1.title)
    assert "GitHub" in titles

    github = Enum.find(SecretsVault.list_items(work.id), &(&1.title == "GitHub"))
    assert {:ok, "s3cret"} = SecretsVault.decrypt_item_body(github, @password)
    assert {:ok, fm} = SecretsVault.decrypt_item_frontmatter(github, @password)
    assert fm["username"] == "octocat"
    assert fm["totp"] =~ "otpauth://"
  end

  test "keep_as_new renames duplicates instead of overwriting" do
    json = File.read!(@fixture)
    assert {:ok, preview} = ManagerImport.preview_bitwarden_export(json)
    assert {:ok, _} = ManagerImport.import_normalized(preview.import_data, :all, @password)

    assert {:ok, preview2} = ManagerImport.preview_bitwarden_export(json)
    assert preview2.duplicate_count >= 1
    assert Enum.any?(preview2.duplicates, &(&1.import_title == "GitHub"))

    assert {:ok, result} =
             ManagerImport.import_normalized(preview2.import_data, :all, @password,
               duplicate_strategy: :keep_as_new
             )

    assert result.overwritten == 0
    assert result.created == 6

    work = Enum.find(SecretsVault.list_folders(), &(&1.name == "Work"))
    titles = SecretsVault.list_items(work.id) |> Enum.map(& &1.title)
    assert "GitHub" in titles
    assert "GitHub (duplicate)" in titles
  end

  test "overwrite updates existing duplicate items via CRDT save" do
    json = File.read!(@fixture)
    assert {:ok, preview} = ManagerImport.preview_bitwarden_export(json)
    assert {:ok, first} = ManagerImport.import_normalized(preview.import_data, :all, @password)

    work = Enum.find(SecretsVault.list_folders(), &(&1.name == "Work"))
    github = Enum.find(SecretsVault.list_items(work.id), &(&1.title == "GitHub"))
    github_id = github.id

    assert {:ok, result} =
             ManagerImport.import_normalized(preview.import_data, :all, @password,
               duplicate_strategy: :overwrite
             )

    assert result.overwritten >= 1
    assert github_id in result.item_ids

    titles = SecretsVault.list_items(work.id) |> Enum.map(& &1.title)
    refute "GitHub (duplicate)" in titles
    assert Enum.count(titles, &(&1 == "GitHub")) == 1

    github = SecretsVault.get_item!(github_id)
    assert {:ok, "s3cret"} = SecretsVault.decrypt_item_body(github, @password)
    assert length(first.item_ids) == 6
  end
end
