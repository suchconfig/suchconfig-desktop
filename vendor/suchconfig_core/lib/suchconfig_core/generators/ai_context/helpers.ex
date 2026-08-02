defmodule SuchConfigCore.Generators.AIContext.Helpers do
  @moduledoc """
  Shared helper functions for AI context generation.

  Contains utility functions for formatting, file detection, and common
  transformations used across language-specific generators.
  """

  def format_project_type(type) do
    case type do
      :node -> "Node.js"
      :elixir -> "Elixir"
      :python -> "Python"
      :rust -> "Rust"
      :go -> "Go"
      :ruby -> "Ruby"
      :mixed_elixir -> "Full-stack (Elixir)"
      :mixed_ruby -> "Full-stack (Ruby)"
      _ -> nil
    end
  end

  def format_framework(framework) do
    case framework do
      "next" -> "Next.js"
      "nuxt" -> "Nuxt.js"
      "react" -> "React"
      "vue" -> "Vue.js"
      "angular" -> "Angular"
      "svelte" -> "SvelteKit"
      "express" -> "Express.js"
      "fastify" -> "Fastify"
      "rails" -> "Ruby on Rails"
      "sinatra" -> "Sinatra"
      "hanami" -> "Hanami"
      "grape" -> "Grape"
      "roda" -> "Roda"
      "padrino" -> "Padrino"
      other -> String.capitalize(to_string(other))
    end
  end

  def format_monorepo_tool(tool) do
    case tool do
      "nx" -> "Nx"
      "turborepo" -> "Turborepo"
      "lerna" -> "Lerna"
      "pnpm-workspaces" -> "pnpm Workspaces"
      "rush" -> "Rush"
      other -> String.capitalize(to_string(other))
    end
  end

  def format_test_framework(framework) do
    case framework do
      "vitest" -> "Vitest"
      "jest" -> "Jest"
      "cypress" -> "Cypress"
      "playwright" -> "Playwright"
      "pytest" -> "pytest"
      "rspec" -> "RSpec"
      "minitest" -> "Minitest"
      other -> String.capitalize(to_string(other))
    end
  end

  def describe_script(name) do
    case name do
      "dev" -> "Start development server"
      "build" -> "Build for production"
      "start" -> "Start production server"
      "test" -> "Run tests"
      "lint" -> "Run linter"
      "format" -> "Format code"
      "typecheck" -> "Run TypeScript type checking"
      "db:migrate" -> "Run database migrations"
      "db:seed" -> "Seed database"
      "db:push" -> "Push schema to database"
      "db:studio" -> "Open database GUI"
      "db:generate" -> "Generate database types"
      "db:setup" -> "Set up database"
      "storybook" -> "Start Storybook"
      "preview" -> "Preview production build"
      "clean" -> "Clean build artifacts"
      _ -> "Run #{name}"
    end
  end

  def describe_make_target(target) do
    case target do
      "dev" -> "Start development"
      "build" -> "Build project"
      "test" -> "Run tests"
      "lint" -> "Run linter"
      "format" -> "Format code"
      "clean" -> "Clean build"
      "install" -> "Install dependencies"
      "deploy" -> "Deploy application"
      _ -> "Run #{target}"
    end
  end

  def describe_workflow(filename, name) do
    name_lower = String.downcase(name)
    file_lower = String.downcase(filename)

    cond do
      String.contains?(name_lower, "test") or String.contains?(file_lower, "test") -> "Runs test suite"
      String.contains?(name_lower, "lint") or String.contains?(file_lower, "lint") -> "Runs linting checks"
      String.contains?(name_lower, "ci") or String.contains?(file_lower, "ci") -> "Continuous integration checks"
      String.contains?(name_lower, "deploy") or String.contains?(file_lower, "deploy") -> "Deployment workflow"
      String.contains?(name_lower, "release") or String.contains?(file_lower, "release") -> "Release automation"
      String.contains?(name_lower, "publish") or String.contains?(file_lower, "publish") -> "Package publishing"
      String.contains?(name_lower, "build") or String.contains?(file_lower, "build") -> "Build process"
      String.contains?(name_lower, "docs") or String.contains?(file_lower, "docs") -> "Documentation generation"
      String.contains?(name_lower, "codeql") or String.contains?(file_lower, "codeql") -> "Security analysis"
      String.contains?(name_lower, "label") or String.contains?(file_lower, "label") -> "Issue/PR labeling"
      String.contains?(name_lower, "stale") or String.contains?(file_lower, "stale") -> "Stale issue management"
      String.contains?(name_lower, "lock") or String.contains?(file_lower, "lock") -> "Issue locking"
      String.contains?(name_lower, "issue") or String.contains?(file_lower, "issue") -> "Issue management"
      String.contains?(name_lower, "sponsor") or String.contains?(file_lower, "sponsor") -> "Sponsor workflow"
      String.contains?(name_lower, "comment") or String.contains?(file_lower, "comment") -> "Comment automation"
      String.contains?(name_lower, "pr") or String.contains?(file_lower, "pr") -> "Pull request automation"
      true -> "Workflow automation"
    end
  end

  def find_file(files, type) when is_atom(type) do
    Enum.find(files, &(&1[:type] == type))
  end

  def filter_files(files, type) when is_atom(type) do
    Enum.filter(files, &(&1[:type] == type))
  end

  def has_file?(files, type) when is_atom(type) do
    Enum.any?(files, &(&1[:type] == type))
  end

  def detect_github_actions(path) when is_binary(path) do
    workflows_path = Path.join([path, ".github", "workflows"])

    if File.dir?(workflows_path) do
      workflows_path
      |> File.ls!()
      |> Enum.filter(fn f -> String.ends_with?(f, ".yml") or String.ends_with?(f, ".yaml") end)
      |> Enum.map(fn f ->
        file_path = Path.join(workflows_path, f)

        name =
          case File.read(file_path) do
            {:ok, content} ->
              case Regex.run(~r/name:\s*["']?([^"'\n]+)["']?/, content) do
                [_, n] -> n
                _ -> Path.rootname(f)
              end

            _ ->
              Path.rootname(f)
          end

        description = describe_workflow(Path.rootname(f), name)

        %{name: name, file: f, description: description}
      end)
    else
      []
    end
  end

  def detect_github_actions(_), do: []

  def detect_directory_structure(path) do
    important_dirs = [
      "app",
      "pages",
      "src",
      "lib",
      "components",
      "hooks",
      "utils",
      "api",
      "public",
      "assets",
      "styles",
      "types",
      "config",
      "scripts",
      "test",
      "tests",
      "__tests__",
      "e2e",
      "prisma",
      ".github",
      "spec",
      "db",
      "bin",
      "vendor",
      "controllers",
      "models",
      "views",
      "helpers",
      "mailers",
      "jobs",
      "channels",
      "services"
    ]

    existing_dirs =
      important_dirs
      |> Enum.filter(fn dir -> File.dir?(Path.join(path, dir)) end)
      |> Enum.take(12)

    existing_dirs
    |> Enum.map_join("\n", fn dir ->
      subdirs = get_subdirs(Path.join(path, dir))

      if length(subdirs) > 0 do
        subdir_lines =
          subdirs
          |> Enum.take(4)
          |> Enum.map_join("\n", fn sub -> "│   └── #{sub}/" end)

        "├── #{dir}/\n#{subdir_lines}"
      else
        "├── #{dir}/"
      end
    end)
  end

  defp get_subdirs(path) do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.filter(fn f ->
          full_path = Path.join(path, f)
          File.dir?(full_path) and not String.starts_with?(f, ".")
        end)
        |> Enum.take(5)

      _ ->
        []
    end
  end
end
