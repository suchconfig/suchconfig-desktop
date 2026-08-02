defmodule SuchConfigDesktop.EnvManagerFixtures do
  def project_folder_fixture(attrs \\ %{}) do
    {:ok, folder} =
      attrs
      |> Enum.into(%{
        name: "project-#{System.unique_integer([:positive])}",
        description: "test folder",
        tags: "test"
      })
      |> SuchConfigDesktop.EnvManager.create_project_folder()

    folder
  end

  def secure_note_fixture(password, attrs \\ %{}) do
    folder = Map.get(attrs, :folder) || project_folder_fixture()

    note_attrs =
      attrs
      |> Map.delete(:folder)
      |> Enum.into(%{
        title: "staging.env",
        project_folder_id: folder.id,
        raw_content: "DATABASE_URL=postgres://localhost\nAPI_KEY=abc123",
        parsed_entries: [
          %{key: "DATABASE_URL", value: "postgres://localhost", is_secret: true, line_number: 1},
          %{key: "API_KEY", value: "abc123", is_secret: true, line_number: 2}
        ],
        entries: [
          %{key: "DATABASE_URL", value: "postgres://localhost", is_secret: true, line_number: 1},
          %{key: "API_KEY", value: "abc123", is_secret: true, line_number: 2}
        ]
      })

    {:ok, note} = SuchConfigDesktop.EnvManager.create_secure_note(note_attrs, password)
    note
  end
end
