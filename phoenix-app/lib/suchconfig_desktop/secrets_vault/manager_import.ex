defmodule SuchConfigDesktop.SecretsVault.ManagerImport do
  @moduledoc """
  Preview and commit Bitwarden (and future manager) exports into Secrets Vault.
  """

  alias SuchConfigCore.Importers.Bitwarden
  alias SuchConfigCore.Importers.ImportData
  alias SuchConfigDesktop.SecretsVault

  @sample_limit 25
  @duplicate_suffix " (duplicate)"

  @doc """
  Parses a Bitwarden unencrypted JSON export for preview, including duplicate matches.

  Duplicates are matched by folder + title + kind (case-insensitive title).
  """
  @spec preview_bitwarden_export(binary()) :: {:ok, map()} | {:error, term()}
  def preview_bitwarden_export(payload) when is_binary(payload) do
    with {:ok, %ImportData{} = data} <- Bitwarden.parse_json(payload) do
      importable = Enum.reject(data.items, & &1.skipped?)
      duplicates = detect_duplicates(data, importable)

      {:ok,
       %{
         source: data.source,
         import_data: data,
         folder_count: length(data.folders),
         item_count: length(importable),
         duplicate_count: length(duplicates),
         duplicates: Enum.take(duplicates, @sample_limit),
         warnings: data.warnings,
         sample_items: Enum.take(importable, @sample_limit)
       }}
    end
  end

  def preview_bitwarden_export(_), do: {:error, :invalid_payload}

  @doc """
  Persists importable items. Duplicate strategy defaults to `:keep_as_new` (non-destructive).

  - `:keep_as_new` — matching items are created with `" (duplicate)"` appended to the title
  - `:overwrite` — matching items are updated in place via `save_item/2` (Loro CRDT replace)
  """
  @spec import_normalized(ImportData.t(), :all, binary()) :: {:ok, map()} | {:error, term()}
  @spec import_normalized(ImportData.t(), :all, binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def import_normalized(data, selection, password, opts \\ [])

  def import_normalized(%ImportData{} = data, :all, password, opts)
      when is_binary(password) and password != "" do
    strategy = Keyword.get(opts, :duplicate_strategy, :keep_as_new)
    batch_id = Ecto.UUID.generate()
    items = Enum.reject(data.items, & &1.skipped?)

    with {:ok, folder_map} <- ensure_folders(data.folders) do
      import_with_strategy(items, folder_map, build_existing_index(), strategy, password, batch_id)
    end
  end

  def import_normalized(_, _, "", _), do: {:error, :invalid_password}
  def import_normalized(_, _, nil, _), do: {:error, :invalid_password}
  def import_normalized(_, _, _, _), do: {:error, :invalid_args}

  defp import_with_strategy(items, folder_map, existing_index, strategy, password, batch_id) do
    {item_ids, created, overwritten, skipped, errors, _index} =
      Enum.reduce(items, {[], 0, 0, 0, [], existing_index}, fn item, acc ->
        {ids, created, overwritten, skipped, errs, index} = acc
        attrs = item_attrs(item, folder_map)
        key = duplicate_key(attrs)
        match = Map.get(index, key)

        {attrs, action} =
          case {match, strategy} do
            {nil, _} ->
              {attrs, :create}

            {%{id: id}, :overwrite} ->
              {Map.put(attrs, :id, id), :overwrite}

            {_match, :keep_as_new} ->
              {Map.put(attrs, :title, unique_duplicate_title(attrs.title, index)), :create}
          end

        case SecretsVault.save_item(attrs, password) do
          {:ok, saved} ->
            new_index =
              case action do
                :create ->
                  Map.put(index, duplicate_key(Map.put(attrs, :title, saved.title)), %{
                    id: saved.id,
                    title: saved.title
                  })

                :overwrite ->
                  index
              end

            case action do
              :create ->
                {[saved.id | ids], created + 1, overwritten, skipped, errs, new_index}

              :overwrite ->
                {[saved.id | ids], created, overwritten + 1, skipped, errs, new_index}
            end

          {:error, reason} ->
            {ids, created, overwritten, skipped + 1, [{item.title, reason} | errs], index}
        end
      end)

    {:ok,
     %{
       batch_id: batch_id,
       imported: length(item_ids),
       created: created,
       overwritten: overwritten,
       skipped: skipped,
       folder_ids: Map.values(folder_map) |> Enum.uniq(),
       item_ids: Enum.reverse(item_ids),
       errors: Enum.reverse(errors),
       duplicate_strategy: strategy
     }}
  end

  defp detect_duplicates(data, importable) do
    folder_map = preview_folder_map(data.folders)
    index = build_existing_index()

    importable
    |> Enum.reduce([], fn item, acc ->
      attrs = item_attrs_for_match(item, folder_map)
      key = duplicate_key(attrs)

      case Map.get(index, key) do
        nil ->
          acc

        %{id: id, title: title} ->
          [
            %{
              import_title: item.title,
              existing_id: id,
              existing_title: title,
              kind: item.kind,
              folder_name: item.folder_name
            }
            | acc
          ]
      end
    end)
    |> Enum.reverse()
  end

  defp preview_folder_map(folders) do
    existing =
      SecretsVault.list_folders()
      |> Map.new(fn f -> {String.downcase(f.name), f.id} end)

    Enum.reduce(folders, %{}, fn folder, acc ->
      case Map.get(existing, String.downcase(folder.name)) do
        nil -> acc
        id -> Map.put(acc, folder.name, id)
      end
    end)
  end

  defp build_existing_index do
    SecretsVault.list_items(nil)
    |> Map.new(fn item ->
      key =
        duplicate_key(%{
          title: item.title,
          kind: item.kind,
          secrets_vault_folder_id: item.secrets_vault_folder_id
        })

      {key, %{id: item.id, title: item.title}}
    end)
  end

  defp duplicate_key(%{title: title, kind: kind, secrets_vault_folder_id: folder_id}) do
    {
      folder_id,
      title |> to_string() |> String.trim() |> String.downcase(),
      kind |> to_string() |> String.downcase()
    }
  end

  defp unique_duplicate_title(title, index) do
    existing_titles =
      index
      |> Map.values()
      |> MapSet.new(fn %{title: t} -> String.downcase(t) end)

    base = "#{title}#{@duplicate_suffix}"

    if not MapSet.member?(existing_titles, String.downcase(base)) do
      base
    else
      Enum.find_value(2..10_000, fn n ->
        candidate = "#{base} #{n}"

        if not MapSet.member?(existing_titles, String.downcase(candidate)) do
          candidate
        end
      end) || "#{base} #{System.unique_integer([:positive])}"
    end
  end

  defp ensure_folders(folders) do
    existing =
      SecretsVault.list_folders()
      |> Map.new(fn f -> {String.downcase(f.name), f.id} end)

    Enum.reduce_while(folders, {:ok, {existing, %{}}}, fn folder, {:ok, {by_down, by_name}} ->
      key = String.downcase(folder.name)

      case Map.fetch(by_down, key) do
        {:ok, id} ->
          {:cont, {:ok, {by_down, Map.put(by_name, folder.name, id)}}}

        :error ->
          case SecretsVault.create_folder(%{
                 name: folder.name,
                 description: "Imported from Bitwarden"
               }) do
            {:ok, created} ->
              {:cont,
               {:ok,
                {Map.put(by_down, key, created.id), Map.put(by_name, folder.name, created.id)}}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
      end
    end)
    |> case do
      {:ok, {_by_down, by_name}} -> {:ok, by_name}
      other -> other
    end
  end

  defp item_attrs(item, folder_map) do
    folder_id =
      case resolve_folder_id(item.folder_name, folder_map) do
        nil -> unassociated_folder_id()
        id -> id
      end

    %{
      title: item.title,
      kind: item.kind,
      security_mode: "global_passkey",
      secrets_vault_folder_id: folder_id,
      body: item.body || "",
      frontmatter: item.frontmatter || %{}
    }
  end

  defp item_attrs_for_match(item, folder_map) do
    folder_id =
      case item.folder_name do
        name when is_binary(name) ->
          trimmed = String.trim(name)

          if trimmed == "" do
            unassociated_folder_id()
          else
            Map.get(folder_map, name) || Map.get(folder_map, trimmed) ||
              {:pending_folder, String.downcase(trimmed)}
          end

        _ ->
          unassociated_folder_id()
      end

    %{
      title: item.title,
      kind: item.kind,
      secrets_vault_folder_id: folder_id
    }
  end

  defp unassociated_folder_id do
    case SecretsVault.ensure_unassociated_folder() do
      {:ok, folder} -> folder.id
      _ -> nil
    end
  end

  defp resolve_folder_id(nil, _map), do: nil
  defp resolve_folder_id("", _map), do: nil
  defp resolve_folder_id(name, map), do: Map.get(map, name)
end
