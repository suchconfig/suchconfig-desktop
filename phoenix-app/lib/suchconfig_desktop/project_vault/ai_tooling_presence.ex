defmodule SuchConfigDesktop.ProjectVault.AiToolingPresence do
  @moduledoc false

  @ai_ignore_files [
    ".cursorignore",
    ".claudeignore",
    ".windsurfignore",
    ".aiderignore",
    ".kiroignore"
  ]

  @tools [
    %{
      id: :cursor,
      tag: "Cursor",
      scaffold: ".cursorignore",
      file_markers: [".cursorignore", ".cursorrules", "AGENTS.md"],
      dir_markers: [".cursor"]
    },
    %{
      id: :claude,
      tag: "Claude",
      scaffold: ".claudeignore",
      file_markers: [".claudeignore", "CLAUDE.md"],
      dir_markers: [".claude"]
    },
    %{
      id: :windsurf,
      tag: "Windsurf",
      scaffold: ".windsurfignore",
      file_markers: [".windsurfrules", ".windsurfignore"],
      dir_markers: [".windsurf"]
    },
    %{
      id: :aider,
      tag: "Aider",
      scaffold: ".aiderignore",
      file_markers: [".aiderignore", ".aider.conf.yml"],
      dir_markers: []
    },
    %{
      id: :kiro,
      tag: "Kiro",
      scaffold: ".kiroignore",
      file_markers: [".kiroignore"],
      dir_markers: [".kiro"]
    },
    %{
      id: :git,
      tag: "Git",
      scaffold: nil,
      file_markers: [".gitignore"],
      dir_markers: []
    }
  ]

  def analyze(root_path) when is_binary(root_path) do
    root_path = String.trim(root_path)

    if root_path == "" or not File.dir?(root_path) do
      empty_result()
    else
      do_analyze(root_path)
    end
  end

  def analyze(_), do: empty_result()

  def scaffold_selection(ai_tooling) when is_map(ai_tooling) do
    (ai_tooling[:recommendations] || [])
    |> Map.new(fn rec -> {rec.path, rec.default_selected == true} end)
  end

  def scaffold_selection(_), do: %{}

  defp do_analyze(root) do
    found =
      @tools
      |> Enum.flat_map(fn tool ->
        files =
          for m <- tool.file_markers, regular_exists?(root, m), do: m

        dirs =
          for m <- tool.dir_markers, dir_exists?(root, m), do: m <> "/"

        files ++ dirs
      end)
      |> Enum.uniq()
      |> Enum.sort()

    detected =
      @tools
      |> Enum.filter(&tool_present?(root, &1))
      |> Enum.map(& &1.id)

    folder_tags =
      @tools
      |> Enum.filter(&(&1.id in detected))
      |> Enum.map(& &1.tag)
      |> Enum.uniq()

    any_ai_ignore? = Enum.any?(@ai_ignore_files, &regular_exists?(root, &1))

    recommendations =
      @tools
      |> Enum.reject(&is_nil(&1.scaffold))
      |> Enum.filter(fn tool -> not regular_exists?(root, tool.scaffold) end)
      |> Enum.map(fn tool ->
        default_selected = default_select?(tool, detected, any_ai_ignore?)

        %{
          path: tool.scaffold,
          tool: tool.tag,
          reason: recommend_reason(tool, detected, any_ai_ignore?),
          default_selected: default_selected
        }
      end)
      |> Enum.filter(& &1.reason)

    %{
      detected_tools: detected,
      folder_tags: folder_tags,
      found: found,
      recommendations: recommendations
    }
  end

  defp empty_result do
    %{detected_tools: [], folder_tags: [], found: [], recommendations: []}
  end

  defp tool_present?(root, tool) do
    Enum.any?(tool.file_markers, &regular_exists?(root, &1)) or
      Enum.any?(tool.dir_markers, &dir_exists?(root, &1))
  end

  defp default_select?(tool, detected, any_ai_ignore?) do
    cond do
      tool.id == :cursor and (:cursor in detected or not any_ai_ignore?) -> true
      tool.id != :cursor and tool.id in detected -> true
      true -> false
    end
  end

  defp recommend_reason(tool, detected, any_ai_ignore?) do
    cond do
      tool.id == :cursor and :cursor in detected ->
        "Cursor project is missing .cursorignore"

      tool.id == :cursor and not any_ai_ignore? ->
        "No AI ignore file found; recommend a secrets-safe .cursorignore"

      tool.id in detected ->
        "#{tool.tag} markers found but #{tool.scaffold} is missing"

      true ->
        nil
    end
  end

  defp regular_exists?(root, name), do: File.regular?(Path.join(root, name))
  defp dir_exists?(root, name), do: File.dir?(Path.join(root, name))
end
