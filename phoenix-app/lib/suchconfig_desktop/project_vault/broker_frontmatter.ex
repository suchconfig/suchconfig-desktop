defmodule SuchConfigDesktop.ProjectVault.BrokerFrontmatter do
  @moduledoc false

  @broker_enabled "broker_enabled"
  @broker_placeholder "broker_placeholder"
  @broker_credential_kind "broker_credential_kind"
  @broker_inject_as "broker_inject_as"
  @broker_env_key "broker_env_key"
  @broker_env_enabled_keys "broker_env_enabled_keys"

  def broker_enabled_key, do: @broker_enabled
  def broker_placeholder_key, do: @broker_placeholder
  def broker_credential_kind_key, do: @broker_credential_kind
  def broker_inject_as_key, do: @broker_inject_as
  def broker_env_key_key, do: @broker_env_key
  def broker_env_enabled_keys_key, do: @broker_env_enabled_keys

  def keys do
    [
      @broker_enabled,
      @broker_placeholder,
      @broker_credential_kind,
      @broker_inject_as,
      @broker_env_key,
      @broker_env_enabled_keys
    ]
  end

  def read_map(item, password) do
    keys()
    |> Enum.flat_map(fn key ->
      case SuchConfigDesktop.ProjectVault.vault_item_frontmatter(item, password, key) do
        {:ok, value} when is_binary(value) -> [{key, value}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  def broker_enabled?(frontmatter) when is_map(frontmatter) do
    parse_bool(Map.get(frontmatter, @broker_enabled))
  end

  def broker_enabled?(_), do: false

  def placeholder_for_env_key(env_key) when is_binary(env_key) do
    key = String.trim(env_key)

    if key != "" and String.match?(key, ~r/^[A-Za-z0-9_]+$/) do
      "__#{key}__"
    else
      nil
    end
  end

  def placeholder_for_env_key(_), do: nil

  def parse_env_enabled_keys(raw) when is_binary(raw) do
    raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_env_enabled_keys(_), do: []

  def encode_env_enabled_keys(keys) when is_list(keys) do
    keys
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  def encode_env_enabled_keys(_), do: ""

  def default_placeholder(item_id) when is_integer(item_id) do
    "__vault_item_#{item_id}__"
  end

  defp parse_bool("true"), do: true
  defp parse_bool("1"), do: true
  defp parse_bool("on"), do: true
  defp parse_bool("yes"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool("0"), do: false
  defp parse_bool("off"), do: false
  defp parse_bool("no"), do: false
  defp parse_bool(_), do: false
end
