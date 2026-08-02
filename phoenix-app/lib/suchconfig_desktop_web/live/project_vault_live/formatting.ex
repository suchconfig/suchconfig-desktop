defmodule SuchConfigDesktopWeb.ProjectVaultLive.Formatting do
  @moduledoc false

  @note_categories [
    {"Generic Note", "generic_note"},
    {"Environment Files", "environment_files"},
    {"Secrets/Credentials", "secrets_credentials"},
    {"AI/Editor Rules", "ai_editor_rules"},
    {"Tooling/Config Snippets", "tooling_config_snippets"},
    {"Project Notes", "project_notes"}
  ]

  def note_categories, do: @note_categories

  def vault_item_category_options do
    [
      {"Generic Note", "generic_note"},
      {"Environment Note", "env_note"},
      {"Prompt Template", "prompt_template"},
      {"Guideline", "guideline"},
      {"API Spec", "api_spec"},
      {"Security Policy", "security_policy"},
      {"Security Manifest", "security_manifest"}
    ]
  end

  def normalize_vault_item_kind(kind) when is_binary(kind) do
    allowed = Enum.map(vault_item_category_options(), fn {_, v} -> v end)
    if kind in allowed, do: kind, else: "generic_note"
  end

  def normalize_vault_item_kind(_), do: "generic_note"

  def project_details_vault_title?(title) when is_binary(title) do
    t = String.trim(title)

    t == "Project Details" or t == "Project Details (import)" or
      String.match?(t, ~r/^Project Details \(\d+\)$/)
  end

  def project_details_vault_title?(_), do: false

  def project_details_vault_item?(title, kind)
      when is_binary(title) and is_binary(kind) do
    kind == "guideline" and project_details_vault_title?(title)
  end

  def project_details_vault_item?(_, _), do: false

  def selected_folder_linked_path(_folders, nil), do: nil

  def selected_folder_linked_path(folders, folder_id)
      when is_list(folders) and is_integer(folder_id) do
    folders
    |> Enum.find(&(&1.id == folder_id))
    |> linked_path_from_folder()
  end

  def selected_folder_linked_path(_, _), do: nil

  defp linked_path_from_folder(%{linked_project_path: path}) when is_binary(path) do
    trimmed = String.trim(path)
    if trimmed == "", do: nil, else: trimmed
  end

  defp linked_path_from_folder(_), do: nil

  def normalize_note_type(note_type) when is_binary(note_type) do
    allowed = Enum.map(@note_categories, fn {_label, value} -> value end)
    if note_type in allowed, do: note_type, else: "generic_note"
  end

  def normalize_note_type(_), do: "generic_note"

  def env_note_type?(note_category),
    do: normalize_note_type(note_category) == "environment_files"

  def env_display_mode?(note_category, tags \\ []) do
    tags = List.wrap(tags)

    note_category in ["environment_files", "env_note"] or
      env_note_type?(note_category) or
      "Environment" in Enum.map(tags, &String.trim/1)
  end

  def default_display_mode(note_category, tags \\ []) do
    if env_display_mode?(note_category, tags), do: :copy, else: :input
  end

  def tag_badge_label(tag), do: tag

  def tag_badge_class(tag) do
    base =
      "shrink-0 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold border"

    tone =
      case tag do
        "Linked" ->
          "border-sky-300 bg-sky-50 text-sky-700 dark:border-sky-700 dark:bg-sky-900/20 dark:text-sky-300"

        "Environment" ->
          "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300"

        "Secrets" ->
          "border-red-300 bg-red-50 text-red-700 dark:border-red-700 dark:bg-red-900/20 dark:text-red-300"

        "AI Rules" ->
          "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-700 dark:bg-purple-900/20 dark:text-purple-300"

        "Guideline" ->
          "border-indigo-300 bg-indigo-50 text-indigo-700 dark:border-indigo-700 dark:bg-indigo-900/20 dark:text-indigo-300"

        _ ->
          "border-gray-300 bg-gray-50 text-gray-700 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300"
      end

    base <> " " <> tone
  end

  def note_content_placeholder(note_category) do
    cond do
      env_display_mode?(note_category) ->
        "Paste .env content here"

      normalize_vault_item_kind(note_category) == "security_manifest" ->
        "Security Manifest JSON is managed by Sentinel Scan"

      true ->
        legacy_note_content_placeholder(note_category)
    end
  end

  defp legacy_note_content_placeholder(note_category) do
    case normalize_note_type(note_category) do
      "environment_files" ->
        "Paste .env content here"

      "secrets_credentials" ->
        "Paste secrets, credentials, tokens, or passwords here"

      "ai_editor_rules" ->
        "Paste AI/editor rules here (.cursorrules, Claude rules, prompt rules)"

      "tooling_config_snippets" ->
        "Paste tooling or config snippets here (CI/CD, settings, scripts)"

      "project_notes" ->
        "Paste project notes, runbooks, and onboarding context here"

      _ ->
        "Paste note content here"
    end
  end

  def note_type_badge_label(note_type) do
    case normalize_note_type(note_type) do
      "environment_files" -> "ENV"
      "secrets_credentials" -> "SECRET"
      "ai_editor_rules" -> "RULES"
      "tooling_config_snippets" -> "CONFIG"
      "project_notes" -> "NOTE"
      _ -> "GENERIC"
    end
  end

  def note_type_badge_class(note_type) do
    base =
      "shrink-0 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold border"

    tone =
      case normalize_note_type(note_type) do
        "environment_files" ->
          "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300"

        "secrets_credentials" ->
          "border-red-300 bg-red-50 text-red-700 dark:border-red-700 dark:bg-red-900/20 dark:text-red-300"

        "ai_editor_rules" ->
          "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-700 dark:bg-purple-900/20 dark:text-purple-300"

        "tooling_config_snippets" ->
          "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-700 dark:bg-blue-900/20 dark:text-blue-300"

        "project_notes" ->
          "border-amber-300 bg-amber-50 text-amber-700 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-300"

        _ ->
          "border-gray-300 bg-gray-50 text-gray-700 dark:border-slate-600 dark:bg-slate-700/40 dark:text-slate-300"
      end

    base <> " " <> tone
  end

  def vault_item_badge_label(kind) do
    case kind do
      "env_note" -> "ENV"
      "prompt_template" -> "PROMPT"
      "guideline" -> "GUIDE"
      "api_spec" -> "API"
      "security_policy" -> "POLICY"
      "security_manifest" -> "SENTINEL"
      _ -> "GENERIC"
    end
  end

  def vault_item_badge_class(kind) do
    base =
      "shrink-0 inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold border"

    tone =
      case kind do
        "env_note" ->
          "border-emerald-300 bg-emerald-50 text-emerald-700 dark:border-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300"

        "prompt_template" ->
          "border-purple-300 bg-purple-50 text-purple-700 dark:border-purple-700 dark:bg-purple-900/20 dark:text-purple-300"

        "guideline" ->
          "border-blue-300 bg-blue-50 text-blue-700 dark:border-blue-700 dark:bg-blue-900/20 dark:text-blue-300"

        "api_spec" ->
          "border-teal-300 bg-teal-50 text-teal-700 dark:border-teal-700 dark:bg-teal-900/20 dark:text-teal-300"

        "security_policy" ->
          "border-red-300 bg-red-50 text-red-700 dark:border-red-700 dark:bg-red-900/20 dark:text-red-300"

        "security_manifest" ->
          "border-amber-300 bg-amber-50 text-amber-800 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-300"

        _ ->
          "border-gray-300 bg-gray-50 text-gray-700 dark:border-slate-600 dark:bg-slate-700/40 dark:text-slate-300"
      end

    base <> " " <> tone
  end

  def parse_env_entries(content) when is_binary(content) do
    content
    |> String.split(~r/\r\n|\n|\r/, trim: false)
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_number}, acc ->
      trimmed = String.trim(line)

      cond do
        trimmed == "" ->
          acc

        String.starts_with?(trimmed, "#") ->
          acc

        !String.contains?(line, "=") ->
          acc

        true ->
          [key, value] = String.split(line, "=", parts: 2)
          cleaned_key = String.trim(key)
          cleaned_value = String.trim(value)

          if cleaned_key == "" do
            acc
          else
            [
              %{
                key: cleaned_key,
                value: cleaned_value,
                line_number: line_number,
                is_secret: secret_key?(cleaned_key)
              }
              | acc
            ]
          end
      end
    end)
    |> Enum.reverse()
  end

  def parse_env_entries(_), do: []

  def native_passkey_reason(nil), do: "Authenticate for Global Passkey"

  def native_passkey_reason(purpose) when is_binary(purpose) do
    case purpose do
      "save" -> "Authenticate to save secure note"
      "unlock" -> "Authenticate to unlock secure note"
      _ -> "Authenticate for Global Passkey"
    end
  end

  def native_passkey_reason(_), do: "Authenticate for Global Passkey"

  def format_relative_time(nil), do: "—"

  def format_relative_time(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second) |> max(0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      seconds < 604_800 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%Y-%m-%d")
    end
  end

  def format_relative_time(%NaiveDateTime{} = dt) do
    dt |> DateTime.from_naive!("Etc/UTC") |> format_relative_time()
  end

  def format_byte_size(content) when is_binary(content) do
    bytes = byte_size(content)

    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
    end
  end

  def format_byte_size(_), do: "—"

  def file_extension(title, kind, note_type \\ nil) do
    cond do
      env_display_mode?(note_type || kind, []) -> "env"
      kind in ["env_note", "environment_files"] -> "env"
      kind == "prompt_template" -> "md"
      kind == "api_spec" -> "yaml"
      kind == "security_policy" -> "md"
      kind == "guideline" -> "md"
      String.contains?(title || "", ".") -> title |> String.split(".") |> List.last()
      true -> "note"
    end
  end

  def toolbar_path(nil, _), do: "—"
  def toolbar_path(folder_name, nil), do: folder_name

  def toolbar_path(folder_name, item_title) when is_binary(item_title) and item_title != "" do
    folder_name <> " / " <> item_title
  end

  def toolbar_path(folder_name, _), do: folder_name

  def folder_item_count(notes, vault_items) do
    length(List.wrap(notes)) + length(List.wrap(vault_items))
  end

  def edits_today_count(events) when is_list(events) do
    today = Date.utc_today()

    Enum.count(events, fn event ->
      case Map.get(event, :inserted_at) do
        %DateTime{} = dt -> DateTime.to_date(dt) == today
        %NaiveDateTime{} = dt -> NaiveDateTime.to_date(dt) == today
        _ -> false
      end
    end)
  end

  @modal_note_type_options [
    %{
      id: "generic",
      kind: "generic_note",
      label: "Note",
      desc: "markdown · sealed",
      icon: "file"
    },
    %{
      id: "env",
      kind: "environment_files",
      label: "Env file",
      desc: "dotenv · schema",
      icon: "code"
    },
    %{
      id: "rules",
      kind: "ai_editor_rules",
      label: "AI rules",
      desc: "cursor · agents",
      icon: "wand"
    },
    %{
      id: "project",
      kind: "project_notes",
      label: "Project",
      desc: "docs · notes",
      icon: "folder"
    }
  ]

  @modal_vault_type_options [
    %{id: "note", kind: "generic_note", label: "Note", desc: "markdown · sealed", icon: "file"},
    %{id: "env", kind: "env_note", label: "Env", desc: "dotenv · vars", icon: "code"},
    %{
      id: "prompt",
      kind: "prompt_template",
      label: "Prompt",
      desc: "template · ai",
      icon: "wand"
    },
    %{
      id: "policy",
      kind: "security_policy",
      label: "Policy",
      desc: "security · rules",
      icon: "lock"
    }
  ]

  def modal_note_type_options, do: @modal_note_type_options
  def modal_vault_type_options, do: @modal_vault_type_options

  def modal_type_options(vault_item_ui_enabled?) do
    if vault_item_ui_enabled?, do: @modal_vault_type_options, else: @modal_note_type_options
  end

  def modal_type_id(category, vault_item_ui_enabled?) do
    options = modal_type_options(vault_item_ui_enabled?)

    Enum.find_value(options, fn option ->
      if normalize_category_for_modal(category, vault_item_ui_enabled?) == option.kind,
        do: option.id
    end) || List.first(options).id
  end

  def kind_from_modal_type(type, vault_item_ui_enabled?) do
    options = modal_type_options(vault_item_ui_enabled?)

    case Enum.find(options, &(&1.id == type)) do
      %{kind: kind} -> kind
      _ -> if(vault_item_ui_enabled?, do: "generic_note", else: "generic_note")
    end
  end

  def new_note_title_placeholder("env"), do: "e.g. staging.env"
  def new_note_title_placeholder("rules"), do: "e.g. .cursorrules — backend"
  def new_note_title_placeholder("project"), do: "e.g. onboarding · README"
  def new_note_title_placeholder("prompt"), do: "e.g. code-review · system"
  def new_note_title_placeholder("policy"), do: "e.g. secrets-handling"
  def new_note_title_placeholder(_), do: "e.g. my-note.md"

  def detail_pill_label(category, vault_item_ui_enabled?) do
    kind = normalize_category_for_modal(category, vault_item_ui_enabled?)

    cond do
      kind == "archive" -> "sealed"
      vault_item_ui_enabled? and kind in ["security_policy"] -> "sealed"
      env_display_mode?(kind, []) -> "env-schema"
      true -> nil
    end
  end

  defp normalize_category_for_modal(category, true), do: normalize_vault_item_kind(category)
  defp normalize_category_for_modal(category, false), do: normalize_note_type(category)

  def file_row_icon(kind, note_type \\ nil) do
    cond do
      kind == "archive" ->
        "archive"

      env_display_mode?(note_type || kind, []) ->
        "file"

      kind in [
        "env_note",
        "prompt_template",
        "guideline",
        "api_spec",
        "security_policy",
        "security_manifest"
      ] ->
        "file"

      true ->
        "file"
    end
  end

  def file_row_icon_color(kind, note_type \\ nil) do
    cond do
      kind == "archive" -> "var(--plum)"
      env_display_mode?(note_type || kind, []) -> "var(--moss)"
      kind in ["secrets_credentials", "security_policy"] -> "var(--rust)"
      true -> "var(--ink-2)"
    end
  end

  defp secret_key?(key) do
    key
    |> String.upcase()
    |> then(fn upper ->
      String.contains?(upper, "SECRET") or
        String.contains?(upper, "TOKEN") or
        String.contains?(upper, "PASSWORD") or
        String.contains?(upper, "KEY")
    end)
  end
end
