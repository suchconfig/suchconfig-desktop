defmodule SuchConfigDesktopWeb.SecretsVaultLive.Formatting do
  @moduledoc false

  alias SuchConfigDesktop.SecretsVault.KindFields

  @kind_labels %{
    "password" => "Login",
    "login" => "Login",
    "api_key" => "API key",
    "ssh_key" => "SSH key",
    "secure_note" => "Secure note"
  }

  def kind_label(kind) when is_binary(kind), do: Map.get(@kind_labels, kind, kind)

  def kind_options, do: KindFields.kind_options()

  def normalize_kind(kind), do: KindFields.normalize_kind(kind)

  def kind_badge_class("password"),
    do:
      "rounded px-1.5 py-0.5 text-[10px] font-medium bg-indigo-100 text-indigo-800 dark:bg-indigo-900/40 dark:text-indigo-200"

  def kind_badge_class("login"),
    do: kind_badge_class("password")

  def kind_badge_class("api_key"),
    do:
      "rounded px-1.5 py-0.5 text-[10px] font-medium bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200"

  def kind_badge_class("ssh_key"),
    do:
      "rounded px-1.5 py-0.5 text-[10px] font-medium bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-200"

  def kind_badge_class(_),
    do:
      "rounded px-1.5 py-0.5 text-[10px] font-medium bg-slate-100 text-slate-700 dark:bg-slate-700 dark:text-slate-200"

  @glyph_types %{
    "password" => "login",
    "login" => "login",
    "api_key" => "api",
    "ssh_key" => "ssh",
    "secure_note" => "note"
  }

  def glyph_type(kind), do: Map.get(@glyph_types, normalize_kind(kind), "login")

  def detail_icon_name(kind) do
    case glyph_type(kind) do
      "login" -> "user"
      "api" -> "code"
      "ssh" -> "ssh"
      "note" -> "note"
      _ -> "diamond"
    end
  end

  def detail_pill_label(kind) do
    case glyph_type(kind) do
      "ssh" -> "ed25519"
      "api" -> "bearer"
      "login" -> "credential"
      "note" -> "sealed"
      _ -> "credential"
    end
  end

  def entry_subtitle(item) do
    case glyph_type(item.kind) do
      "login" -> "credential"
      "api" -> "••••••"
      "ssh" -> detail_pill_label(item.kind)
      "note" -> "sealed"
      _ -> kind_label(item.kind)
    end
  end

  def format_date(nil), do: "—"

  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")

  def format_date(%NaiveDateTime{} = dt) do
    dt |> DateTime.from_naive!("Etc/UTC") |> format_date()
  end

  def filter_items(items, filter_types, filter_tags, tags_by_item_id \\ %{})
      when is_list(filter_types) and is_list(filter_tags) and is_map(tags_by_item_id) do
    items
    |> filter_by_types(filter_types)
    |> filter_by_tags(filter_tags, tags_by_item_id)
  end

  def filter_by_types(items, []), do: items

  def filter_by_types(items, filter_types) when is_list(filter_types) do
    Enum.filter(items, &(glyph_type(&1.kind) in filter_types))
  end

  def filter_by_tags(items, [], _tags_by_item_id), do: items

  def filter_by_tags(items, filter_tags, tags_by_item_id)
      when is_list(filter_tags) and is_map(tags_by_item_id) do
    Enum.filter(items, fn item ->
      item_tags = Map.get(tags_by_item_id, item.id, [])
      Enum.any?(item_tags, &(&1 in filter_tags))
    end)
  end

  def filter_type_options(items) when is_list(items) do
    counts =
      items
      |> Enum.frequencies_by(&glyph_type(&1.kind))
      |> Map.new()

    SuchConfigDesktopWeb.Sc.FilterPopover.type_options()
    |> Enum.map(fn type ->
      Map.put(type, :count, Map.get(counts, type.id, 0))
    end)
  end

  def tag_options(items, tags_by_item_id) when is_list(items) and is_map(tags_by_item_id) do
    items
    |> Enum.flat_map(fn item -> Map.get(tags_by_item_id, item.id, []) end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {tag, _count} -> String.downcase(tag) end)
    |> Enum.map(fn {tag, count} ->
      %{tag: tag, count: count, slug: tag_slug(tag)}
    end)
  end

  def tags_by_item_id(items, password)
      when is_list(items) and is_binary(password) and password != "" do
    alias SuchConfigDesktop.SecretsVault
    alias SuchConfigDesktop.ProjectVault.VaultItemTags

    Map.new(items, fn item ->
      tags =
        case SecretsVault.decrypt_item_frontmatter(item, password) do
          {:ok, fm} -> VaultItemTags.decode(Map.get(fm, "tags"))
          _ -> []
        end

      {item.id, tags}
    end)
  end

  def tags_by_item_id(_items, _password), do: %{}

  def unique_tag_count(tags_by_item_id) when is_map(tags_by_item_id) do
    tags_by_item_id
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> length()
  end

  defp tag_slug(tag) when is_binary(tag) do
    tag
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  def filter_items_by_search(items, ""), do: items

  def filter_items_by_search(items, query) when is_binary(query) do
    q = String.downcase(String.trim(query))

    if q == "" do
      items
    else
      Enum.filter(items, fn item ->
        String.contains?(String.downcase(item.title || ""), q) or
          String.contains?(String.downcase(kind_label(item.kind)), q)
      end)
    end
  end

  def format_relative_time(nil), do: "—"

  def format_relative_time(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second) |> max(0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{quotient(seconds, 3600)}h ago"
      seconds < 604_800 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%Y-%m-%d")
    end
  end

  def format_relative_time(%NaiveDateTime{} = dt) do
    dt |> DateTime.from_naive!("Etc/UTC") |> format_relative_time()
  end

  def strength_label(nil), do: "—"

  def strength_label(score) when is_integer(score) and score >= 1 and score <= 5 do
    Enum.at(~w(fragile weak fair strong vault-grade), score - 1)
  end

  def strength_label(_), do: "—"

  def strength_color(nil), do: "var(--ink-2)"
  def strength_color(score) when is_integer(score) and score >= 4, do: "var(--moss)"
  def strength_color(_), do: "var(--accent)"

  @modal_type_options [
    %{id: "login", kind: "password", label: "Login", desc: "user · password", icon: "user"},
    %{id: "api", kind: "api_key", label: "API Key", desc: "token · env", icon: "code"},
    %{id: "ssh", kind: "ssh_key", label: "SSH Key", desc: "ed25519 · rsa", icon: "ssh"},
    %{
      id: "note",
      kind: "secure_note",
      label: "Secure Note",
      desc: "markdown · sealed",
      icon: "note"
    }
  ]

  def modal_type_options, do: @modal_type_options

  def modal_type_id(kind), do: glyph_type(kind)

  def kind_from_modal_type("login"), do: "password"
  def kind_from_modal_type("api"), do: "api_key"
  def kind_from_modal_type("ssh"), do: "ssh_key"
  def kind_from_modal_type("note"), do: "secure_note"
  def kind_from_modal_type(_), do: "password"

  def new_entry_title_placeholder("login"), do: "e.g. GitHub — work"
  def new_entry_title_placeholder("api"), do: "e.g. OpenAI — prod"
  def new_entry_title_placeholder("ssh"), do: "e.g. deploy-bot · prod-edge"
  def new_entry_title_placeholder("note"), do: "e.g. Recovery codes — Stripe"
  def new_entry_title_placeholder(_), do: ""

  defp quotient(seconds, unit), do: div(seconds, unit)

  @vault_stat_kinds ~w(password api_key ssh_key secure_note)

  def vault_stats(items, folders, crdt_enabled?) when is_list(items) and is_list(folders) do
    counts = kind_counts(items)

    %{
      total: length(items),
      folder_count: length(folders),
      login_count: Map.get(counts, "password", 0),
      api_count: Map.get(counts, "api_key", 0),
      ssh_count: Map.get(counts, "ssh_key", 0),
      note_count: Map.get(counts, "secure_note", 0),
      merge_conflicts: 0,
      crdt_enabled?: crdt_enabled?,
      last_backup_at: nil,
      trusted_folder_path: nil,
      last_sync_at: nil
    }
  end

  def kind_counts(items) when is_list(items) do
    Enum.reduce(items, kind_count_base(), fn item, acc ->
      kind = normalize_kind(item.kind)
      Map.update(acc, kind, 1, &(&1 + 1))
    end)
  end

  def backup_label(nil), do: "Not configured"
  def backup_label(%DateTime{} = dt), do: format_date(dt)
  def backup_label(%NaiveDateTime{} = dt), do: format_date(dt)

  def sync_destination_label(nil), do: "Not configured"
  def sync_destination_label(""), do: "Not configured"

  def sync_destination_label(path) when is_binary(path) do
    trimmed = String.trim(path)
    if trimmed == "", do: "Not configured", else: trimmed
  end

  def sync_status_label(nil, _path), do: "Not synced"
  def sync_status_label(_at, nil), do: "Not synced"
  def sync_status_label(_at, ""), do: "Not synced"

  def sync_status_label(at, path) when is_binary(path) do
    trimmed = String.trim(path)

    if trimmed == "" do
      "Not synced"
    else
      "#{sync_destination_label(path)} · #{format_date(at)}"
    end
  end

  def merge_conflicts_label(0, true), do: "0 pending"
  def merge_conflicts_label(0, false), do: "—"
  def merge_conflicts_label(count, _crdt_enabled?), do: "#{count} pending"

  def merge_conflicts_color(0, true), do: "var(--moss)"
  def merge_conflicts_color(0, false), do: "var(--ink-2)"
  def merge_conflicts_color(_count, _crdt_enabled?), do: "var(--accent)"

  defp kind_count_base do
    Map.new(@vault_stat_kinds, &{&1, 0})
  end

  @show_all_folder_id :all

  def show_all_folder_id, do: @show_all_folder_id

  def show_all_folder_selected?(id), do: id == @show_all_folder_id

  def parse_folder_select_id("all"), do: @show_all_folder_id

  def parse_folder_select_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def parse_folder_select_id(id) when is_integer(id), do: id
  def parse_folder_select_id(@show_all_folder_id), do: @show_all_folder_id
  def parse_folder_select_id(_), do: nil

  def items_query_folder_id(@show_all_folder_id), do: nil
  def items_query_folder_id(folder_id) when is_integer(folder_id), do: folder_id
  def items_query_folder_id(_), do: nil

  def new_entry_folder_id(@show_all_folder_id), do: nil
  def new_entry_folder_id(folder_id), do: folder_id

  def new_entry_folder_param(@show_all_folder_id), do: ""
  def new_entry_folder_param(folder_id) when is_integer(folder_id), do: folder_id
  def new_entry_folder_param(_), do: ""

  def save_folder_id(@show_all_folder_id), do: nil
  def save_folder_id(folder_id), do: folder_id

  def save_error_message(reason) do
    case reason do
      :invalid_title -> "Title is required."
      :unknown_kind -> "Invalid entry type."
      :invalid_folder -> "Folder not found."
      :invalid_password -> "Unlock the vault to save secrets."
      :secrets_vault_persistence_disabled -> "Secrets Vault persistence is disabled."
      :crdt_unavailable -> "CRDT support is not available on this build."
      :encrypt_failed -> "Could not encrypt this entry."
      :crdt_error -> "Could not update the CRDT document."
      other -> SuchConfigDesktop.SecretsVault.format_error(other)
    end
  end
end
