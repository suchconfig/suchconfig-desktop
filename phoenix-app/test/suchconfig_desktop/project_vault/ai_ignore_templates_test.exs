defmodule SuchConfigDesktop.ProjectVault.AiIgnoreTemplatesTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.AiIgnoreTemplates

  setup do
    dir = Path.join(System.tmp_dir!(), "ai_templates_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "content_for includes secrets-safe baseline" do
    assert {:ok, body} = AiIgnoreTemplates.content_for(".cursorignore")
    assert body =~ ".env"
    assert body =~ ".env.*"
    assert body =~ "!.env.example"
    assert body =~ "node_modules/"
    assert body =~ "*.suchvault"
  end

  test "write_if_missing creates file once", %{dir: dir} do
    assert :ok = AiIgnoreTemplates.write_if_missing(dir, ".claudeignore")
    abs = Path.join(dir, ".claudeignore")
    assert File.regular?(abs)
    assert File.read!(abs) =~ ".env.*"

    assert {:skipped, :exists} = AiIgnoreTemplates.write_if_missing(dir, ".claudeignore")
  end

  test "rejects unknown templates and nested paths", %{dir: dir} do
    assert {:error, :unknown_template} = AiIgnoreTemplates.write_if_missing(dir, ".fooignore")
    assert {:error, :invalid_path} = AiIgnoreTemplates.write_if_missing(dir, "sub/.cursorignore")
  end
end
