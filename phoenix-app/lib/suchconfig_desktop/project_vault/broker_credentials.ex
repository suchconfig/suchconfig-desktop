defmodule SuchConfigDesktop.ProjectVault.BrokerCredentials do
  @moduledoc false

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.BrokerFrontmatter
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.Vault.Item
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  def list_broker_credentials_for_folder(folder_id, password)
      when is_integer(folder_id) and is_binary(password) and password != "" do
    folder_id
    |> ProjectVault.list_vault_items_by_folder()
    |> Enum.flat_map(&broker_entries_for_item(&1, password))
  end

  def list_broker_credentials_for_folder(_, _), do: []

  def credentials_map(folder_id, password) when is_integer(folder_id) do
    list_broker_credentials_for_folder(folder_id, password)
    |> Enum.reduce(%{}, fn entry, acc ->
      case entry.placeholder do
        placeholder when is_binary(placeholder) and placeholder != "" ->
          Map.put(acc, placeholder, entry.secret)

        _ ->
          acc
      end
    end)
  end

  def credentials_map(_, _), do: %{}

  defp broker_entries_for_item(%Item{} = item, password) do
    frontmatter = BrokerFrontmatter.read_map(item, password)

    cond do
      env_item?(item, frontmatter) ->
        env_entries(item, password, frontmatter)

      BrokerFrontmatter.broker_enabled?(frontmatter) ->
        credential_entry(item, password, frontmatter)

      true ->
        []
    end
  end

  defp env_item?(item, frontmatter) do
    linked_env_path?(frontmatter) or item.kind == "env_note"
  end

  defp linked_env_path?(frontmatter) do
    case Map.get(frontmatter, LinkedFrontmatter.relative_path()) do
      path when is_binary(path) -> String.match?(path, ~r/^\.env/)
      _ -> false
    end
  end

  defp credential_entry(item, password, frontmatter) do
    with {:ok, body} <- ProjectVault.decrypt_vault_item_body(item, password),
         secret <- String.trim(body),
         true <- secret != "",
         placeholder <- credential_placeholder(item, frontmatter),
         placeholder when is_binary(placeholder) <- placeholder do
      [
        %{
          item_id: item.id,
          title: item.title,
          placeholder: placeholder,
          secret: secret,
          kind: Map.get(frontmatter, BrokerFrontmatter.broker_credential_kind_key(), "api_key"),
          inject_as: Map.get(frontmatter, BrokerFrontmatter.broker_inject_as_key(), "header"),
          source: :credential
        }
      ]
    else
      _ -> []
    end
  end

  defp env_entries(item, password, frontmatter) do
    enabled_keys =
      frontmatter
      |> Map.get(BrokerFrontmatter.broker_env_enabled_keys_key(), "")
      |> BrokerFrontmatter.parse_env_enabled_keys()
      |> MapSet.new()

    with {:ok, body} <- ProjectVault.decrypt_vault_item_body(item, password) do
      body
      |> Formatting.parse_env_entries()
      |> Enum.filter(fn entry -> MapSet.member?(enabled_keys, entry.key) end)
      |> Enum.flat_map(fn entry ->
        case BrokerFrontmatter.placeholder_for_env_key(entry.key) do
          placeholder when is_binary(placeholder) ->
            value = String.trim(entry.value)

            if value != "" do
              [
                %{
                  item_id: item.id,
                  title: item.title,
                  env_key: entry.key,
                  placeholder: placeholder,
                  secret: value,
                  kind: "env_var",
                  inject_as: "env",
                  source: :env_key
                }
              ]
            else
              []
            end

          _ ->
            []
        end
      end)
    else
      _ -> []
    end
  end

  defp credential_placeholder(item, frontmatter) do
    case Map.get(frontmatter, BrokerFrontmatter.broker_placeholder_key()) do
      placeholder when is_binary(placeholder) ->
        placeholder |> String.trim() |> then(fn p -> if p == "", do: nil, else: p end)

      _ ->
        BrokerFrontmatter.default_placeholder(item.id)
    end
  end
end
