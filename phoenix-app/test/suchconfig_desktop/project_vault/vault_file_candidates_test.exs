defmodule SuchConfigDesktop.ProjectVault.VaultFileCandidatesTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.VaultFileCandidates

  test "collect includes known config and gitignored env file" do
    dir = Path.join(System.tmp_dir!(), "vault_fc_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf(dir) end)

    File.write!(Path.join(dir, ".gitignore"), ".env*\n")
    File.write!(Path.join(dir, ".cursorrules"), "rules")
    File.write!(Path.join(dir, ".env.local"), "X=1\n")

    list = VaultFileCandidates.collect(dir)

    assert [%{relative_path: _, gitignored: _, note_type: _, absolute_path: _} | _] = list
    assert Enum.any?(list, &(&1.relative_path == ".cursorrules"))
    env = Enum.find(list, &(&1.relative_path == ".env.local"))
    assert env.gitignored
    assert env.note_type == "environment_files"
  end
end
