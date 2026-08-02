defmodule SuchConfigDesktop.EnvManager do
  import Ecto.Query, warn: false

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.EnvManager.{Note, NoteEntry, ProjectFolder}
  alias SuchConfigCore.Security.EnvCrypto

  def list_project_folders do
    Repo.all(from project_folder in ProjectFolder, order_by: [asc: project_folder.name])
  end

  def search_project_folders(query) do
    pattern = "%#{query}%"

    Repo.all(
      from project_folder in ProjectFolder,
        where:
          ilike(project_folder.name, ^pattern) or ilike(project_folder.description, ^pattern),
        order_by: [asc: project_folder.name]
    )
  end

  def get_project_folder!(id), do: Repo.get!(ProjectFolder, id)

  def get_project_folder_with_notes!(id) do
    ProjectFolder
    |> Repo.get!(id)
    |> Repo.preload(notes: from(note in Note, order_by: [asc: note.title]))
  end

  def create_project_folder(attrs) do
    %ProjectFolder{}
    |> ProjectFolder.changeset(attrs)
    |> Repo.insert()
  end

  def update_project_folder(%ProjectFolder{} = project_folder, attrs) do
    project_folder
    |> ProjectFolder.changeset(attrs)
    |> Repo.update()
  end

  def delete_project_folder(%ProjectFolder{} = project_folder) do
    Repo.delete(project_folder)
  end

  def change_project_folder(%ProjectFolder{} = project_folder, attrs \\ %{}) do
    ProjectFolder.changeset(project_folder, attrs)
  end

  def list_notes do
    Repo.all(from note in Note, order_by: [asc: note.title], preload: [:project_folder])
  end

  def list_notes_by_folder(project_folder_id) do
    Repo.all(
      from note in Note,
        where: note.project_folder_id == ^project_folder_id,
        order_by: [asc: note.title]
    )
  end

  def search_notes(query) do
    pattern = "%#{query}%"

    Repo.all(
      from note in Note,
        where: ilike(note.title, ^pattern),
        order_by: [asc: note.title],
        preload: [:project_folder]
    )
  end

  def get_note!(id), do: Repo.get!(Note, id)

  def get_note_with_entries!(id) do
    Note
    |> Repo.get!(id)
    |> Repo.preload(entries: from(note_entry in NoteEntry, order_by: [asc: note_entry.position]))
  end

  def create_note(attrs) do
    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  def create_secure_note(attrs, password) when is_binary(password) do
    with {:ok, encrypted_attrs} <- encrypt_note_attrs(attrs, password),
         {:ok, note} <- create_note(encrypted_attrs),
         {:ok, _entries} <- upsert_note_entries_secure(note.id, attrs, password) do
      {:ok, note}
    end
  end

  def create_note_without_password(attrs) do
    with {:ok, plain_attrs} <- prepare_plain_note_attrs(attrs),
         {:ok, note} <- create_note(plain_attrs),
         {:ok, _entries} <- upsert_note_entries_plain(note.id, attrs) do
      {:ok, note}
    end
  end

  def update_note(%Note{} = note, attrs) do
    note
    |> Note.changeset(attrs)
    |> Repo.update()
  end

  def update_secure_note(%Note{} = note, attrs, password) when is_binary(password) do
    with {:ok, encrypted_attrs} <- encrypt_note_attrs(attrs, password),
         {:ok, updated_note} <- update_note(note, encrypted_attrs),
         {:ok, _entries} <- upsert_note_entries_secure(updated_note.id, attrs, password) do
      {:ok, updated_note}
    end
  end

  def update_note_without_password(%Note{} = note, attrs) do
    with {:ok, plain_attrs} <- prepare_plain_note_attrs(attrs),
         {:ok, updated_note} <- update_note(note, plain_attrs),
         {:ok, _entries} <- upsert_note_entries_plain(updated_note.id, attrs) do
      {:ok, updated_note}
    end
  end

  def delete_note(%Note{} = note) do
    Repo.delete(note)
  end

  def change_note(%Note{} = note, attrs \\ %{}) do
    Note.changeset(note, attrs)
  end

  def list_note_entries(note_id) do
    Repo.all(
      from note_entry in NoteEntry,
        where: note_entry.note_id == ^note_id,
        order_by: [asc: note_entry.position]
    )
  end

  def list_note_entries_decrypted(note_id, password) when is_binary(password) do
    note_id
    |> list_note_entries()
    |> Enum.map(fn note_entry ->
      if note_entry.encryption_version == 0 do
        with {:ok, value} <- ensure_binary(note_entry.value_encrypted) do
          {:ok, %{note_entry | value_encrypted: nil, value_nonce: nil} |> Map.put(:value, value)}
        end
      else
        with {:ok, payload_json} <- ensure_binary(note_entry.value_encrypted),
             {:ok, value} <- EnvCrypto.decrypt_from_binary(password, payload_json) do
          {:ok, %{note_entry | value_encrypted: nil, value_nonce: nil} |> Map.put(:value, value)}
        end
      end
    end)
    |> collect_results()
  end

  def upsert_note_entries(note_id, entries) when is_list(entries) do
    Repo.transaction(fn ->
      Repo.delete_all(from note_entry in NoteEntry, where: note_entry.note_id == ^note_id)

      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        attrs =
          entry
          |> Map.put(:note_id, note_id)
          |> Map.put_new(:position, idx)

        %NoteEntry{}
        |> NoteEntry.changeset(attrs)
        |> Repo.insert!()
      end)
    end)
  end

  def upsert_note_entries_secure(note_id, attrs, password) when is_binary(password) do
    entries = normalize_entries(attrs)

    Repo.transaction(fn ->
      Repo.delete_all(from note_entry in NoteEntry, where: note_entry.note_id == ^note_id)

      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        key_name = Map.get(entry, :key, "")
        value = Map.get(entry, :value, "")
        is_secret = Map.get(entry, :is_secret, true)
        line_number = Map.get(entry, :line_number)
        value_binary = if is_binary(value), do: value, else: to_string(value)
        {:ok, payload_json} = EnvCrypto.encrypt_to_binary(password, value_binary)

        attrs = %{
          note_id: note_id,
          position: idx,
          key_name: key_name,
          value_encrypted: payload_json,
          value_nonce: <<>>,
          is_secret: is_secret,
          line_number: line_number,
          encryption_version: 1
        }

        %NoteEntry{}
        |> NoteEntry.changeset(attrs)
        |> Repo.insert!()
      end)
    end)
  end

  def upsert_note_entries_plain(note_id, attrs) do
    entries = normalize_entries(attrs)

    Repo.transaction(fn ->
      Repo.delete_all(from note_entry in NoteEntry, where: note_entry.note_id == ^note_id)

      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        key_name = Map.get(entry, :key, "")
        value = Map.get(entry, :value, "")
        is_secret = Map.get(entry, :is_secret, true)
        line_number = Map.get(entry, :line_number)
        value_binary = if is_binary(value), do: value, else: to_string(value)

        attrs = %{
          note_id: note_id,
          position: idx,
          key_name: key_name,
          value_encrypted: value_binary,
          value_nonce: <<>>,
          is_secret: is_secret,
          line_number: line_number,
          encryption_version: 0
        }

        %NoteEntry{}
        |> NoteEntry.changeset(attrs)
        |> Repo.insert!()
      end)
    end)
  end

  def create_note_entry(attrs) do
    %NoteEntry{}
    |> NoteEntry.changeset(attrs)
    |> Repo.insert()
  end

  def update_note_entry(%NoteEntry{} = note_entry, attrs) do
    note_entry
    |> NoteEntry.changeset(attrs)
    |> Repo.update()
  end

  def delete_note_entry(%NoteEntry{} = note_entry) do
    Repo.delete(note_entry)
  end

  def change_note_entry(%NoteEntry{} = note_entry, attrs \\ %{}) do
    NoteEntry.changeset(note_entry, attrs)
  end

  def decrypt_note_raw_content(%Note{} = note, password) when is_binary(password) do
    if note.encryption_version == 0 do
      ensure_binary(note.raw_content_encrypted)
    else
      with {:ok, payload_json} <- ensure_binary(note.raw_content_encrypted),
           {:ok, plaintext} <- EnvCrypto.decrypt_from_binary(password, payload_json) do
        {:ok, plaintext}
      end
    end
  end

  def export_secure_archive(folder_ids, password)
      when is_list(folder_ids) and is_binary(password) do
    folders =
      Repo.all(
        from project_folder in ProjectFolder,
          where: project_folder.id in ^folder_ids,
          order_by: [asc: project_folder.name]
      )
      |> Repo.preload(notes: from(note in Note, order_by: [asc: note.title]))

    notes_by_id =
      folders
      |> Enum.flat_map(& &1.notes)
      |> Enum.map(& &1.id)
      |> then(fn note_ids ->
        Repo.all(
          from note_entry in NoteEntry,
            where: note_entry.note_id in ^note_ids,
            order_by: [asc: note_entry.position]
        )
      end)
      |> Enum.group_by(& &1.note_id)

    archive_payload = %{
      "version" => 1,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "folders" =>
        Enum.map(folders, fn folder ->
          %{
            "name" => folder.name,
            "description" => folder.description,
            "tags" => folder.tags,
            "notes" =>
              Enum.map(folder.notes, fn note ->
                %{
                  "title" => note.title,
                  "note_type" => note.note_type,
                  "encryption_version" => note.encryption_version,
                  "raw_content_encrypted" => note.raw_content_encrypted,
                  "parsed_entries_encrypted" => note.parsed_entries_encrypted,
                  "entries" =>
                    Enum.map(Map.get(notes_by_id, note.id, []), fn entry ->
                      %{
                        "position" => entry.position,
                        "key_name" => entry.key_name,
                        "value_encrypted" => entry.value_encrypted,
                        "is_secret" => entry.is_secret,
                        "line_number" => entry.line_number,
                        "encryption_version" => entry.encryption_version
                      }
                    end)
                }
              end)
          }
        end)
    }

    EnvCrypto.pack_archive(password, archive_payload)
  end

  def import_secure_archive(archive_binary, password, conflict_strategy \\ :duplicate)
      when is_binary(archive_binary) and is_binary(password) do
    with {:ok, decoded} <- EnvCrypto.unpack_archive(password, archive_binary),
         folders when is_list(folders) <- Map.get(decoded, "folders", []) do
      Repo.transaction(fn ->
        Enum.map(folders, fn folder ->
          folder_name = Map.get(folder, "name", "Imported Folder")
          resolved_name = resolve_folder_name(folder_name, conflict_strategy)

          {:ok, created_folder} =
            create_project_folder(%{
              name: resolved_name,
              description: Map.get(folder, "description"),
              tags: Map.get(folder, "tags")
            })

          Enum.each(Map.get(folder, "notes", []), fn note ->
            note_title = Map.get(note, "title", "imported.env")

            {:ok, created_note} =
              create_note(%{
                title: resolve_note_title(created_folder.id, note_title, conflict_strategy),
                note_type: Map.get(note, "note_type", "generic_note"),
                project_folder_id: created_folder.id,
                raw_content_encrypted: Map.get(note, "raw_content_encrypted"),
                parsed_entries_encrypted: Map.get(note, "parsed_entries_encrypted"),
                encryption_version: Map.get(note, "encryption_version", 1)
              })

            entries =
              Enum.map(Map.get(note, "entries", []), fn entry ->
                %{
                  note_id: created_note.id,
                  position: Map.get(entry, "position", 0),
                  key_name: Map.get(entry, "key_name", ""),
                  value_encrypted: Map.get(entry, "value_encrypted"),
                  value_nonce: <<>>,
                  is_secret: Map.get(entry, "is_secret", true),
                  line_number: Map.get(entry, "line_number"),
                  encryption_version: Map.get(entry, "encryption_version", 1)
                }
              end)

            Enum.each(entries, fn entry_attrs ->
              %NoteEntry{} |> NoteEntry.changeset(entry_attrs) |> Repo.insert!()
            end)
          end)

          created_folder
        end)
      end)
    else
      _ -> {:error, :invalid_password_or_archive}
    end
  end

  defp encrypt_note_attrs(attrs, password) do
    raw_content = Map.get(attrs, :raw_content, Map.get(attrs, "raw_content", ""))
    parsed_entries = Map.get(attrs, :parsed_entries, Map.get(attrs, "parsed_entries", []))

    with {:ok, raw_payload_json} <- EnvCrypto.encrypt_to_binary(password, raw_content || ""),
         {:ok, parsed_entries_json} <- Jason.encode(parsed_entries),
         {:ok, parsed_payload_json} <- EnvCrypto.encrypt_to_binary(password, parsed_entries_json) do
      encrypted_attrs =
        attrs
        |> Map.new()
        |> Map.put(:raw_content_encrypted, raw_payload_json)
        |> Map.put(:raw_content_nonce, <<>>)
        |> Map.put(:parsed_entries_encrypted, parsed_payload_json)
        |> Map.put(:parsed_entries_nonce, <<>>)
        |> Map.put(:encryption_version, 1)
        |> Map.put(:security_mode, "global_passkey")
        |> Map.delete(:raw_content)
        |> Map.delete("raw_content")
        |> Map.delete(:parsed_entries)
        |> Map.delete("parsed_entries")
        |> Map.delete(:entries)
        |> Map.delete("entries")

      {:ok, encrypted_attrs}
    end
  end

  defp prepare_plain_note_attrs(attrs) do
    raw_content = Map.get(attrs, :raw_content, Map.get(attrs, "raw_content", ""))
    parsed_entries = Map.get(attrs, :parsed_entries, Map.get(attrs, "parsed_entries", []))

    with {:ok, parsed_entries_json} <- Jason.encode(parsed_entries) do
      plain_attrs =
        attrs
        |> Map.new()
        |> Map.put(:raw_content_encrypted, raw_content || "")
        |> Map.put(:raw_content_nonce, <<>>)
        |> Map.put(:parsed_entries_encrypted, parsed_entries_json)
        |> Map.put(:parsed_entries_nonce, <<>>)
        |> Map.put(:encryption_version, 0)
        |> Map.delete(:raw_content)
        |> Map.delete("raw_content")
        |> Map.delete(:parsed_entries)
        |> Map.delete("parsed_entries")
        |> Map.delete(:entries)
        |> Map.delete("entries")

      {:ok, plain_attrs}
    end
  end

  defp normalize_entries(attrs) do
    entries = Map.get(attrs, :entries, Map.get(attrs, "entries", []))

    Enum.map(entries, fn
      %{"key" => key, "value" => value} = entry ->
        %{
          key: key,
          value: value,
          is_secret: Map.get(entry, "is_secret", true),
          line_number: Map.get(entry, "line_number")
        }

      %{key: _key, value: _value} = entry ->
        %{
          key: Map.get(entry, :key, ""),
          value: Map.get(entry, :value, ""),
          is_secret: Map.get(entry, :is_secret, true),
          line_number: Map.get(entry, :line_number)
        }

      _ ->
        %{key: "", value: "", is_secret: true}
    end)
  end

  defp collect_results(results) do
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, entry} -> entry end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_binary(value) when is_binary(value), do: {:ok, value}
  defp ensure_binary(_), do: {:error, :missing_encrypted_payload}

  defp resolve_folder_name(name, :replace) do
    case Repo.one(from project_folder in ProjectFolder, where: project_folder.name == ^name) do
      nil ->
        name

      existing ->
        Repo.delete!(existing)
        name
    end
  end

  defp resolve_folder_name(name, :keep_existing), do: name

  defp resolve_folder_name(name, _strategy) do
    case Repo.one(from project_folder in ProjectFolder, where: project_folder.name == ^name) do
      nil -> name
      _ -> "#{name}-imported-#{System.unique_integer([:positive])}"
    end
  end

  defp resolve_note_title(project_folder_id, title, :replace) do
    case Repo.one(
           from note in Note,
             where: note.project_folder_id == ^project_folder_id and note.title == ^title
         ) do
      nil ->
        title

      existing ->
        Repo.delete!(existing)
        title
    end
  end

  defp resolve_note_title(_project_folder_id, title, :keep_existing), do: title

  defp resolve_note_title(project_folder_id, title, _strategy) do
    case Repo.one(
           from note in Note,
             where: note.project_folder_id == ^project_folder_id and note.title == ^title
         ) do
      nil -> title
      _ -> "#{title}-imported-#{System.unique_integer([:positive])}"
    end
  end
end
