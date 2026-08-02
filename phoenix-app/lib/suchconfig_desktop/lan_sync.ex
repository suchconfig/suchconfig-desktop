defmodule SuchConfigDesktop.LanSync do
  @moduledoc false

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault.Item, as: SecretsItem
  alias SuchConfigDesktop.TrustedFolder
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktop.Vault.Item, as: ProjectItem
  alias SuchConfigCore.Security.EnvCrypto

  @vaults ~w(projects secrets)

  def enabled_vaults, do: @vaults

  def item_key("projects", folder_id, title),
    do: "projects:#{folder_id}:#{title}"

  def item_key("secrets", folder_id, title),
    do: "secrets:#{folder_id}:#{title}"

  def export_handoff_bundles(export_password)
      when is_binary(export_password) and export_password != "" do
    Enum.flat_map(@vaults, fn vault ->
      case TrustedFolder.vault_atom(vault) do
        nil ->
          []

        vault_atom ->
          case TrustedFolder.export_handoff_bundle(vault_atom, export_password) do
            {:ok, binary} ->
              [
                %{
                  vault: vault,
                  snapshot_base64: Base.encode64(binary)
                }
              ]

            _ ->
              []
          end
      end
    end)
  end

  def export_handoff_bundles(_), do: []

  def import_handoff_bundle(vault, snapshot_base64, import_password)
      when is_binary(vault) and is_binary(import_password) and import_password != "" do
    with vault_atom when not is_nil(vault_atom) <- TrustedFolder.vault_atom(vault),
         {:ok, binary} <- Base.decode64(String.trim(snapshot_base64 || "")),
         {:ok, stats} <- TrustedFolder.import_handoff_bundle(binary, vault_atom, import_password) do
      record_lan_sync_audit("handoff", %{
        vault: vault,
        upserted: Map.get(stats, :upserted, 0),
        skipped: Map.get(stats, :skipped, 0),
        deleted_items: Map.get(stats, :deleted_items, 0),
        deleted_folders: Map.get(stats, :deleted_folders, 0)
      })

      {:ok, stats}
    else
      {:ok, _} -> {:error, :invalid_bundle}
      {:error, _} = err -> err
      _ -> {:error, :invalid_bundle}
    end
  end

  def import_handoff_bundle(_, _, _), do: {:error, :invalid_password}

  def export_deltas_for_vault(vault, password, peer_frontiers)
      when vault in @vaults and is_binary(password) and is_map(peer_frontiers) do
    items = list_vault_items(vault)

    updates =
      Enum.flat_map(items, fn item ->
        key = item_key_for(vault, item)

        case build_item_delta(vault, item, password, Map.get(peer_frontiers, key)) do
          {:ok, update} -> [update]
          _ -> []
        end
      end)

    {:ok, updates}
  end

  def export_deltas_for_vault(_, _, _), do: {:ok, []}

  def sync_apply(peer_device_id, updates, password)
      when is_binary(peer_device_id) and is_list(updates) and is_binary(password) do
    Enum.reduce_while(updates, {:ok, %{applied: 0, peers: [peer_device_id]}}, fn update, acc ->
      case acc do
        {:error, _} = err ->
          {:halt, err}

        {:ok, stats} ->
          case apply_single_update(update, password, peer_device_id) do
            {:ok, frontier_patch} ->
              {:cont,
               {:ok,
                stats
                |> Map.put(:applied, stats.applied + 1)
                |> Map.put(:frontier, frontier_patch)}}

            {:error, _} = err ->
              {:halt, err}
          end
      end
    end)
    |> tap(fn
      {:ok, stats} ->
        record_lan_sync_audit("lan_sync", %{
          peer_device_id: peer_device_id,
          updates_applied: Map.get(stats, :applied, 0)
        })

      _ ->
        :ok
    end)
  end

  defp apply_single_update(update, password, peer_device_id) do
    vault = Map.get(update, "vault") || Map.get(update, :vault)
    item_key = Map.get(update, "item_key") || Map.get(update, :item_key)
    delta_b64 = Map.get(update, "delta_base64") || Map.get(update, :delta_base64)

    with true <- vault in @vaults,
         {:ok, delta} <- Base.decode64(String.trim(delta_b64 || "")),
         {:ok, item} <- find_item_by_key(vault, item_key),
         {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, merged, summary} <- Crdt.apply_update(plain, delta),
         {:ok, enc} <- EnvCrypto.encrypt_to_binary(password, merged),
         {:ok, hash} <- Crdt.snapshot_hash(merged),
         {:ok, _} <- persist_item_snapshot(vault, item, enc, hash) do
      {:ok,
       %{
         peer_device_id: peer_device_id,
         item_key: item_key,
         snapshot_base64: Base.encode64(merged),
         snapshot_hash: hash,
         remote_frontier: Map.get(summary, :remote_frontier, "")
       }}
    else
      _ -> {:error, :apply_failed}
    end
  end

  defp build_item_delta(vault, item, password, peer_snapshot_b64) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, peer_plain} <- decode_peer_snapshot(peer_snapshot_b64),
         {:ok, delta} <- Crdt.diff_from(plain, peer_plain),
         {:ok, hash} <- Crdt.snapshot_hash(plain),
         false <- delta == <<>> do
      {:ok,
       %{
         vault: vault,
         item_key: item_key_for(vault, item),
         delta_base64: Base.encode64(delta),
         snapshot_hash: hash
       }}
    else
      true -> {:error, :no_changes}
      _ -> {:error, :delta_failed}
    end
  end

  defp decode_peer_snapshot(nil), do: Crdt.new_doc("generic_note")
  defp decode_peer_snapshot(""), do: Crdt.new_doc("generic_note")

  defp decode_peer_snapshot(b64) when is_binary(b64) do
    case Base.decode64(String.trim(b64)) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> Crdt.new_doc("generic_note")
    end
  end

  defp list_vault_items("projects") do
    Repo.all(from(i in ProjectItem, order_by: [asc: i.project_folder_id, asc: i.title]))
  end

  defp list_vault_items("secrets") do
    Repo.all(from(i in SecretsItem, order_by: [asc: i.secrets_vault_folder_id, asc: i.title]))
  end

  defp list_vault_items(_), do: []

  defp item_key_for("projects", %ProjectItem{} = item),
    do: item_key("projects", item.project_folder_id, item.title)

  defp item_key_for("secrets", %SecretsItem{} = item),
    do: item_key("secrets", item.secrets_vault_folder_id, item.title)

  defp find_item_by_key("projects", key) when is_binary(key) do
    case String.split(key, ":", parts: 3) do
      ["projects", folder_id, title] ->
        with {fid, ""} <- Integer.parse(folder_id) do
          Repo.one(
            from(i in ProjectItem,
              where: i.project_folder_id == ^fid and i.title == ^title,
              limit: 1
            )
          )
          |> case do
            nil -> {:error, :not_found}
            item -> {:ok, item}
          end
        else
          _ -> {:error, :invalid_key}
        end

      _ ->
        {:error, :invalid_key}
    end
  end

  defp find_item_by_key("secrets", key) when is_binary(key) do
    case String.split(key, ":", parts: 3) do
      ["secrets", folder_id, title] ->
        with {fid, ""} <- Integer.parse(folder_id) do
          Repo.one(
            from(i in SecretsItem,
              where: i.secrets_vault_folder_id == ^fid and i.title == ^title,
              limit: 1
            )
          )
          |> case do
            nil -> {:error, :not_found}
            item -> {:ok, item}
          end
        else
          _ -> {:error, :invalid_key}
        end

      _ ->
        {:error, :invalid_key}
    end
  end

  defp find_item_by_key(_, _), do: {:error, :invalid_key}

  defp persist_item_snapshot("projects", %ProjectItem{} = item, enc, hash) do
    item
    |> ProjectItem.changeset(%{
      crdt_snapshot_encrypted: enc,
      crdt_snapshot_hash: hash
    })
    |> Repo.update()
  end

  defp persist_item_snapshot("secrets", %SecretsItem{} = item, enc, hash) do
    item
    |> SecretsItem.changeset(%{
      crdt_snapshot_encrypted: enc,
      crdt_snapshot_hash: hash
    })
    |> Repo.update()
  end

  defp record_lan_sync_audit(operation, metadata) do
    ProjectVault.record_merge_audit(operation, metadata)
  end
end
