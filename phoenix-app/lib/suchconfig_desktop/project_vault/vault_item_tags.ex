defmodule SuchConfigDesktop.ProjectVault.VaultItemTags do
  @moduledoc false

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.Vault.Item

  @tags_key "tags"
  @system_linked "Linked"

  @suggested_tags [
    "Environment",
    "Secrets",
    "AI Rules",
    "Config",
    "Notes",
    "Prompt",
    "Guideline",
    "API",
    "Security"
  ]

  @note_type_tag %{
    "environment_files" => "Environment",
    "secrets_credentials" => "Secrets",
    "ai_editor_rules" => "AI Rules",
    "tooling_config_snippets" => "Config",
    "project_notes" => "Notes",
    "generic_note" => "Notes"
  }

  @kind_tag %{
    "env_note" => "Environment",
    "prompt_template" => "Prompt",
    "guideline" => "Guideline",
    "api_spec" => "API",
    "security_policy" => "Security",
    "security_manifest" => "Security"
  }

  def suggested_tags, do: @suggested_tags
  def system_linked_tag, do: @system_linked
  def frontmatter_key, do: @tags_key

  def encode(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  def encode(_), do: ""

  def decode(nil), do: []
  def decode(""), do: []

  def decode(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def decode(_), do: []

  def normalize_tag(tag) when is_binary(tag), do: tag |> String.trim() |> capitalize_tag()
  def normalize_tag(_), do: ""

  def user_tags_from_item(%Item{} = item, password) when is_binary(password) do
    case ProjectVault.vault_item_frontmatter(item, password, @tags_key) do
      {:ok, raw} -> decode(raw)
      _ -> []
    end
  end

  def user_tags_from_item(_, _), do: []

  def linked?(%Item{} = item, password) when is_binary(password) do
    case ProjectVault.vault_item_frontmatter(item, password, LinkedFrontmatter.relative_path()) do
      {:ok, path} when is_binary(path) -> String.trim(path) != ""
      _ -> false
    end
  end

  def linked?(_, _), do: false

  def display_tags(%Item{} = item, password) when is_binary(password) do
    user_tags_from_item(item, password)
    |> then(fn user ->
      if linked?(item, password) do
        Enum.uniq([@system_linked | user])
      else
        user
      end
    end)
  end

  def display_tags(_, _), do: []

  def tags_by_item_id(items, password) when is_list(items) do
    if is_binary(password) and password != "" do
      Map.new(items, fn item -> {item.id, display_tags(item, password)} end)
    else
      %{}
    end
  end

  def tags_by_item_id(_, _), do: %{}

  def folder_tag_suggestions(items, password, extra_tags \\ []) do
    base =
      items
      |> tags_by_item_id(password)
      |> Map.values()
      |> List.flatten()

    (@suggested_tags ++ base ++ extra_tags)
    |> Enum.map(&normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def store_user_tags(tags) when is_list(tags) do
    encoded = encode(tags)

    if encoded == "" do
      %{}
    else
      %{@tags_key => encoded}
    end
  end

  def merge_frontmatter(existing_fm, user_tags) when is_map(existing_fm) do
    user_only =
      user_tags
      |> List.wrap()
      |> Enum.map(&normalize_tag/1)
      |> Enum.reject(&(&1 == @system_linked))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    store = store_user_tags(user_only)

    existing_fm
    |> Map.drop([@tags_key])
    |> Map.merge(store)
  end

  def kind_from_tags(tags, fallback \\ "generic_note") when is_list(tags) do
    normalized = Enum.map(tags, &normalize_tag/1)

    cond do
      "Environment" in normalized -> "env_note"
      "Guideline" in normalized -> "guideline"
      "Prompt" in normalized -> "prompt_template"
      "API" in normalized -> "api_spec"
      "Security" in normalized -> "security_policy"
      true -> fallback
    end
  end

  def tags_from_note_type(note_type) do
    case Map.get(@note_type_tag, note_type) do
      nil -> []
      tag -> [tag]
    end
  end

  def tags_from_kind(kind) do
    case Map.get(@kind_tag, kind) do
      nil -> []
      tag -> [tag]
    end
  end

  def env_display_mode?(tags, kind) when is_list(tags) do
    kind in ["env_note", "environment_files"] or "Environment" in Enum.map(tags, &normalize_tag/1)
  end

  def env_display_mode?(_, kind), do: kind in ["env_note", "environment_files"]

  defp capitalize_tag(tag) do
    case tag do
      "" -> ""
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
    end
  end
end
