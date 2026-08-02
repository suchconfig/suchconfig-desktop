defmodule SuchConfigDesktop.ProjectVault.VaultFileCandidates do
  @moduledoc false

  @known_basenames [
    ".cursorrules",
    ".cursorignore",
    ".claudeignore",
    ".windsurfrules",
    ".windsurfignore",
    ".aiderignore",
    ".aider.conf.yml",
    ".kiroignore",
    ".gitignore",
    ".npmrc",
    ".yarnrc",
    ".yarnrc.yml",
    ".editorconfig",
    ".dockerignore",
    ".prettierrc",
    ".prettierrc.json",
    ".prettierrc.js",
    ".eslintrc.json",
    ".eslintrc.js",
    "biome.json",
    "biome.jsonc",
    ".tool-versions",
    ".nvmrc",
    ".node-version",
    "Procfile",
    "Procfile.dev",
    "fly.toml",
    "vercel.json",
    "netlify.toml",
    "AGENTS.md",
    "CLAUDE.md",
    ".env.example",
    ".env.sample"
  ]

  @max_import_bytes 400_000

  @skip_basenames MapSet.new([".DS_Store", "Thumbs.db", ".localized"])

  def collect(root_path) when is_binary(root_path) do
    root_path = String.trim(root_path)

    if root_path == "" or not File.dir?(root_path) do
      []
    else
      patterns = read_gitignore_patterns(Path.join(root_path, ".gitignore"))
      curated = for b <- @known_basenames, relative_exists?(root_path, b), do: b
      env_files = list_root_env_files(root_path)
      gitignored_extras = list_root_gitignored_regular_files(root_path, patterns)

      curated
      |> Kernel.++(env_files)
      |> Kernel.++(gitignored_extras)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn rel ->
        abs = Path.join(root_path, rel)
        gi = gitignored?(rel, patterns)

        %{
          relative_path: rel,
          absolute_path: abs,
          gitignored: gi,
          note_type: infer_note_type(rel)
        }
      end)
    end
  end

  defp relative_exists?(root, name), do: File.regular?(Path.join(root, name))

  defp list_root_env_files(root) do
    case File.ls(root) do
      {:ok, names} ->
        names
        |> Enum.filter(fn n ->
          String.match?(n, ~r/^\.env/) and File.regular?(Path.join(root, n))
        end)

      {:error, _} ->
        []
    end
  end

  defp list_root_gitignored_regular_files(root, patterns) do
    if patterns == [] do
      []
    else
      case File.ls(root) do
        {:ok, names} ->
          names
          |> Enum.filter(fn n ->
            path = Path.join(root, n)

            File.regular?(path) and
              not MapSet.member?(@skip_basenames, n) and
              n not in @known_basenames and
              not String.match?(n, ~r/^\.env/) and
              gitignored?(n, patterns) and
              importable_size?(path) and
              textish_name?(n)
          end)

        {:error, _} ->
          []
      end
    end
  end

  defp importable_size?(abs) do
    case File.stat(abs) do
      {:ok, %{size: s}} when s >= 0 and s <= @max_import_bytes -> true
      _ -> false
    end
  end

  defp textish_name?(name) do
    ext = name |> Path.extname() |> String.downcase()

    ext == "" or
      ext in [
        ".md",
        ".txt",
        ".json",
        ".yml",
        ".yaml",
        ".toml",
        ".ini",
        ".cfg",
        ".conf",
        ".config",
        ".rc",
        ".env",
        ".rules",
        ".pem",
        ".crt",
        ".key",
        ".csr",
        ".pub",
        ".local",
        ".example",
        ".sample",
        ".sh",
        ".bash",
        ".zsh",
        ".gitignore",
        ".cursorrules",
        ".editorconfig",
        ".npmrc",
        ".xml",
        ".properties"
      ] or
      String.starts_with?(name, ".")
  end

  defp infer_note_type(rel) do
    cond do
      String.match?(rel, ~r/^\.env/) ->
        "environment_files"

      rel in [
        ".cursorrules",
        ".cursorignore",
        ".claudeignore",
        ".windsurfrules",
        ".windsurfignore",
        ".aiderignore",
        ".aider.conf.yml",
        ".kiroignore",
        "AGENTS.md",
        "CLAUDE.md"
      ] ->
        "ai_editor_rules"

      rel in [".npmrc", ".yarnrc", ".yarnrc.yml", ".editorconfig", "biome.json", "biome.jsonc"] ->
        "tooling_config_snippets"

      String.ends_with?(rel, ".editorconfig") ->
        "tooling_config_snippets"

      true ->
        "generic_note"
    end
  end

  defp read_gitignore_patterns(gitignore_path) do
    case File.read(gitignore_path) do
      {:ok, bin} ->
        bin
        |> String.split(~r/\r\n|\n|\r/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)
        |> Enum.reject(&String.starts_with?(&1, "!"))
        |> Enum.uniq()

      {:error, _} ->
        []
    end
  end

  defp gitignored?(relative_path, patterns) do
    Enum.any?(patterns, &pattern_matches?(&1, relative_path))
  end

  defp pattern_matches?(pattern, rel) when is_binary(pattern) and is_binary(rel) do
    pat = String.trim(pattern)
    base = Path.basename(rel)

    cond do
      pat == "" ->
        false

      String.starts_with?(pat, "#") ->
        false

      String.starts_with?(pat, "!") ->
        false

      String.ends_with?(pat, "/") ->
        dir = String.trim_trailing(pat, "/")
        rel == dir or String.starts_with?(rel, dir <> "/")

      String.contains?(pat, "/") ->
        rel == pat or String.starts_with?(rel, pat <> "/")

      String.contains?(pat, "*") ->
        wildcard_match?(base, pat) or wildcard_match?(rel, pat)

      true ->
        base == pat or rel == pat
    end
  end

  defp wildcard_match?(subject, pattern) when is_binary(subject) and is_binary(pattern) do
    parts = String.split(pattern, "*", trim: false)
    rx_body = parts |> Enum.map(&Regex.escape/1) |> Enum.join(".*")
    Regex.match?(Regex.compile!("^#{rx_body}$"), subject)
  rescue
    _ -> false
  end
end
