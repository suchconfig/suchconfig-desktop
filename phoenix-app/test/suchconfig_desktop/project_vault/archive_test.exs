defmodule SuchConfigDesktop.ProjectVault.ArchiveTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.EnvManager
  alias SuchConfigDesktop.ProjectVault.Archive
  alias SuchConfigDesktop.ProjectVault.Archive.Preview
  alias SuchConfigCore.Security.EnvCrypto

  describe "manifest envelope" do
    test "pack/preview round-trip wraps payload in v2 envelope" do
      password = "archive-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})

      assert {:ok, archive_bin} = Archive.pack([folder.id], password)
      assert is_binary(archive_bin)

      assert {:ok, %Preview{} = preview} = Archive.preview(archive_bin, password)
      assert preview.format == "suchvault"
      assert preview.format_version == 3
      assert preview.folder_count == 1
      assert preview.note_count >= 1
      assert [folder_summary] = preview.folders
      assert folder_summary.name == folder.name
      assert folder_summary.note_count >= 1
    end

    test "preview reads legacy v1 archives transparently" do
      password = "legacy-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})

      legacy_payload = %{
        "version" => 1,
        "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "folders" => [
          %{
            "name" => folder.name,
            "description" => folder.description,
            "tags" => folder.tags,
            "notes" => []
          }
        ]
      }

      {:ok, legacy_bin} = EnvCrypto.pack_archive(password, legacy_payload)

      assert {:ok, %Preview{} = preview} = Archive.preview(legacy_bin, password)
      assert preview.format == "legacy"
      assert preview.format_version == 1
      assert preview.folder_count == 1
    end

    test "preview returns error for bad password" do
      password = "archive-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})

      {:ok, archive_bin} = Archive.pack([folder.id], password)

      assert {:error, _} = Archive.preview(archive_bin, "wrong-password")
    end
  end

  describe "apply_import/4 routing" do
    test ":create_new creates a new folder per archive entry" do
      password = "routing-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})
      {:ok, archive_bin} = Archive.pack([folder.id], password)

      starting_count = length(EnvManager.list_project_folders())

      routing = %{0 => :create_new}

      assert {:ok, summary} =
               Archive.apply_import(archive_bin, password, routing, :duplicate, [])

      assert summary.created == 1
      assert summary.merged == 0
      assert summary.skipped == 0
      assert summary.notes_imported >= 1
      assert length(EnvManager.list_project_folders()) == starting_count + 1
    end

    test ":merge_into imports notes into an existing folder" do
      password = "merge-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})
      {:ok, archive_bin} = Archive.pack([folder.id], password)

      target =
        project_folder_fixture(%{name: "merge-target-#{System.unique_integer([:positive])}"})

      notes_before = length(EnvManager.list_notes_by_folder(target.id))
      folders_before = length(EnvManager.list_project_folders())

      routing = %{0 => {:merge_into, target.id}}

      assert {:ok, summary} =
               Archive.apply_import(archive_bin, password, routing, :duplicate, [])

      assert summary.merged == 1
      assert summary.created == 0
      assert length(EnvManager.list_project_folders()) == folders_before
      assert length(EnvManager.list_notes_by_folder(target.id)) > notes_before
    end

    test ":skip does not import" do
      password = "skip-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})
      {:ok, archive_bin} = Archive.pack([folder.id], password)

      folders_before = length(EnvManager.list_project_folders())

      routing = %{0 => :skip}

      assert {:ok, summary} =
               Archive.apply_import(archive_bin, password, routing, :duplicate, [])

      assert summary.skipped == 1
      assert summary.created == 0
      assert summary.merged == 0
      assert summary.notes_imported == 0
      assert length(EnvManager.list_project_folders()) == folders_before
    end

    test "defaults to :create_new when no routing decision is provided" do
      password = "default-pw"
      folder = project_folder_fixture()
      _ = secure_note_fixture(password, %{folder: folder})
      {:ok, archive_bin} = Archive.pack([folder.id], password)

      folders_before = length(EnvManager.list_project_folders())

      assert {:ok, summary} = Archive.apply_import(archive_bin, password, %{}, :duplicate, [])
      assert summary.created == 1
      assert length(EnvManager.list_project_folders()) == folders_before + 1
    end
  end
end
