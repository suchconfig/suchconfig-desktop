defmodule SuchConfigDesktop.ProjectVault.Archive do
  @moduledoc """
  Secure archive format, packing, previewing, and import routing for Project Vault.

  The archive envelope (format_version 3) wraps the legacy v1 payload plus
  optional `vault_items` per folder (CRDT snapshots). Legacy v1 archives
  (top-level `version` key) and v2 envelopes are detected on import and read
  transparently.
  """

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.EnvManager
  alias SuchConfigDesktop.EnvManager.{Note, NoteEntry, ProjectFolder}
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Item
  alias SuchConfigCore.Security.EnvCrypto

  @format "suchvault"
  @format_version 3
  @legacy_payload_version 1

  defmodule Preview do
    @moduledoc """
    Snapshot of a decrypted archive used to render the import preview UI.

    Contains manifest metadata and a list of folder summaries; no DB writes
    happen during preview.
    """

    @type folder_summary :: %{
            index: non_neg_integer(),
            name: String.t(),
            description: String.t() | nil,
            tags: String.t() | nil,
            note_count: non_neg_integer(),
            note_types: %{String.t() => non_neg_integer()},
            notes: [%{title: String.t(), note_type: String.t()}]
          }

    @type t :: %__MODULE__{
            format: String.t(),
            format_version: non_neg_integer(),
            created_at: String.t() | nil,
            creator: map(),
            folders: [folder_summary()],
            folder_count: non_neg_integer(),
            note_count: non_neg_integer()
          }

    defstruct format: nil,
              format_version: nil,
              created_at: nil,
              creator: %{},
              folders: [],
              folder_count: 0,
              note_count: 0
  end

  @doc """
  Default format id for the envelope (`"suchvault"`).
  """
  def format, do: @format

  @doc """
  Current envelope format version.
  """
  def format_version, do: @format_version

  @doc """
  Builds a v2 manifest envelope around the v1 data payload for the given
  folder ids. Pure function aside from the underlying DB read.
  """
  def build_envelope(folder_ids) when is_list(folder_ids) do
    payload = build_payload(folder_ids)

    folder_count = length(Map.get(payload, "folders", []))

    note_count =
      payload
      |> Map.get("folders", [])
      |> Enum.reduce(0, fn folder, acc ->
        acc + length(Map.get(folder, "notes", []))
      end)

    %{
      "format" => @format,
      "format_version" => @format_version,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "creator" => %{
        "app" => "SuchConfig Desktop",
        "version" => app_version()
      },
      "contents" => %{
        "folder_count" => folder_count,
        "note_count" => note_count
      },
      "payload" => payload
    }
  end

  @doc """
  Builds and encrypts a `.suchvault` archive. Returns `{:ok, binary}` with the
  encrypted JSON bytes or `{:error, reason}` from the crypto layer.
  """
  def pack(folder_ids, password) when is_list(folder_ids) and is_binary(password) do
    envelope = build_envelope(folder_ids)
    EnvCrypto.pack_archive(password, envelope)
  end

  @doc """
  Decrypts an archive and returns a `Preview` struct describing its contents
  without touching the DB. Handles both the v2 envelope and legacy v1 shape.
  """
  def preview(archive_binary, password)
      when is_binary(archive_binary) and is_binary(password) do
    with {:ok, decoded} <- EnvCrypto.unpack_archive(password, archive_binary),
         {:ok, manifest, payload} <- unwrap(decoded) do
      folders = Map.get(payload, "folders", [])

      folder_summaries =
        folders
        |> Enum.with_index()
        |> Enum.map(fn {folder, index} -> summarize_folder(folder, index) end)

      note_count = folder_summaries |> Enum.map(& &1.note_count) |> Enum.sum()

      {:ok,
       %Preview{
         format: Map.get(manifest, "format", "legacy"),
         format_version: Map.get(manifest, "format_version", @legacy_payload_version),
         created_at: Map.get(manifest, "created_at"),
         creator: Map.get(manifest, "creator", %{}),
         folders: folder_summaries,
         folder_count: length(folder_summaries),
         note_count: note_count
       }}
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_password_or_archive}
    end
  end

  @doc """
  Applies the archive to the database using the provided routing decisions.

  `routing` is a map keyed by archive folder index (0-based) with one of:

    * `:create_new` — create a new project folder using the archive's name
      (conflict_strategy applies for duplicate names)
    * `{:create_new, name}` — create a new project folder with a user-chosen name
    * `{:merge_into, folder_id}` — import notes into an existing folder
    * `:skip` — do not import this folder

  Folders with no routing decision default to `:create_new`.

  Returns `{:ok, summary_map}` on success or `{:error, reason}`. The summary
  map includes counts of created / merged / skipped folders and total notes
  imported.
  """
  def apply_import(archive_binary, password, routing, conflict_strategy),
    do: apply_import(archive_binary, password, routing, conflict_strategy, [])

  def apply_import(archive_binary, password, routing, conflict_strategy, opts)
      when is_binary(archive_binary) and is_binary(password) and is_map(routing) and is_list(opts) do
    strategy = normalize_conflict_strategy(conflict_strategy)

    with {:ok, decoded} <- EnvCrypto.unpack_archive(password, archive_binary),
         {:ok, _manifest, payload} <- unwrap(decoded),
         folders when is_list(folders) <- Map.get(payload, "folders", []) do
      Repo.transaction(fn ->
        folders
        |> Enum.with_index()
        |> Enum.reduce(
          %{
            created: 0,
            merged: 0,
            skipped: 0,
            notes_imported: 0,
            vault_items_imported: 0,
            vault_items_merged: 0,
            folders: []
          },
          fn {folder, index}, acc ->
            decision = Map.get(routing, index, :create_new)
            apply_routing(folder, decision, strategy, acc, opts)
          end
        )
      end)
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_password_or_archive}
    end
  end

  defp apply_routing(_folder, :skip, _strategy, acc, _opts) do
    %{acc | skipped: acc.skipped + 1}
  end

  defp apply_routing(folder, :create_new, strategy, acc, opts) do
    create_new_folder(folder, Map.get(folder, "name", "Imported Folder"), strategy, acc, opts)
  end

  defp apply_routing(folder, {:create_new, name}, strategy, acc, opts) do
    name =
      if is_binary(name) and String.trim(name) != "",
        do: name,
        else: Map.get(folder, "name", "Imported Folder")

    create_new_folder(folder, name, strategy, acc, opts)
  end

  defp apply_routing(folder, {:merge_into, folder_id}, strategy, acc, opts)
       when is_integer(folder_id) do
    case Repo.get(ProjectFolder, folder_id) do
      nil ->
        Repo.rollback(:merge_target_missing)

      %ProjectFolder{} = target ->
        notes = Map.get(folder, "notes", [])
        Enum.each(notes, fn note -> import_note(target.id, note, strategy) end)

        {vi, vm} = import_folder_vault_items(target.id, folder, strategy, opts)

        %{
          acc
          | merged: acc.merged + 1,
            notes_imported: acc.notes_imported + length(notes),
            vault_items_imported: acc.vault_items_imported + vi,
            vault_items_merged: acc.vault_items_merged + vm,
            folders: [%{folder_id: target.id, action: :merged} | acc.folders]
        }
    end
  end

  defp apply_routing(folder, _unknown, strategy, acc, opts) do
    apply_routing(folder, :create_new, strategy, acc, opts)
  end

  defp create_new_folder(folder, requested_name, strategy, acc, opts) do
    resolved_name = resolve_folder_name(requested_name, strategy)

    {:ok, created_folder} =
      EnvManager.create_project_folder(%{
        name: resolved_name,
        description: Map.get(folder, "description"),
        tags: Map.get(folder, "tags")
      })

    notes = Map.get(folder, "notes", [])
    Enum.each(notes, fn note -> import_note(created_folder.id, note, strategy) end)

    {vi, vm} = import_folder_vault_items(created_folder.id, folder, strategy, opts)

    %{
      acc
      | created: acc.created + 1,
        notes_imported: acc.notes_imported + length(notes),
        vault_items_imported: acc.vault_items_imported + vi,
        vault_items_merged: acc.vault_items_merged + vm,
        folders: [%{folder_id: created_folder.id, action: :created} | acc.folders]
    }
  end

  defp import_note(folder_id, note, strategy) do
    note_title = Map.get(note, "title", "imported.env")

    {:ok, created_note} =
      EnvManager.create_note(%{
        title: resolve_note_title(folder_id, note_title, strategy),
        note_type: Map.get(note, "note_type", "generic_note"),
        project_folder_id: folder_id,
        raw_content_encrypted: Map.get(note, "raw_content_encrypted"),
        parsed_entries_encrypted: Map.get(note, "parsed_entries_encrypted"),
        encryption_version: Map.get(note, "encryption_version", 1)
      })

    note
    |> Map.get("entries", [])
    |> Enum.each(fn entry ->
      entry_attrs = %{
        note_id: created_note.id,
        position: Map.get(entry, "position", 0),
        key_name: Map.get(entry, "key_name", ""),
        value_encrypted: Map.get(entry, "value_encrypted"),
        value_nonce: <<>>,
        is_secret: Map.get(entry, "is_secret", true),
        line_number: Map.get(entry, "line_number"),
        encryption_version: Map.get(entry, "encryption_version", 1)
      }

      %NoteEntry{}
      |> NoteEntry.changeset(entry_attrs)
      |> Repo.insert!()
    end)
  end

  defp build_payload(folder_ids) do
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

    folder_ids = Enum.map(folders, & &1.id)

    vault_by_folder =
      case folder_ids do
        [] ->
          %{}

        ids ->
          Repo.all(
            from i in Item,
              where: i.project_folder_id in ^ids,
              order_by: [asc: i.title]
          )
          |> Enum.group_by(& &1.project_folder_id)
      end

    %{
      "version" => @legacy_payload_version,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "folders" =>
        Enum.map(folders, fn folder ->
          %{
            "name" => folder.name,
            "description" => folder.description,
            "tags" => folder.tags,
            "vault_items" => encode_vault_items(Map.get(vault_by_folder, folder.id, [])),
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
  end

  defp encode_vault_items(items) do
    Enum.map(items, fn item ->
      blob = item.crdt_snapshot_encrypted || <<>>

      %{
        "title" => item.title,
        "kind" => item.kind,
        "security_mode" => item.security_mode,
        "crdt_snapshot_encrypted" => Base.encode64(blob),
        "crdt_snapshot_hash" => item.crdt_snapshot_hash,
        "crdt_encryption_version" => item.crdt_encryption_version,
        "crdt_schema_version" => item.crdt_schema_version
      }
    end)
  end

  defp import_folder_vault_items(folder_id, folder_map, strategy, opts) do
    items = Map.get(folder_map, "vault_items", []) || []
    vault_password = Keyword.get(opts, :vault_password)

    Enum.reduce(items, {0, 0}, fn entry, {imported, merged} ->
      case import_one_vault_item(folder_id, entry, strategy, vault_password) do
        {:ok, :inserted} -> {imported + 1, merged}
        {:ok, :merged} -> {imported, merged + 1}
        _ -> {imported, merged}
      end
    end)
  end

  defp import_one_vault_item(folder_id, entry, strategy, vault_password) do
    title = Map.get(entry, "title", "Untitled") |> to_string() |> String.trim()
    title = if title == "", do: "Untitled", else: title

    case decode_vault_snapshot(entry) do
      {:ok, enc_remote} ->
        case Repo.get_by(Item, project_folder_id: folder_id, title: title) do
          %Item{} = local when is_binary(vault_password) and vault_password != "" ->
            try_merge_vault_item(local, enc_remote, vault_password)

          %Item{} ->
            rt = resolve_vault_item_title(folder_id, title, strategy)
            do_insert_vault_item(folder_id, Map.put(entry, "title", rt), enc_remote)

          nil ->
            rt = resolve_vault_item_title(folder_id, title, strategy)
            do_insert_vault_item(folder_id, Map.put(entry, "title", rt), enc_remote)
        end

      other ->
        other
    end
  end

  defp decode_vault_snapshot(entry) do
    case Map.get(entry, "crdt_snapshot_encrypted") do
      b64 when is_binary(b64) ->
        case Base.decode64(b64) do
          {:ok, bin} -> {:ok, bin}
          :error -> {:error, :bad_base64}
        end

      _ ->
        {:error, :missing}
    end
  end

  defp try_merge_vault_item(%Item{} = local, enc_remote, vault_password) do
    cond do
      not Crdt.available?() ->
        rt =
          resolve_vault_item_title(
            local.project_folder_id,
            "#{local.title}-imported",
            :duplicate
          )

        do_insert_vault_item(local.project_folder_id, %{"title" => rt}, enc_remote)

      true ->
        with {:ok, local_plain} <-
               EnvCrypto.decrypt_from_binary(vault_password, local.crdt_snapshot_encrypted),
             {:ok, remote_plain} <- EnvCrypto.decrypt_from_binary(vault_password, enc_remote),
             {:ok, delta} <- Crdt.diff_from(remote_plain, local_plain),
             {:ok, merged_plain, _summary} <- Crdt.apply_update(local_plain, delta),
             {:ok, hash} <- Crdt.snapshot_hash(merged_plain),
             {:ok, new_enc} <- EnvCrypto.encrypt_to_binary(vault_password, merged_plain) do
          local
          |> Item.changeset(%{
            crdt_snapshot_encrypted: new_enc,
            crdt_snapshot_hash: hash,
            crdt_encryption_version: 1,
            crdt_schema_version: 1,
            updated_clock: System.system_time(:millisecond)
          })
          |> Repo.update()
          |> case do
            {:ok, _} -> {:ok, :merged}
            _ -> {:error, :update_failed}
          end
        else
          _ ->
            alt = "#{local.title}-imported-#{System.unique_integer([:positive])}"
            do_insert_vault_item(local.project_folder_id, %{"title" => alt}, enc_remote)
        end
    end
  end

  defp do_insert_vault_item(folder_id, entry, enc_remote) do
    title = Map.get(entry, "title", "item") |> to_string() |> String.trim()
    title = if title == "", do: "item", else: title

    attrs = %{
      title: title,
      kind: Map.get(entry, "kind", "generic_note"),
      security_mode: Map.get(entry, "security_mode", "global_passkey"),
      project_folder_id: folder_id,
      crdt_snapshot_encrypted: enc_remote,
      crdt_snapshot_nonce: nil,
      crdt_encryption_version: Map.get(entry, "crdt_encryption_version", 1),
      crdt_schema_version: Map.get(entry, "crdt_schema_version", 1),
      crdt_snapshot_hash: Map.get(entry, "crdt_snapshot_hash", ""),
      updated_clock: System.system_time(:millisecond)
    }

    case %Item{} |> Item.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> {:ok, :inserted}
      {:error, _} -> {:error, :insert_failed}
    end
  end

  defp resolve_vault_item_title(folder_id, title, :replace) do
    case Repo.one(from i in Item, where: i.project_folder_id == ^folder_id and i.title == ^title) do
      nil ->
        title

      existing ->
        Repo.delete!(existing)
        title
    end
  end

  defp resolve_vault_item_title(_folder_id, title, :keep_existing), do: title

  defp resolve_vault_item_title(folder_id, title, _strategy) do
    case Repo.one(from i in Item, where: i.project_folder_id == ^folder_id and i.title == ^title) do
      nil -> title
      _ -> "#{title}-imported-#{System.unique_integer([:positive])}"
    end
  end

  defp unwrap(%{"format" => @format, "payload" => payload} = manifest) when is_map(payload) do
    {:ok, manifest, payload}
  end

  defp unwrap(%{"version" => version} = payload) when is_integer(version) do
    manifest = %{
      "format" => "legacy",
      "format_version" => version,
      "created_at" => Map.get(payload, "exported_at"),
      "creator" => %{},
      "contents" => %{}
    }

    {:ok, manifest, payload}
  end

  defp unwrap(_), do: {:error, :invalid_password_or_archive}

  defp summarize_folder(folder, index) do
    notes = Map.get(folder, "notes", [])

    note_types =
      notes
      |> Enum.map(&Map.get(&1, "note_type", "generic_note"))
      |> Enum.frequencies()

    summaries =
      Enum.map(notes, fn note ->
        %{
          title: Map.get(note, "title", "(untitled)"),
          note_type: Map.get(note, "note_type", "generic_note")
        }
      end)

    %{
      index: index,
      name: Map.get(folder, "name", "(unnamed)"),
      description: Map.get(folder, "description"),
      tags: Map.get(folder, "tags"),
      note_count: length(notes),
      note_types: note_types,
      notes: summaries
    }
  end

  defp resolve_folder_name(name, :replace) do
    case Repo.one(from f in ProjectFolder, where: f.name == ^name) do
      nil ->
        name

      existing ->
        Repo.delete!(existing)
        name
    end
  end

  defp resolve_folder_name(name, :keep_existing), do: name

  defp resolve_folder_name(name, _strategy) do
    case Repo.one(from f in ProjectFolder, where: f.name == ^name) do
      nil -> name
      _ -> "#{name}-imported-#{System.unique_integer([:positive])}"
    end
  end

  defp resolve_note_title(folder_id, title, :replace) do
    case Repo.one(
           from n in Note,
             where: n.project_folder_id == ^folder_id and n.title == ^title
         ) do
      nil ->
        title

      existing ->
        Repo.delete!(existing)
        title
    end
  end

  defp resolve_note_title(_folder_id, title, :keep_existing), do: title

  defp resolve_note_title(folder_id, title, _strategy) do
    case Repo.one(
           from n in Note,
             where: n.project_folder_id == ^folder_id and n.title == ^title
         ) do
      nil -> title
      _ -> "#{title}-imported-#{System.unique_integer([:positive])}"
    end
  end

  defp normalize_conflict_strategy(:duplicate), do: :duplicate
  defp normalize_conflict_strategy(:keep_existing), do: :keep_existing
  defp normalize_conflict_strategy(:replace), do: :replace

  defp normalize_conflict_strategy(s) when is_binary(s) do
    case s do
      "duplicate" -> :duplicate
      "keep_existing" -> :keep_existing
      "replace" -> :replace
      _ -> :duplicate
    end
  end

  defp normalize_conflict_strategy(_), do: :duplicate

  defp app_version do
    case Application.spec(:suchconfig_desktop, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end
end
