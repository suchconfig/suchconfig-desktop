defmodule SuchConfigDesktop.ProjectVault.AutoDetectTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.AutoDetect
  alias SuchConfigDesktop.ProjectVault.VaultFileCandidates

  test "generate_plan returns markdown for minimal project_data" do
    data = %{}

    assert {:ok, plan} = AutoDetect.generate_plan(data, format: :setup_guide)
    body = plan[:markdown] || Map.get(plan, "markdown")
    assert is_binary(body)
    assert String.trim(body) != ""
  end

  test "scan_disk attaches vault_file_candidates including .env" do
    dir = Path.join(System.tmp_dir!(), "auto_detect_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    File.write!(Path.join(dir, ".gitignore"), ".env\n")
    File.write!(Path.join(dir, ".env"), "X=1\n")

    assert {:ok, data} = AutoDetect.scan_disk(dir)
    candidates = data[:vault_file_candidates] || []
    assert Enum.any?(candidates, &(&1.relative_path == ".env"))

    ai = data[:ai_tooling]
    assert is_map(ai)
    assert is_list(ai.recommendations)
    assert Enum.any?(ai.recommendations, &(&1.path == ".cursorignore"))

    assert {:ok, plan} = AutoDetect.generate_plan(data, format: :setup_guide)
    assert is_binary(plan[:markdown])
    assert String.trim(plan[:markdown]) != ""
  end

  test "vault candidates collect env files independently" do
    dir = Path.join(System.tmp_dir!(), "vfc_only_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    File.write!(Path.join(dir, ".env"), "A=1\n")

    list = VaultFileCandidates.collect(dir)
    assert Enum.any?(list, &(&1.relative_path == ".env" and &1.note_type == "environment_files"))
  end
end
