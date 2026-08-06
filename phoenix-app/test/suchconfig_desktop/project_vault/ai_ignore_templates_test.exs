defmodule SuchConfigDesktop.ProjectVault.AiIgnoreTemplatesTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.AiIgnoreTemplates

  setup do
    dir = Path.join(System.tmp_dir!(), "ai_templates_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "content_for includes secrets-safe polyglot baseline without root" do
    assert {:ok, body} = AiIgnoreTemplates.content_for(".cursorignore")
    assert body =~ ".env"
    assert body =~ ".env.*"
    assert body =~ "!.env.example"
    assert body =~ "node_modules/"
    assert body =~ "__pycache__/"
    assert body =~ "_build/"
    assert body =~ "deps/"
    assert body =~ "target/"
    assert body =~ "*.suchvault"
    refute body =~ "tightened from .gitignore"
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

  test "tightens deps section for Node project from package.json and .gitignore", %{dir: dir} do
    File.write!(Path.join(dir, "package.json"), ~s({"name":"demo"}\n))

    File.write!(
      Path.join(dir, ".gitignore"),
      """
      node_modules/
      dist/
      coverage/
      .nocciolo/local/
      .nocciolo/cache/
      *.tsbuildinfo
      .env
      .env.*
      !.env.example
      """
    )

    assert :ok = AiIgnoreTemplates.write_if_missing(dir, ".cursorignore")
    body = File.read!(Path.join(dir, ".cursorignore"))

    assert body =~ "tightened from .gitignore"
    assert body =~ "node_modules/"
    assert body =~ "dist/"
    assert body =~ "# From project .gitignore"
    assert body =~ "coverage/"
    assert body =~ ".nocciolo/local/"
    assert body =~ ".nocciolo/cache/"
    assert body =~ "*.tsbuildinfo"
    refute body =~ "__pycache__/"
    refute body =~ "_build/"
    refute body =~ "\ndeps/\n"
    refute body =~ "target/"
  end

  test "includes elixir build paths when mix.exs present", %{dir: dir} do
    File.write!(Path.join(dir, "mix.exs"), "defmodule Demo.MixProject do\nend\n")
    File.write!(Path.join(dir, ".gitignore"), "_build/\ndeps/\ncover/\n")

    assert {:ok, body} = AiIgnoreTemplates.content_for(".cursorignore", dir)
    assert body =~ "_build/"
    assert body =~ "deps/"
    assert body =~ "cover/"
    refute body =~ "node_modules/"
    refute body =~ "__pycache__/"
  end

  test "empty project without manifests keeps polyglot baseline", %{dir: dir} do
    assert {:ok, body} = AiIgnoreTemplates.content_for(".cursorignore", dir)
    assert body =~ "node_modules/"
    assert body =~ "_build/"
    assert body =~ "target/"
    assert body =~ "__pycache__/"
    refute body =~ "tightened from .gitignore"
  end
end
