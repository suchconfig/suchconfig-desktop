defmodule SuchConfigDesktop.EnvManagerTest do
  use SuchConfigDesktop.DataCase

  alias SuchConfigDesktop.EnvManager

  import SuchConfigDesktop.EnvManagerFixtures

  describe "project folders" do
    test "create and list folders" do
      folder = project_folder_fixture()
      folders = EnvManager.list_project_folders()

      assert Enum.any?(folders, &(&1.id == folder.id))
    end
  end

  describe "secure notes" do
    test "create_secure_note and decrypt_note_raw_content roundtrip" do
      password = "vault-password"
      folder = project_folder_fixture()

      attrs = %{
        title: "dev.env",
        project_folder_id: folder.id,
        raw_content: "FOO=bar\nTOKEN=abc",
        parsed_entries: [
          %{key: "FOO", value: "bar", is_secret: false, line_number: 1},
          %{key: "TOKEN", value: "abc", is_secret: true, line_number: 2}
        ],
        entries: [
          %{key: "FOO", value: "bar", is_secret: false, line_number: 1},
          %{key: "TOKEN", value: "abc", is_secret: true, line_number: 2}
        ]
      }

      assert {:ok, note} = EnvManager.create_secure_note(attrs, password)
      assert {:ok, raw_content} = EnvManager.decrypt_note_raw_content(note, password)
      assert raw_content == "FOO=bar\nTOKEN=abc"
    end

    test "list_note_entries_decrypted returns decrypted values" do
      password = "entry-password"
      note = secure_note_fixture(password)

      assert {:ok, entries} = EnvManager.list_note_entries_decrypted(note.id, password)
      assert Enum.any?(entries, &(Map.get(&1, :value) == "abc123"))
    end
  end

  describe "secure archive" do
    test "export and import archive roundtrip" do
      password = "archive-password"
      folder = project_folder_fixture(%{name: "archive-source"})

      _note =
        secure_note_fixture(password, %{
          folder: folder,
          title: "prod.env"
        })

      assert {:ok, archive} = EnvManager.export_secure_archive([folder.id], password)

      assert {:ok, imported_folders} =
               EnvManager.import_secure_archive(archive, password, :duplicate)

      assert length(imported_folders) == 1
      assert hd(imported_folders).name != ""
    end
  end
end
