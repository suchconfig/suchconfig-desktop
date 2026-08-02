defmodule SuchConfigDesktop.ProjectVault.AiToolingPresenceTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.AiToolingPresence

  setup do
    dir = Path.join(System.tmp_dir!(), "ai_presence_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "empty dir recommends .cursorignore by default", %{dir: dir} do
    result = AiToolingPresence.analyze(dir)

    assert result.detected_tools == []
    assert result.folder_tags == []
    assert result.found == []

    assert [%{path: ".cursorignore", default_selected: true}] =
             Enum.filter(result.recommendations, &(&1.path == ".cursorignore"))

    selection = AiToolingPresence.scaffold_selection(result)
    assert selection[".cursorignore"] == true
  end

  test "Cursor and Claude markers yield tags and missing ignore recommendations", %{dir: dir} do
    File.write!(Path.join(dir, "AGENTS.md"), "# agents\n")
    File.write!(Path.join(dir, "CLAUDE.md"), "# claude\n")

    result = AiToolingPresence.analyze(dir)

    assert :cursor in result.detected_tools
    assert :claude in result.detected_tools
    assert "Cursor" in result.folder_tags
    assert "Claude" in result.folder_tags
    assert "AGENTS.md" in result.found
    assert "CLAUDE.md" in result.found

    paths = Enum.map(result.recommendations, & &1.path)
    assert ".cursorignore" in paths
    assert ".claudeignore" in paths

    cursor_rec = Enum.find(result.recommendations, &(&1.path == ".cursorignore"))
    claude_rec = Enum.find(result.recommendations, &(&1.path == ".claudeignore"))
    assert cursor_rec.default_selected
    assert claude_rec.default_selected
  end

  test "existing .cursorignore is not recommended", %{dir: dir} do
    File.write!(Path.join(dir, ".cursorignore"), ".env\n")
    File.mkdir_p!(Path.join(dir, ".cursor"))

    result = AiToolingPresence.analyze(dir)

    assert "Cursor" in result.folder_tags
    assert ".cursorignore" in result.found
    assert ".cursor/" in result.found
    refute Enum.any?(result.recommendations, &(&1.path == ".cursorignore"))
  end

  test "invalid path returns empty result" do
    assert AiToolingPresence.analyze("/no/such/path-#{:erlang.unique_integer([:positive])}") ==
             %{detected_tools: [], folder_tags: [], found: [], recommendations: []}
  end
end
