defmodule SuchConfigDesktop.ProjectVault.LinkedSync do
  @moduledoc false

  alias SuchConfigDesktop.EnvManager.ProjectFolder
  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.LinkedDiff
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Item
  alias SuchConfigCore.Security.EnvCrypto

  @type sync_status :: :in_sync | :vault_ahead | :disk_ahead | :conflict | :not_linked

  @spec status(Item.t(), ProjectFolder.t() | nil, String.t(), String.t()) :: sync_status()
  def status(%Item{} = item, folder, vault_body, password)
      when is_binary(vault_body) and is_binary(password) do
    with rel when is_binary(rel) <- linked_relative_path(item, folder, password),
         root when is_binary(root) <- folder_root(folder),
         {:ok, abs} <- safe_join(root, rel),
         true <- File.regular?(abs),
         {:ok, disk_hash, _} <- disk_fingerprint(abs) do
      vault_hash = LinkedFrontmatter.content_fingerprint(vault_body)
      agreed = agreed_hash(item, folder, password)

      cond do
        agreed == nil -> if vault_hash == disk_hash, do: :in_sync, else: :vault_ahead
        vault_hash == disk_hash and vault_hash == agreed -> :in_sync
        vault_hash != agreed and disk_hash != agreed -> :conflict
        vault_hash != agreed -> :vault_ahead
        disk_hash != agreed -> :disk_ahead
        true -> :in_sync
      end
    else
      _ -> :not_linked
    end
  end

  def status(_, _, _, _), do: :not_linked

  @spec linked_relative_path(Item.t(), ProjectFolder.t() | nil, String.t()) :: String.t() | nil
  def linked_relative_path(%Item{} = item, _folder, password) do
    case read_frontmatter(item, password, LinkedFrontmatter.relative_path()) do
      {:ok, rel} when is_binary(rel) and rel != "" -> rel
      _ -> nil
    end
  end

  @spec agreed_hash(Item.t(), ProjectFolder.t() | nil, String.t()) :: String.t() | nil
  def agreed_hash(item, _folder, password) do
    case read_frontmatter(item, password, LinkedFrontmatter.content_sha256()) do
      {:ok, h} when is_binary(h) and h != "" -> h
      _ -> nil
    end
  end

  @spec absolute_path(ProjectFolder.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def absolute_path(%ProjectFolder{linked_project_path: root}, relative)
      when is_binary(root) and is_binary(relative) do
    safe_join(String.trim(root), relative)
  end

  def absolute_path(_, _), do: {:error, :not_linked}

  @spec push_to_disk(Item.t(), ProjectFolder.t(), String.t(), String.t()) ::
          {:ok, Item.t()} | {:error, term()}
  def push_to_disk(%Item{} = item, %ProjectFolder{} = folder, body, password) do
    with rel when is_binary(rel) <- linked_relative_path(item, folder, password),
         {:ok, abs} <- absolute_path(folder, rel),
         :ok <- write_file(abs, body),
         {:ok, _hash, mtime, _} <- LinkedFrontmatter.disk_file_fingerprint(abs),
         {:ok, updated} <- update_agreement(item, body, mtime, password) do
      ProjectVault.record_merge_audit("linked_push", %{
        "relative_path" => rel,
        "project_folder_id" => folder.id
      })

      {:ok, updated}
    else
      nil -> {:error, :not_linked}
      {:error, _} = e -> e
      _ -> {:error, :push_failed}
    end
  end

  def pull_preview(%Item{} = item, %ProjectFolder{} = folder, vault_body, password)
      when is_binary(password) do
    with rel when is_binary(rel) <- linked_relative_path(item, folder, password),
         {:ok, abs} <- absolute_path(folder, rel),
         {:ok, _h, _mtime, disk_body} <- LinkedFrontmatter.disk_file_fingerprint(abs) do
      {:ok,
       %{
         disk_body: disk_body,
         vault_body: vault_body,
         diff_lines: LinkedDiff.lines(vault_body, disk_body)
       }}
    else
      nil -> {:error, :not_linked}
      {:error, _} = e -> e
      _ -> {:error, :read_failed}
    end
  end

  @spec accept_pull(Item.t(), ProjectFolder.t(), String.t(), String.t()) ::
          {:ok, Item.t()} | {:error, term()}
  def accept_pull(%Item{} = item, %ProjectFolder{} = folder, disk_body, password) do
    with rel when is_binary(rel) <- linked_relative_path(item, folder, password),
         {:ok, abs} <- absolute_path(folder, rel),
         {:ok, _hash, mtime, _} <- LinkedFrontmatter.disk_file_fingerprint(abs),
         {:ok, updated} <-
           ProjectVault.save_vault_item(
             %{
               id: item.id,
               title: item.title,
               kind: item.kind,
               security_mode: item.security_mode,
               project_folder_id: item.project_folder_id,
               body: disk_body,
               frontmatter: LinkedFrontmatter.after_agreement(disk_body, mtime)
             },
             password
           ) do
      ProjectVault.record_merge_audit("linked_pull", %{
        "relative_path" => rel,
        "project_folder_id" => folder.id
      })

      {:ok, updated}
    else
      nil -> {:error, :not_linked}
      {:error, _} = e -> e
      _ -> {:error, :pull_failed}
    end
  end

  @spec find_item_by_linked_path(integer(), String.t()) :: Item.t() | nil
  def find_item_by_linked_path(folder_id, relative_path) when is_integer(folder_id) do
    ProjectVault.list_vault_items_by_folder(folder_id)
    |> Enum.find(&(&1.title == relative_path))
  end

  @spec refresh_status(Item.t(), ProjectFolder.t(), String.t(), String.t()) :: sync_status()
  def refresh_status(item, folder, vault_body, password) do
    status(item, folder, vault_body, password)
  end

  defp update_agreement(item, body, mtime, password) do
    ProjectVault.save_vault_item(
      %{
        id: item.id,
        title: item.title,
        kind: item.kind,
        security_mode: item.security_mode,
        project_folder_id: item.project_folder_id,
        body: body,
        frontmatter: LinkedFrontmatter.after_agreement(body, mtime)
      },
      password
    )
  end

  defp read_frontmatter(%Item{} = item, password, key) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, val} <- Crdt.frontmatter_string(plain, key) do
      {:ok, val}
    else
      _ -> :error
    end
  end

  defp disk_fingerprint(path) do
    case LinkedFrontmatter.disk_file_fingerprint(path) do
      {:ok, hash, mtime, _} -> {:ok, hash, mtime}
      :error -> :error
    end
  end

  defp folder_root(%ProjectFolder{linked_project_path: path}) when is_binary(path) do
    trimmed = String.trim(path)
    if trimmed != "", do: trimmed, else: nil
  end

  defp folder_root(_), do: nil

  defp safe_join(root, relative) do
    root_exp = root |> Path.expand() |> String.trim_trailing("/")
    abs = Path.join(root_exp, relative) |> Path.expand()
    abs_exp = abs |> String.trim_trailing("/")

    if abs_exp == root_exp or String.starts_with?(abs_exp, root_exp <> "/") do
      {:ok, abs}
    else
      {:error, :path_escape}
    end
  end

  defp write_file(path, body) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".suchconfig.tmp"

    with :ok <- File.write(tmp, body),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, _} -> File.write(path, body)
    end
  end
end
