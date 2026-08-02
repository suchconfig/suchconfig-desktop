defmodule SuchConfigDesktop.ProjectVault.AutoDetect do
  @moduledoc false

  alias SuchConfigDesktop.ProjectVault.AiToolingPresence
  alias SuchConfigDesktop.ProjectVault.VaultFileCandidates

  def scan_disk(path) when is_binary(path) do
    case SuchConfigCore.Parsers.ProjectParser.scan_project(path) do
      {:ok, data} ->
        {:ok,
         data
         |> Map.put(:vault_file_candidates, VaultFileCandidates.collect(path))
         |> Map.put(:ai_tooling, AiToolingPresence.analyze(path))}

      other ->
        other
    end
  end

  def scan_from_files(project_name, files) when is_binary(project_name) and is_list(files),
    do: SuchConfigCore.Parsers.ProjectParser.scan_from_contents(project_name, files)

  def generate_plan(project_data, opts \\ []) when is_map(project_data),
    do: SuchConfigCore.Analyzers.WorkflowAnalyzer.generate_plan(project_data, opts)
end
