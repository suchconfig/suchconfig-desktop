defmodule SuchConfigDesktop.TrustedFolder do
  @moduledoc """
  Trusted Folder sync bundles for Tauri `.loro.enc` export/import.
  """

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.EnvManager.ProjectFolder
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.Folder, as: SecretsFolder
  alias SuchConfigDesktop.SecretsVault.Item, as: SecretsItem
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Item, as: ProjectItem
  alias SuchConfigCore.Security.EnvCrypto

  @bundle_format "suchconfig_trusted_sync"
  @handoff_format "suchconfig_handoff_sync"
  @bundle_version 1

  def display_path(nil), do: nil

  def display_path(path) when is_binary(path) do
    path
    |> String.trim()
    |> then(fn p ->
      case System.get_env("HOME") do
        home when is_binary(home) and home != "" -> String.replace_prefix(p, home, "~")
        _ -> p
      end
    end)
  end

  def configured?(nil), do: false
  def configured?(""), do: false
  def configured?(path) when is_binary(path), do: String.trim(path) != ""
  def configured?(_), do: false

  def export_bundle(:projects) do
    folders =
      Repo.all(
        from f in ProjectFolder,
          order_by: [asc: f.name]
      )

    items =
      Repo.all(
        from i in ProjectItem,
          order_by: [asc: i.project_folder_id, asc: i.title]
      )

    encode_projects_bundle(
      Enum.map(folders, &project_folder_payload/1),
      Enum.map(items, &project_item_payload/1)
    )
  end

  def export_bundle(:secrets) do
    folders =
      Repo.all(
        from f in SecretsFolder,
          order_by: [asc: f.name]
      )

    items =
      Repo.all(
        from i in SecretsItem,
          order_by: [asc: i.secrets_vault_folder_id, asc: i.title]
      )

    encode_secrets_bundle(
      Enum.map(folders, &secrets_folder_payload/1),
      Enum.map(items, &secrets_item_payload/1)
    )
  end

  def import_bundle(binary, :projects) when is_binary(binary) do
    with {:ok, %{"vault" => "projects"} = decoded} <- Jason.decode(binary),
         folders <- Map.get(decoded, "folders", []),
         items <- Map.get(decoded, "items", []),
         {:ok, folder_id_map} <- import_project_folders(folders),
         {:ok, item_stats} <- import_project_items(items, folder_id_map),
         {:ok, pruned} <- prune_projects_snapshot(folders, items, folder_id_map) do
      {:ok, merge_import_stats(item_stats, pruned)}
    else
      {:ok, _} -> {:error, :invalid_bundle}
      {:error, _} = err -> err
    end
  end

  def import_bundle(binary, :secrets) when is_binary(binary) do
    with {:ok, %{"vault" => "secrets"} = decoded} <- Jason.decode(binary),
         folders <- Map.get(decoded, "folders", []),
         items <- Map.get(decoded, "items", []),
         {:ok, folder_id_map} <- import_secrets_folders(folders),
         {:ok, item_stats} <- import_secrets_items(items, folder_id_map),
         {:ok, pruned} <- prune_secrets_snapshot(items, folder_id_map) do
      {:ok, merge_import_stats(item_stats, pruned)}
    else
      {:ok, _} -> {:error, :invalid_bundle}
      {:error, _} = err -> err
    end
  end

  def export_handoff_bundle(:projects, export_password)
      when is_binary(export_password) and export_password != "" do
    folders =
      Repo.all(
        from f in ProjectFolder,
          order_by: [asc: f.name]
      )

    items =
      Repo.all(
        from i in ProjectItem,
          order_by: [asc: i.project_folder_id, asc: i.title]
      )

    item_payloads =
      Enum.flat_map(items, fn item ->
        case handoff_project_item_payload(item, export_password) do
          {:ok, payload} -> [payload]
          _ -> []
        end
      end)

    encode_handoff_projects_bundle(
      Enum.map(folders, &project_folder_payload/1),
      item_payloads
    )
  end

  def export_handoff_bundle(:secrets, export_password)
      when is_binary(export_password) and export_password != "" do
    folders =
      Repo.all(
        from f in SecretsFolder,
          order_by: [asc: f.name]
      )

    items =
      Repo.all(
        from i in SecretsItem,
          order_by: [asc: i.secrets_vault_folder_id, asc: i.title]
      )

    item_payloads =
      Enum.flat_map(items, fn item ->
        case handoff_secrets_item_payload(item, export_password) do
          {:ok, payload} -> [payload]
          _ -> []
        end
      end)

    encode_handoff_secrets_bundle(
      Enum.map(folders, &secrets_folder_payload/1),
      item_payloads
    )
  end

  def export_handoff_bundle(_, _), do: {:error, :invalid_password}

  def import_handoff_bundle(binary, :projects, import_password)
      when is_binary(binary) and is_binary(import_password) and import_password != "" do
    with {:ok, %{"format" => @handoff_format, "vault" => "projects"} = decoded} <-
           Jason.decode(binary),
         folders <- Map.get(decoded, "folders", []),
         items <- Map.get(decoded, "items", []),
         {:ok, folder_id_map} <- import_project_folders(folders),
         {:ok, item_stats} <- import_project_items_handoff(items, folder_id_map, import_password),
         {:ok, pruned} <- prune_projects_snapshot(folders, items, folder_id_map) do
      {:ok, merge_import_stats(item_stats, pruned)}
    else
      {:ok, _} -> {:error, :invalid_bundle}
      {:error, _} = err -> err
    end
  end

  def import_handoff_bundle(binary, :secrets, import_password)
      when is_binary(binary) and is_binary(import_password) and import_password != "" do
    with {:ok, %{"format" => @handoff_format, "vault" => "secrets"} = decoded} <-
           Jason.decode(binary),
         folders <- Map.get(decoded, "folders", []),
         items <- Map.get(decoded, "items", []),
         {:ok, folder_id_map} <- import_secrets_folders(folders),
         {:ok, item_stats} <- import_secrets_items_handoff(items, folder_id_map, import_password),
         {:ok, pruned} <- prune_secrets_snapshot(items, folder_id_map) do
      {:ok, merge_import_stats(item_stats, pruned)}
    else
      {:ok, _} -> {:error, :invalid_bundle}
      {:error, _} = err -> err
    end
  end

  def import_handoff_bundle(_, _, _), do: {:error, :invalid_password}

  def vault_atom("projects"), do: :projects
  def vault_atom("secrets"), do: :secrets
  def vault_atom(_), do: nil

  defp encode_projects_bundle(folders, items) do
    payload = %{
      "format" => @bundle_format,
      "format_version" => @bundle_version,
      "vault" => "projects",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "folders" => folders,
      "items" => items
    }

    {:ok, Jason.encode!(payload)}
  end

  defp encode_secrets_bundle(folders, items) do
    payload = %{
      "format" => @bundle_format,
      "format_version" => @bundle_version,
      "vault" => "secrets",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "folders" => folders,
      "items" => items
    }

    {:ok, Jason.encode!(payload)}
  end

  defp encode_handoff_projects_bundle(folders, items) do
    payload = %{
      "format" => @handoff_format,
      "format_version" => @bundle_version,
      "vault" => "projects",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "folders" => folders,
      "items" => items
    }

    {:ok, Jason.encode!(payload)}
  end

  defp encode_handoff_secrets_bundle(folders, items) do
    payload = %{
      "format" => @handoff_format,
      "format_version" => @bundle_version,
      "vault" => "secrets",
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "folders" => folders,
      "items" => items
    }

    {:ok, Jason.encode!(payload)}
  end

  defp secrets_folder_payload(%SecretsFolder{} = folder) do
    %{
      "id" => folder.id,
      "name" => folder.name,
      "description" => folder.description
    }
  end

  defp project_folder_payload(%ProjectFolder{} = folder) do
    %{
      "id" => folder.id,
      "name" => folder.name,
      "description" => folder.description,
      "tags" => folder.tags,
      "linked_project_path" => folder.linked_project_path,
      "linked_sync_enabled" => folder.linked_sync_enabled,
      "linked_auto_sync" => folder.linked_auto_sync
    }
  end

  defp project_item_payload(%ProjectItem{} = item) do
    %{
      "title" => item.title,
      "kind" => item.kind,
      "security_mode" => item.security_mode,
      "project_folder_id" => item.project_folder_id,
      "crdt_snapshot_encrypted" => Base.encode64(item.crdt_snapshot_encrypted || <<>>),
      "crdt_snapshot_hash" => item.crdt_snapshot_hash,
      "crdt_encryption_version" => item.crdt_encryption_version,
      "crdt_schema_version" => item.crdt_schema_version
    }
  end

  defp secrets_item_payload(%SecretsItem{} = item) do
    %{
      "title" => item.title,
      "kind" => item.kind,
      "security_mode" => item.security_mode,
      "secrets_vault_folder_id" => item.secrets_vault_folder_id,
      "crdt_snapshot_encrypted" => Base.encode64(item.crdt_snapshot_encrypted || <<>>),
      "crdt_snapshot_hash" => item.crdt_snapshot_hash,
      "crdt_encryption_version" => item.crdt_encryption_version,
      "crdt_schema_version" => item.crdt_schema_version
    }
  end

  defp handoff_project_item_payload(%ProjectItem{} = item, export_password) do
    with enc when is_binary(enc) and enc != "" <- item.crdt_snapshot_encrypted,
         {:ok, plain} <- EnvCrypto.decrypt_from_binary(export_password, enc),
         {:ok, hash} <- Crdt.snapshot_hash(plain) do
      {:ok,
       %{
         "title" => item.title,
         "kind" => item.kind,
         "security_mode" => item.security_mode,
         "project_folder_id" => item.project_folder_id,
         "crdt_snapshot_plain_b64" => Base.encode64(plain),
         "crdt_snapshot_hash" => hash,
         "crdt_encryption_version" => item.crdt_encryption_version,
         "crdt_schema_version" => item.crdt_schema_version
       }}
    else
      _ -> :error
    end
  end

  defp handoff_secrets_item_payload(%SecretsItem{} = item, export_password) do
    with enc when is_binary(enc) and enc != "" <- item.crdt_snapshot_encrypted,
         {:ok, plain} <- EnvCrypto.decrypt_from_binary(export_password, enc),
         {:ok, hash} <- Crdt.snapshot_hash(plain) do
      {:ok,
       %{
         "title" => item.title,
         "kind" => item.kind,
         "security_mode" => item.security_mode,
         "secrets_vault_folder_id" => item.secrets_vault_folder_id,
         "crdt_snapshot_plain_b64" => Base.encode64(plain),
         "crdt_snapshot_hash" => hash,
         "crdt_encryption_version" => item.crdt_encryption_version,
         "crdt_schema_version" => item.crdt_schema_version
       }}
    else
      _ -> :error
    end
  end

  defp import_project_folders(folders) when is_list(folders) do
    folder_id_map =
      Enum.reduce(folders, %{}, fn folder_map, acc ->
        case upsert_project_folder(folder_map) do
          {:ok, folder, exported_id} when is_integer(exported_id) ->
            Map.put(acc, exported_id, folder.id)

          _ ->
            acc
        end
      end)

    {:ok, folder_id_map}
  end

  defp import_project_items(items, folder_id_map) when is_list(items) do
    {:ok, tally_import_items(items, &upsert_project_item(&1, folder_id_map))}
  end

  defp import_project_items_handoff(items, folder_id_map, import_password)
       when is_list(items) and is_map(folder_id_map) and is_binary(import_password) do
    {:ok,
     tally_import_items(items, &upsert_project_item_handoff(&1, folder_id_map, import_password))}
  end

  defp import_secrets_folders(folders) when is_list(folders) do
    _ = SecretsVault.ensure_unassociated_folder()

    folder_id_map =
      Enum.reduce(folders, %{}, fn folder_map, acc ->
        case upsert_secrets_folder(folder_map) do
          {:ok, folder, exported_id} when is_integer(exported_id) ->
            Map.put(acc, exported_id, folder.id)

          _ ->
            acc
        end
      end)

    {:ok, folder_id_map}
  end

  defp import_secrets_items(items, folder_id_map) when is_list(items) do
    {:ok, tally_import_items(items, &upsert_secrets_item(&1, folder_id_map))}
  end

  defp import_secrets_items_handoff(items, folder_id_map, import_password)
       when is_list(items) and is_map(folder_id_map) and is_binary(import_password) do
    {:ok,
     tally_import_items(items, &upsert_secrets_item_handoff(&1, folder_id_map, import_password))}
  end

  defp tally_import_items(items, upsert_fun) when is_list(items) and is_function(upsert_fun, 1) do
    Enum.reduce(items, %{upserted: 0, skipped: 0}, fn map, acc ->
      case import_item_safely(fn -> upsert_fun.(map) end) do
        {:ok, _} ->
          Map.update!(acc, :upserted, &(&1 + 1))

        _ ->
          Map.update!(acc, :skipped, &(&1 + 1))
      end
    end)
  end

  defp import_item_safely(fun) when is_function(fun, 0) do
    fun.()
  rescue
    Ecto.ConstraintError -> {:error, :constraint}
  end

  defp upsert_project_folder(map) when is_map(map) do
    name = map["name"]
    exported_id = map["id"]

    if is_binary(name) and String.trim(name) != "" do
      attrs = %{
        name: String.trim(name),
        description: Map.get(map, "description"),
        tags: Map.get(map, "tags"),
        linked_project_path: Map.get(map, "linked_project_path"),
        linked_sync_enabled: Map.get(map, "linked_sync_enabled", false),
        linked_auto_sync: Map.get(map, "linked_auto_sync", false)
      }

      existing =
        Repo.one(
          from f in ProjectFolder,
            where: f.name == ^attrs.name,
            limit: 1
        )

      result =
        case existing do
          nil ->
            %ProjectFolder{}
            |> ProjectFolder.changeset(attrs)
            |> Repo.insert()

          %ProjectFolder{} = folder ->
            folder
            |> ProjectFolder.changeset(attrs)
            |> Repo.update()
        end

      case result do
        {:ok, folder} -> {:ok, folder, exported_id}
        {:error, _} = err -> err
      end
    else
      {:error, :invalid_folder}
    end
  end

  defp upsert_project_item_handoff(map, folder_id_map, import_password)
       when is_map(map) and is_map(folder_id_map) and is_binary(import_password) do
    exported_folder_id = map["project_folder_id"]
    folder_id = Map.get(folder_id_map, exported_folder_id, exported_folder_id)
    title = map["title"]
    plain = decode_blob(Map.get(map, "crdt_snapshot_plain_b64"))

    if is_integer(folder_id) and is_binary(title) and title != "" and is_binary(plain) and
         plain != "" do
      with {:ok, enc} <- EnvCrypto.encrypt_to_binary(import_password, plain),
           {:ok, hash} <- Crdt.snapshot_hash(plain) do
        existing =
          Repo.one(
            from i in ProjectItem,
              where: i.project_folder_id == ^folder_id and i.title == ^title,
              limit: 1
          )

        attrs = %{
          title: title,
          kind: Map.get(map, "kind", "generic_note"),
          security_mode: Map.get(map, "security_mode", "global_passkey"),
          project_folder_id: folder_id,
          crdt_snapshot_encrypted: enc,
          crdt_snapshot_hash: hash,
          crdt_encryption_version: Map.get(map, "crdt_encryption_version", 1),
          crdt_schema_version: Map.get(map, "crdt_schema_version", 1)
        }

        case existing do
          nil ->
            %ProjectItem{}
            |> ProjectItem.changeset(attrs)
            |> Repo.insert()

          %ProjectItem{} = item ->
            item
            |> ProjectItem.changeset(attrs)
            |> Repo.update()
        end
      else
        _ -> {:error, :invalid_item}
      end
    else
      {:error, :invalid_item}
    end
  end

  defp upsert_project_item(map, folder_id_map) when is_map(map) and is_map(folder_id_map) do
    exported_folder_id = map["project_folder_id"]
    folder_id = Map.get(folder_id_map, exported_folder_id, exported_folder_id)
    title = map["title"]
    enc = decode_blob(Map.get(map, "crdt_snapshot_encrypted"))

    if is_integer(folder_id) and is_binary(title) and title != "" and enc != nil do
      existing =
        Repo.one(
          from i in ProjectItem,
            where: i.project_folder_id == ^folder_id and i.title == ^title,
            limit: 1
        )

      attrs = %{
        title: title,
        kind: Map.get(map, "kind", "generic_note"),
        security_mode: Map.get(map, "security_mode", "global_passkey"),
        project_folder_id: folder_id,
        crdt_snapshot_encrypted: enc,
        crdt_snapshot_hash: Map.get(map, "crdt_snapshot_hash"),
        crdt_encryption_version: Map.get(map, "crdt_encryption_version", 1),
        crdt_schema_version: Map.get(map, "crdt_schema_version", 1)
      }

      case existing do
        nil ->
          %ProjectItem{}
          |> ProjectItem.changeset(attrs)
          |> Repo.insert()

        %ProjectItem{} = item ->
          item
          |> ProjectItem.changeset(attrs)
          |> Repo.update()
      end
    else
      {:error, :invalid_item}
    end
  end

  defp upsert_secrets_folder(map) when is_map(map) do
    name = map["name"]
    exported_id = map["id"]

    if is_binary(name) and String.trim(name) != "" do
      attrs = %{
        name: String.trim(name),
        description: Map.get(map, "description")
      }

      existing =
        Repo.one(
          from f in SecretsFolder,
            where: f.name == ^attrs.name,
            limit: 1
        )

      result =
        case existing do
          nil ->
            %SecretsFolder{}
            |> SecretsFolder.changeset(attrs)
            |> Repo.insert()

          %SecretsFolder{} = folder ->
            folder
            |> SecretsFolder.changeset(attrs)
            |> Repo.update()
        end

      case result do
        {:ok, folder} -> {:ok, folder, exported_id}
        {:error, _} = err -> err
      end
    else
      {:error, :invalid_folder}
    end
  end

  defp upsert_secrets_item_handoff(map, folder_id_map, import_password)
       when is_map(map) and is_map(folder_id_map) and is_binary(import_password) do
    exported_folder_id = map["secrets_vault_folder_id"]
    folder_id = resolve_secrets_folder_id(exported_folder_id, folder_id_map)
    title = map["title"]
    plain = decode_blob(Map.get(map, "crdt_snapshot_plain_b64"))

    if is_integer(folder_id) and is_binary(title) and title != "" and is_binary(plain) and
         plain != "" do
      with {:ok, enc} <- EnvCrypto.encrypt_to_binary(import_password, plain),
           {:ok, hash} <- Crdt.snapshot_hash(plain) do
        existing =
          Repo.one(
            from i in SecretsItem,
              where: i.secrets_vault_folder_id == ^folder_id and i.title == ^title,
              limit: 1
          )

        attrs = %{
          title: title,
          kind: Map.get(map, "kind", "password"),
          security_mode: Map.get(map, "security_mode", "global_passkey"),
          secrets_vault_folder_id: folder_id,
          crdt_snapshot_encrypted: enc,
          crdt_snapshot_hash: hash,
          crdt_encryption_version: Map.get(map, "crdt_encryption_version", 1),
          crdt_schema_version: Map.get(map, "crdt_schema_version", 1)
        }

        case existing do
          nil ->
            %SecretsItem{}
            |> SecretsItem.changeset(attrs)
            |> Repo.insert()

          %SecretsItem{} = item ->
            item
            |> SecretsItem.changeset(attrs)
            |> Repo.update()
        end
      else
        _ -> {:error, :invalid_item}
      end
    else
      {:error, :invalid_item}
    end
  end

  defp upsert_secrets_item(map, folder_id_map) when is_map(map) and is_map(folder_id_map) do
    exported_folder_id = map["secrets_vault_folder_id"]
    folder_id = resolve_secrets_folder_id(exported_folder_id, folder_id_map)
    title = map["title"]
    enc = decode_blob(Map.get(map, "crdt_snapshot_encrypted"))

    if is_integer(folder_id) and is_binary(title) and title != "" and enc != nil do
      existing =
        Repo.one(
          from i in SecretsItem,
            where: i.secrets_vault_folder_id == ^folder_id and i.title == ^title,
            limit: 1
        )

      attrs = %{
        title: title,
        kind: Map.get(map, "kind", "password"),
        security_mode: Map.get(map, "security_mode", "global_passkey"),
        secrets_vault_folder_id: folder_id,
        crdt_snapshot_encrypted: enc,
        crdt_snapshot_hash: Map.get(map, "crdt_snapshot_hash"),
        crdt_encryption_version: Map.get(map, "crdt_encryption_version", 1),
        crdt_schema_version: Map.get(map, "crdt_schema_version", 1)
      }

      case existing do
        nil ->
          %SecretsItem{}
          |> SecretsItem.changeset(attrs)
          |> Repo.insert()

        %SecretsItem{} = item ->
          item
          |> SecretsItem.changeset(attrs)
          |> Repo.update()
      end
    else
      {:error, :invalid_item}
    end
  end

  defp decode_blob(nil), do: nil

  defp decode_blob(b64) when is_binary(b64) do
    case Base.decode64(b64) do
      {:ok, bin} -> bin
      :error -> nil
    end
  end

  defp merge_import_stats(item_stats, pruned) when is_map(item_stats) do
    %{
      upserted: Map.get(item_stats, :upserted, 0),
      skipped: Map.get(item_stats, :skipped, 0),
      deleted_folders: Map.get(pruned, :deleted_folders, 0),
      deleted_items: Map.get(pruned, :deleted_items, 0)
    }
  end

  defp resolve_secrets_folder_id(exported_folder_id, folder_id_map) when is_map(folder_id_map) do
    case Map.get(folder_id_map, exported_folder_id) do
      id when is_integer(id) ->
        id

      _ when is_integer(exported_folder_id) ->
        case Repo.get(SecretsFolder, exported_folder_id) do
          %SecretsFolder{} = folder -> folder.id
          nil -> unassociated_folder_id()
        end

      _ ->
        unassociated_folder_id()
    end
  end

  defp unassociated_folder_id do
    {:ok, folder} = SecretsVault.ensure_unassociated_folder()
    folder.id
  end

  defp prune_projects_snapshot(folders, items, folder_id_map)
       when is_list(folders) and is_list(items) and is_map(folder_id_map) do
    imported_folder_names =
      folders
      |> Enum.map(&Map.get(&1, "name"))
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
      |> MapSet.new()

    imported_item_keys = imported_project_item_keys(items, folder_id_map)

    deleted_folders =
      Repo.all(from(f in ProjectFolder))
      |> Enum.reduce(0, fn folder, acc ->
        if MapSet.member?(imported_folder_names, folder.name) do
          acc
        else
          Repo.delete!(folder)
          acc + 1
        end
      end)

    deleted_items =
      Repo.all(from(i in ProjectItem))
      |> Enum.reduce(0, fn item, acc ->
        key = {item.project_folder_id, item.title}

        if MapSet.member?(imported_item_keys, key) do
          acc
        else
          Repo.delete!(item)
          acc + 1
        end
      end)

    {:ok, %{deleted_folders: deleted_folders, deleted_items: deleted_items}}
  end

  defp prune_secrets_snapshot(items, folder_id_map)
       when is_list(items) and is_map(folder_id_map) do
    imported_item_keys = imported_secrets_item_keys(items, folder_id_map)

    deleted_items =
      Repo.all(from(i in SecretsItem))
      |> Enum.reduce(0, fn item, acc ->
        key = {item.secrets_vault_folder_id, item.title}

        if MapSet.member?(imported_item_keys, key) do
          acc
        else
          Repo.delete!(item)
          acc + 1
        end
      end)

    {:ok, %{deleted_folders: 0, deleted_items: deleted_items}}
  end

  defp imported_project_item_keys(items, folder_id_map) do
    items
    |> Enum.flat_map(fn map ->
      exported_folder_id = map["project_folder_id"]
      folder_id = Map.get(folder_id_map, exported_folder_id, exported_folder_id)
      title = map["title"]

      if is_integer(folder_id) and is_binary(title) and title != "" do
        [{folder_id, title}]
      else
        []
      end
    end)
    |> MapSet.new()
  end

  defp imported_secrets_item_keys(items, folder_id_map) when is_map(folder_id_map) do
    items
    |> Enum.flat_map(fn map ->
      exported_folder_id = map["secrets_vault_folder_id"]
      folder_id = resolve_secrets_folder_id(exported_folder_id, folder_id_map)
      title = map["title"]

      if is_integer(folder_id) and is_binary(title) and title != "" do
        [{folder_id, title}]
      else
        []
      end
    end)
    |> MapSet.new()
  end
end
