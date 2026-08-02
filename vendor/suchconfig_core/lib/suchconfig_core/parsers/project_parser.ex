defmodule SuchConfigCore.Parsers.ProjectParser do
  @moduledoc """
  Project configuration file parser for the Workflow Wizard.

  This module scans project directories for configuration files and parses them
  to extract relevant information for generating setup plans.

  ## Supported Files

  - `package.json` - Node.js project configuration
  - `mix.exs` - Elixir project configuration
  - `Makefile` - Make build targets
  - `Dockerfile` - Docker container configuration
  - `docker-compose.yml` / `docker-compose.yaml` - Docker Compose services
  - `README.md` - Project documentation
  - `.env.example` / `.env.sample` - Environment variable templates
  - `.nvmrc` / `.node-version` - Node version specification
  - `.tool-versions` - asdf version manager configuration

  ## Examples

      iex> SuchConfigCore.Parsers.ProjectParser.scan_project("/path/to/project")
      {:ok, %{
        project_type: :node,
        files: [%{name: "package.json", path: "/path/to/project/package.json", ...}],
        ...
      }}

  """

  @config_files [
    "package.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "package-lock.json",
    "bun.lockb",
    "mix.exs",
    "Makefile",
    "Dockerfile",
    "docker-compose.yml",
    "docker-compose.yaml",
    "README.md",
    "readme.md",
    "CONTRIBUTING.md",
    "contributing.md",
    "AGENTS.md",
    "CODE_OF_CONDUCT.md",
    "SECURITY.md",
    "LICENSE",
    "LICENSE.md",
    "LICENSE.txt",
    "CITATION.cff",
    "requirements.txt",
    "requirements-dev.txt",
    "requirements-test.txt",
    "requirements-tests.txt",
    "requirements-docs.txt",
    "requirements-docs-tests.txt",
    "requirements-github-actions.txt",
    "requirements-translations.txt",
    "setup.py",
    "setup.cfg",
    "tox.ini",
    "noxfile.py",
    ".env.example",
    ".env.sample",
    ".env.local.example",
    ".nvmrc",
    ".node-version",
    ".tool-versions",
    "tsconfig.json",
    "jsconfig.json",
    "drizzle.config.ts",
    "drizzle.config.js",
    "prisma/schema.prisma",
    "vite.config.js",
    "vite.config.ts",
    "webpack.config.js",
    "next.config.js",
    "next.config.ts",
    "next.config.mjs",
    "nuxt.config.js",
    "nuxt.config.ts",
    "angular.json",
    "vue.config.js",
    "tailwind.config.js",
    "tailwind.config.ts",
    "postcss.config.js",
    "postcss.config.mjs",
    ".prettierrc",
    ".prettierrc.json",
    ".prettierrc.js",
    "prettier.config.js",
    "prettier.config.mjs",
    ".eslintrc.json",
    ".eslintrc.js",
    ".eslintrc.yaml",
    ".eslintrc.yml",
    "eslint.config.js",
    "eslint.config.mjs",
    "biome.json",
    "biome.jsonc",
    ".stylelintrc",
    ".stylelintrc.json",
    "stylelint.config.js",
    ".gitlab-ci.yml",
    "bitbucket-pipelines.yml",
    ".circleci/config.yml",
    "Jenkinsfile",
    ".travis.yml",
    ".pre-commit-config.yaml",
    ".commitlintrc",
    ".commitlintrc.json",
    ".commitlintrc.js",
    "commitlint.config.js",
    ".czrc",
    "commitizen.config.js",
    ".cz.json",
    "CODEOWNERS",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/dependabot.yml",
    "pnpm-workspace.yaml",
    "lerna.json",
    "nx.json",
    "turbo.json",
    "rush.json",
    "vitest.config.ts",
    "vitest.config.js",
    "jest.config.js",
    "jest.config.ts",
    "jest.config.json",
    "cypress.config.js",
    "cypress.config.ts",
    "playwright.config.ts",
    "playwright.config.js",
    "pyproject.toml",
    "requirements.txt",
    "Cargo.toml",
    "go.mod",
    "go.sum",
    ".air.toml",
    ".golangci.yml",
    ".golangci.yaml",
    ".goreleaser.yml",
    ".goreleaser.yaml",
    "vercel.json",
    "netlify.toml",
    "fly.toml",
    "railway.json",
    "render.yaml",
    "CLAUDE.md",
    ".cursorrules",
    ".cursorignore",
    ".suchconfig.yml",
    ".suchconfig.yaml",
    ".suchconfig.json",
    "Gemfile",
    "Gemfile.lock",
    ".ruby-version",
    ".ruby-gemset",
    ".rvmrc",
    ".rubocop.yml",
    ".rubocop_todo.yml",
    ".standard.yml",
    ".yardopts",
    "Rakefile",
    "config.ru",
    "Brewfile",
    ".mdlrc",
    "rails.gemspec",
    "config/database.yml",
    "config/routes.rb",
    "config/application.rb",
    "db/schema.rb",
    "db/structure.sql",
    "bin/rails",
    "bin/rake",
    "bin/spring",
    ".rspec",
    "spec/spec_helper.rb",
    "spec/rails_helper.rb",
    "Guardfile",
    ".simplecov",
    "Procfile",
    "Procfile.dev",
    "config/puma.rb",
    "config/unicorn.rb",
    ".foreman"
  ]

  @doc """
  Scans a project directory for configuration files and parses them.

  Returns structured data about the project type, detected files, and parsed content.

  ## Parameters

  - `path` - The absolute path to the project directory

  ## Returns

  - `{:ok, project_data}` - Successfully scanned project data
  - `{:error, reason}` - Error message if scanning failed

  ## Examples

      iex> scan_project("/home/user/my-react-app")
      {:ok, %{
        project_type: :node,
        framework: "react",
        files: [...],
        dependencies: [...],
        scripts: [...],
        ...
      }}

  """
  def scan_project(path) when is_binary(path) do
    case File.dir?(path) do
      true ->
        detected_files = detect_config_files(path)
        workflow_files = detect_workflow_directories(path)
        all_files = detected_files ++ workflow_files
        parsed_files = Enum.map(all_files, &parse_file/1)

        project_data = %{
          path: path,
          project_name: Path.basename(path),
          files: parsed_files,
          project_type: detect_project_type(parsed_files),
          framework: detect_framework(parsed_files),
          dependencies: extract_dependencies(parsed_files),
          scripts: extract_scripts(parsed_files),
          env_vars: extract_env_vars(parsed_files),
          docker_config: extract_docker_config(parsed_files),
          node_version: extract_node_version(parsed_files),
          elixir_version: extract_elixir_version(parsed_files),
          ruby_version: extract_ruby_version(parsed_files),
          go_version: extract_go_version(parsed_files),
          python_version: extract_python_version(parsed_files),
          make_targets: extract_make_targets(parsed_files),
          ci_config: extract_ci_config(parsed_files),
          git_workflow: extract_git_workflow(parsed_files),
          code_quality: extract_code_quality(parsed_files),
          testing_config: extract_testing_config(parsed_files),
          monorepo_config: extract_monorepo_config(parsed_files),
          ai_context_files: extract_ai_context_files(parsed_files),
          scanned_at: DateTime.utc_now()
        }

        {:ok, project_data}

      false ->
        {:error, "Path does not exist or is not a directory: #{path}"}
    end
  end

  def scan_project(_), do: {:error, "Invalid path provided"}

  @doc """
  Scans a project from file contents provided as a map.

  This is useful when files are read externally (e.g., via Tauri) and passed in.

  ## Parameters

  - `project_name` - Name of the project
  - `files_map` - Map of filename to file content

  ## Returns

  - `{:ok, project_data}` - Successfully parsed project data

  """
  def scan_from_contents(project_name, files_map) when is_map(files_map) do
    parsed_files =
      files_map
      |> Enum.map(fn {filename, content} ->
        parse_file_content(filename, content)
      end)
      |> Enum.reject(&is_nil/1)

    project_data = %{
      path: nil,
      project_name: project_name,
      files: parsed_files,
      project_type: detect_project_type(parsed_files),
      framework: detect_framework(parsed_files),
      dependencies: extract_dependencies(parsed_files),
      scripts: extract_scripts(parsed_files),
      env_vars: extract_env_vars(parsed_files),
      docker_config: extract_docker_config(parsed_files),
      node_version: extract_node_version(parsed_files),
      elixir_version: extract_elixir_version(parsed_files),
      ruby_version: extract_ruby_version(parsed_files),
      go_version: extract_go_version(parsed_files),
      python_version: extract_python_version(parsed_files),
      make_targets: extract_make_targets(parsed_files),
      ci_config: extract_ci_config(parsed_files),
      git_workflow: extract_git_workflow(parsed_files),
      code_quality: extract_code_quality(parsed_files),
      testing_config: extract_testing_config(parsed_files),
      monorepo_config: extract_monorepo_config(parsed_files),
      ai_context_files: extract_ai_context_files(parsed_files),
      scanned_at: DateTime.utc_now()
    }

    {:ok, project_data}
  end

  defp detect_config_files(path) do
    @config_files
    |> Enum.map(fn filename ->
      file_path = Path.join(path, filename)

      if File.exists?(file_path) do
        %{name: filename, path: file_path}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp detect_workflow_directories(path) do
    workflow_files = []

    workflow_files =
      case list_github_workflows(path) do
        {:ok, files} -> workflow_files ++ files
        _ -> workflow_files
      end

    workflow_files =
      case list_husky_hooks(path) do
        {:ok, files} -> workflow_files ++ files
        _ -> workflow_files
      end

    workflow_files =
      case list_github_issue_templates(path) do
        {:ok, files} -> workflow_files ++ files
        _ -> workflow_files
      end

    workflow_files =
      case list_storybook_files(path) do
        {:ok, files} -> workflow_files ++ files
        _ -> workflow_files
      end

    workflow_files
  end

  defp list_github_workflows(path) do
    workflows_dir = Path.join(path, ".github/workflows")

    if File.dir?(workflows_dir) do
      files =
        File.ls!(workflows_dir)
        |> Enum.filter(&String.ends_with?(&1, [".yml", ".yaml"]))
        |> Enum.map(fn file ->
          %{name: ".github/workflows/#{file}", path: Path.join(workflows_dir, file)}
        end)

      {:ok, files}
    else
      {:error, :not_found}
    end
  end

  defp list_husky_hooks(path) do
    husky_dir = Path.join(path, ".husky")

    if File.dir?(husky_dir) do
      files =
        File.ls!(husky_dir)
        |> Enum.reject(fn f -> String.starts_with?(f, "_") or String.starts_with?(f, ".") end)
        |> Enum.map(fn file ->
          %{name: ".husky/#{file}", path: Path.join(husky_dir, file)}
        end)

      {:ok, files}
    else
      {:error, :not_found}
    end
  end

  defp list_github_issue_templates(path) do
    templates_dir = Path.join(path, ".github/ISSUE_TEMPLATE")

    if File.dir?(templates_dir) do
      files =
        File.ls!(templates_dir)
        |> Enum.filter(&String.ends_with?(&1, [".md", ".yml", ".yaml"]))
        |> Enum.map(fn file ->
          %{name: ".github/ISSUE_TEMPLATE/#{file}", path: Path.join(templates_dir, file)}
        end)

      {:ok, files}
    else
      {:error, :not_found}
    end
  end

  defp list_storybook_files(path) do
    storybook_dir = Path.join(path, ".storybook")

    if File.dir?(storybook_dir) do
      files =
        File.ls!(storybook_dir)
        |> Enum.filter(&String.ends_with?(&1, [".js", ".ts", ".jsx", ".tsx"]))
        |> Enum.take(5)
        |> Enum.map(fn file ->
          %{name: ".storybook/#{file}", path: Path.join(storybook_dir, file)}
        end)

      {:ok, files}
    else
      {:error, :not_found}
    end
  end

  defp parse_file(%{name: filename, path: file_path}) do
    case File.read(file_path) do
      {:ok, content} ->
        parse_file_content(filename, content)
        |> Map.put(:path, file_path)

      {:error, _} ->
        %{name: filename, path: file_path, parsed: false, error: "Could not read file"}
    end
  end

  defp parse_file_content(filename, content) do
    parsed_data =
      cond do
        filename == "package.json" ->
          parse_package_json(content)

        filename == "pnpm-lock.yaml" ->
          %{type: :lock_file, package_manager: "pnpm"}

        filename == "yarn.lock" ->
          %{type: :lock_file, package_manager: "yarn"}

        filename == "package-lock.json" ->
          %{type: :lock_file, package_manager: "npm"}

        filename == "bun.lockb" ->
          %{type: :lock_file, package_manager: "bun"}

        filename == "mix.exs" ->
          parse_mix_exs(content)

        filename == "Makefile" ->
          parse_makefile(content)

        filename == "Dockerfile" ->
          parse_dockerfile(content)

        filename in ["docker-compose.yml", "docker-compose.yaml"] ->
          parse_docker_compose(content)

        filename in ["README.md", "readme.md"] ->
          parse_readme(content)

        filename in ["CONTRIBUTING.md", "contributing.md"] ->
          parse_contributing(content)

        filename == "AGENTS.md" ->
          parse_agents_md(content)

        filename == "CODE_OF_CONDUCT.md" ->
          %{type: :code_of_conduct, has_content: byte_size(content) > 100}

        filename == "SECURITY.md" ->
          parse_security_md(content)

        filename in [".env.example", ".env.sample", ".env.local.example"] ->
          parse_env_example(content)

        filename in [".nvmrc", ".node-version"] ->
          parse_node_version_file(content)

        filename == ".tool-versions" ->
          parse_tool_versions(content)

        filename == "tsconfig.json" ->
          parse_tsconfig(content)

        filename in ["drizzle.config.ts", "drizzle.config.js"] ->
          %{type: :drizzle_config, orm: "drizzle"}

        filename == "prisma/schema.prisma" ->
          %{type: :prisma_schema, orm: "prisma"}

        filename in ["vite.config.js", "vite.config.ts"] ->
          %{type: :vite_config, bundler: "vite"}

        filename == "webpack.config.js" ->
          %{type: :webpack_config, bundler: "webpack"}

        filename in ["next.config.js", "next.config.ts", "next.config.mjs"] ->
          %{type: :next_config, framework: "next"}

        filename in ["nuxt.config.js", "nuxt.config.ts"] ->
          %{type: :nuxt_config, framework: "nuxt"}

        filename == "angular.json" ->
          %{type: :angular_config, framework: "angular"}

        filename == "vue.config.js" ->
          %{type: :vue_config, framework: "vue"}

        filename in ["tailwind.config.js", "tailwind.config.ts"] ->
          %{type: :tailwind_config, styling: "tailwindcss"}

        filename in ["postcss.config.js", "postcss.config.mjs"] ->
          %{type: :postcss_config}

        filename == "vercel.json" ->
          %{type: :vercel_config, deployment: "vercel"}

        filename == "netlify.toml" ->
          %{type: :netlify_config, deployment: "netlify"}

        filename == "fly.toml" ->
          %{type: :fly_config, deployment: "fly"}

        filename == "railway.json" ->
          %{type: :railway_config, deployment: "railway"}

        filename == "pyproject.toml" ->
          parse_pyproject(content)

        filename == "requirements.txt" ->
          parse_requirements_txt(content, :main)

        String.starts_with?(filename, "requirements-") and String.ends_with?(filename, ".txt") ->
          req_type = filename |> String.replace("requirements-", "") |> String.replace(".txt", "") |> String.to_atom()
          parse_requirements_txt(content, req_type)

        filename in ["LICENSE", "LICENSE.md", "LICENSE.txt"] ->
          parse_license(content)

        filename == "CITATION.cff" ->
          parse_citation_cff(content)

        filename == "setup.py" ->
          parse_setup_py(content)

        filename == "setup.cfg" ->
          parse_setup_cfg(content)

        filename == "tox.ini" ->
          parse_tox_ini(content)

        filename == "noxfile.py" ->
          parse_noxfile(content)

        filename == "Cargo.toml" ->
          parse_cargo_toml(content)

        filename == "go.mod" ->
          parse_go_mod(content)

        filename == "go.sum" ->
          parse_go_sum(content)

        filename == ".air.toml" ->
          parse_air_toml(content)

        filename in [".golangci.yml", ".golangci.yaml"] ->
          parse_golangci(content)

        filename in [".goreleaser.yml", ".goreleaser.yaml"] ->
          %{type: :goreleaser_config, has_content: byte_size(content) > 10}

        filename == "jsconfig.json" ->
          parse_jsconfig(content)

        String.starts_with?(filename, ".github/workflows/") ->
          parse_github_workflow(content, filename)

        filename == ".gitlab-ci.yml" ->
          parse_gitlab_ci(content)

        filename == "bitbucket-pipelines.yml" ->
          parse_bitbucket_pipelines(content)

        filename == ".circleci/config.yml" ->
          parse_circleci_config(content)

        filename == "Jenkinsfile" ->
          parse_jenkinsfile(content)

        filename == ".travis.yml" ->
          parse_travis_ci(content)

        String.starts_with?(filename, ".husky/") ->
          parse_husky_hook(content, filename)

        filename == ".pre-commit-config.yaml" ->
          parse_pre_commit_config(content)

        filename in [".commitlintrc", ".commitlintrc.json", ".commitlintrc.js", "commitlint.config.js"] ->
          parse_commitlint_config(content)

        filename in [".czrc", "commitizen.config.js", ".cz.json"] ->
          parse_commitizen_config(content)

        filename == "CODEOWNERS" ->
          parse_codeowners(content)

        filename == ".github/PULL_REQUEST_TEMPLATE.md" ->
          parse_pr_template(content)

        String.starts_with?(filename, ".github/ISSUE_TEMPLATE/") ->
          parse_issue_template(content, filename)

        filename == ".github/dependabot.yml" ->
          parse_dependabot_config(content)

        filename in [".eslintrc.json", ".eslintrc.js", ".eslintrc.yaml", ".eslintrc.yml"] ->
          parse_eslint_config(content, filename)

        filename in ["eslint.config.js", "eslint.config.mjs"] ->
          parse_eslint_flat_config(content)

        filename in [".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js", "prettier.config.mjs"] ->
          parse_prettier_config(content, filename)

        filename in ["biome.json", "biome.jsonc"] ->
          parse_biome_config(content)

        filename in [".stylelintrc", ".stylelintrc.json", "stylelint.config.js"] ->
          parse_stylelint_config(content)

        filename == "pnpm-workspace.yaml" ->
          parse_pnpm_workspace(content)

        filename == "lerna.json" ->
          parse_lerna_config(content)

        filename == "nx.json" ->
          parse_nx_config(content)

        filename == "turbo.json" ->
          parse_turbo_config(content)

        filename == "rush.json" ->
          parse_rush_config(content)

        filename in ["vitest.config.ts", "vitest.config.js"] ->
          parse_vitest_config(content)

        filename in ["jest.config.js", "jest.config.ts", "jest.config.json"] ->
          parse_jest_config(content, filename)

        filename in ["cypress.config.js", "cypress.config.ts"] ->
          parse_cypress_config(content)

        filename in ["playwright.config.ts", "playwright.config.js"] ->
          parse_playwright_config(content)

        String.starts_with?(filename, ".storybook/") ->
          parse_storybook_config(content, filename)

        filename == "render.yaml" ->
          %{type: :render_config, deployment: "render"}

        filename == "CLAUDE.md" ->
          parse_claude_md(content)

        filename == ".cursorrules" ->
          parse_cursorrules(content)

        filename == ".cursorignore" ->
          parse_cursorignore(content)

        filename in [".suchconfig.yml", ".suchconfig.yaml", ".suchconfig.json"] ->
          parse_suchconfig(content)

        filename == "Gemfile" ->
          parse_gemfile(content)

        filename == "Gemfile.lock" ->
          parse_gemfile_lock(content)

        filename in [".ruby-version", ".ruby-gemset"] ->
          parse_ruby_version_file(content)

        filename == ".rvmrc" ->
          parse_rvmrc(content)

        filename in [".rubocop.yml", ".rubocop_todo.yml"] ->
          parse_rubocop_config(content)

        filename == ".standard.yml" ->
          parse_standard_rb_config(content)

        filename == ".yardopts" ->
          %{type: :yardopts, has_yard: true}

        filename == "Rakefile" ->
          parse_rakefile(content)

        filename == "config.ru" ->
          parse_rack_config(content)

        filename == "Brewfile" ->
          parse_brewfile(content)

        filename == ".mdlrc" ->
          %{type: :mdlrc, has_markdownlint: true}

        String.ends_with?(filename, ".gemspec") ->
          parse_gemspec(content)

        filename == "config/database.yml" ->
          parse_database_yml(content)

        filename == "config/routes.rb" ->
          parse_routes_rb(content)

        filename == "config/application.rb" ->
          parse_application_rb(content)

        filename in ["db/schema.rb", "db/structure.sql"] ->
          parse_db_schema(content, filename)

        filename in ["bin/rails", "bin/rake", "bin/spring"] ->
          %{type: :rails_bin, executable: filename, is_rails: true}

        filename == ".rspec" ->
          parse_rspec_config(content)

        filename in ["spec/spec_helper.rb", "spec/rails_helper.rb"] ->
          parse_spec_helper(content, filename)

        filename == "Guardfile" ->
          parse_guardfile(content)

        filename == ".simplecov" ->
          %{type: :simplecov, has_coverage: true}

        filename in ["Procfile", "Procfile.dev"] ->
          parse_procfile(content, filename)

        filename in ["config/puma.rb", "config/unicorn.rb"] ->
          parse_server_config(content, filename)

        filename == ".foreman" ->
          %{type: :foreman_config}

        true ->
          %{type: :unknown}
      end

    Map.merge(
      %{name: filename, parsed: true, content_preview: String.slice(content, 0, 500)},
      parsed_data
    )
  end

  @doc """
  Parses a package.json file and extracts relevant information.
  """
  def parse_package_json(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        %{
          type: :package_json,
          name: Map.get(json, "name"),
          version: Map.get(json, "version"),
          description: Map.get(json, "description"),
          scripts: Map.get(json, "scripts", %{}),
          dependencies: Map.get(json, "dependencies", %{}),
          dev_dependencies: Map.get(json, "devDependencies", %{}),
          engines: Map.get(json, "engines", %{}),
          main: Map.get(json, "main"),
          module: Map.get(json, "module"),
          module_type: Map.get(json, "type")
        }

      {:error, _} ->
        %{type: :package_json, error: "Invalid JSON"}
    end
  end

  @doc """
  Parses a mix.exs file and extracts relevant information.
  """
  def parse_mix_exs(content) when is_binary(content) do
    elixir_version = extract_regex(content, ~r/elixir:\s*"([^"]+)"/)
    app_name = extract_regex(content, ~r/app:\s*:(\w+)/)
    version = extract_regex(content, ~r/version:\s*"([^"]+)"/)

    deps =
      case Regex.run(~r/defp?\s+deps\s+do\s*\[([\s\S]*?)\]\s*end/m, content) do
        [_, deps_content] ->
          Regex.scan(~r/\{:(\w+),\s*"([^"]+)"/, deps_content)
          |> Enum.map(fn [_, name, version] -> %{name: name, version: version} end)

        _ ->
          []
      end

    aliases =
      case Regex.run(~r/defp?\s+aliases\s+do\s*\[([\s\S]*?)\]\s*end/m, content) do
        [_, aliases_content] ->
          Regex.scan(~r/(\w+):\s*\[/, aliases_content)
          |> Enum.map(fn [_, name] -> name end)

        _ ->
          []
      end

    %{
      type: :mix_exs,
      app_name: app_name,
      version: version,
      elixir_version: elixir_version,
      dependencies: deps,
      aliases: aliases
    }
  end

  @doc """
  Parses a Makefile and extracts targets.
  """
  def parse_makefile(content) when is_binary(content) do
    targets =
      Regex.scan(~r/^([a-zA-Z_][a-zA-Z0-9_-]*):/m, content)
      |> Enum.map(fn [_, target] -> target end)
      |> Enum.reject(&String.starts_with?(&1, "."))
      |> Enum.uniq()

    phony_targets =
      case Regex.run(~r/\.PHONY:\s*(.+)$/m, content) do
        [_, targets_str] -> String.split(targets_str, ~r/\s+/, trim: true)
        _ -> []
      end

    %{
      type: :makefile,
      targets: targets,
      phony_targets: phony_targets
    }
  end

  @doc """
  Parses a Dockerfile and extracts relevant information.
  """
  def parse_dockerfile(content) when is_binary(content) do
    base_image = extract_regex(content, ~r/^FROM\s+([^\s]+)/m)
    exposed_ports = Regex.scan(~r/^EXPOSE\s+(\d+)/m, content) |> Enum.map(fn [_, p] -> p end)
    workdir = extract_regex(content, ~r/^WORKDIR\s+([^\s]+)/m)

    env_vars =
      Regex.scan(~r/^ENV\s+([^\s=]+)/m, content)
      |> Enum.map(fn [_, var] -> var end)

    %{
      type: :dockerfile,
      base_image: base_image,
      exposed_ports: exposed_ports,
      workdir: workdir,
      env_vars: env_vars
    }
  end

  @doc """
  Parses a docker-compose.yml file.
  """
  def parse_docker_compose(content) when is_binary(content) do
    services =
      Regex.scan(~r/^\s{2}([a-zA-Z_][a-zA-Z0-9_-]*):/m, content)
      |> Enum.map(fn [_, service] -> service end)

    %{
      type: :docker_compose,
      services: services
    }
  end

  defp parse_readme(content) do
    title =
      case Regex.run(~r/^#\s+(.+)$/m, content) do
        [_, t] -> String.trim(t)
        _ -> nil
      end

    has_installation = String.contains?(content, ["## Installation", "## Install", "## Setup"])
    has_usage = String.contains?(content, ["## Usage", "## Getting Started", "## Quick Start"])

    %{
      type: :readme,
      title: title,
      has_installation_section: has_installation,
      has_usage_section: has_usage,
      word_count: content |> String.split(~r/\s+/) |> length(),
      content_preview: String.slice(content, 0, 5000)
    }
  end

  defp parse_contributing(content) do
    requirements = extract_contributing_requirements(content)
    setup_steps = extract_contributing_setup_steps(content)
    coding_guidelines = extract_coding_guidelines(content)
    issue_conventions = extract_issue_conventions(content)
    ways_to_contribute = extract_ways_to_contribute(content)
    contribution_sections = extract_contribution_sections(content)

    %{
      type: :contributing,
      has_content: byte_size(content) > 100,
      requirements: requirements,
      setup_steps: setup_steps,
      coding_guidelines: coding_guidelines,
      issue_conventions: issue_conventions,
      ways_to_contribute: ways_to_contribute,
      contribution_sections: contribution_sections,
      has_docker_setup: String.contains?(content, ["docker compose", "docker-compose", "Docker"]),
      has_monorepo_info: String.contains?(content, ["monorepo", "workspace", "packages/"]),
      has_virtual_env: String.contains?(content, ["venv", "virtualenv", "virtual environment"]),
      has_pre_commit: String.contains?(content, ["pre-commit", "pre_commit"]),
      has_tests_section: String.contains?(content, ["## Test", "### Test", "Running Tests", "Run Tests"]),
      word_count: content |> String.split(~r/\s+/) |> length(),
      content_preview: String.slice(content, 0, 12_000)
    }
  end

  defp extract_contribution_sections(content) do
    sections = []

    sections =
      if Regex.match?(~r/##\s*(?:Development|Local Development|Dev Setup)/i, content) do
        section_content = extract_section_content(content, ~r/##\s*(?:Development|Local Development|Dev Setup)/i)
        sections ++ [%{title: "Development Setup", content: String.slice(section_content, 0, 1000)}]
      else
        sections
      end

    sections =
      if Regex.match?(~r/##\s*(?:Testing|Tests|Running Tests)/i, content) do
        section_content = extract_section_content(content, ~r/##\s*(?:Testing|Tests|Running Tests)/i)
        sections ++ [%{title: "Testing", content: String.slice(section_content, 0, 1000)}]
      else
        sections
      end

    sections =
      if Regex.match?(~r/##\s*(?:Code Style|Coding Style|Style Guide)/i, content) do
        section_content = extract_section_content(content, ~r/##\s*(?:Code Style|Coding Style|Style Guide)/i)
        sections ++ [%{title: "Code Style", content: String.slice(section_content, 0, 1000)}]
      else
        sections
      end

    sections =
      if Regex.match?(~r/##\s*(?:Documentation|Docs)/i, content) do
        section_content = extract_section_content(content, ~r/##\s*(?:Documentation|Docs)/i)
        sections ++ [%{title: "Documentation", content: String.slice(section_content, 0, 1000)}]
      else
        sections
      end

    sections
  end

  defp extract_section_content(content, header_regex) do
    case Regex.run(header_regex, content, return: :index) do
      [{start_pos, _}] ->
        rest = String.slice(content, start_pos, String.length(content))

        case Regex.run(~r/\n##\s+[A-Z]/, rest, return: :index) do
          [{end_pos, _}] -> String.slice(rest, 0, end_pos)
          nil -> String.slice(rest, 0, 2000)
        end

      nil ->
        ""
    end
  end

  defp extract_contributing_requirements(content) do
    requirements = %{
      node_version: nil,
      python_version: nil,
      docker_required: false,
      postgres_version: nil,
      redis_version: nil,
      memory_requirement: nil,
      other: []
    }

    requirements =
      case Regex.run(~r/Node\.?js\s+(?:version\s+)?(\d+(?:\.\d+)?(?:\+)?)/i, content) do
        [_, version] -> %{requirements | node_version: version}
        _ -> requirements
      end

    requirements =
      case Regex.run(~r/Python\s+(?:version\s+)?(\d+\.\d+(?:\+)?)/i, content) do
        [_, version] -> %{requirements | python_version: version}
        _ -> requirements
      end

    requirements =
      case Regex.run(~r/Postgres(?:ql)?\s+(?:version\s+)?v?(\d+(?:\.\d+)?)/i, content) do
        [_, version] -> %{requirements | postgres_version: version}
        _ -> requirements
      end

    requirements =
      case Regex.run(~r/Redis\s+(?:version\s+)?v?(\d+(?:\.\d+)?(?:\.\d+)?)/i, content) do
        [_, version] -> %{requirements | redis_version: version}
        _ -> requirements
      end

    requirements =
      case Regex.run(~r/(?:Minimum\s+)?(\d+)\s*GB\s*(?:RAM|memory)/i, content) do
        [_, mem] -> %{requirements | memory_requirement: "#{mem} GB RAM"}
        _ -> requirements
      end

    requirements =
      if String.contains?(content, ["Docker Engine", "Docker installed", "docker compose", "Docker Compose"]) do
        %{requirements | docker_required: true}
      else
        requirements
      end

    other_reqs =
      ~r/[-*]\s+(.+(?:installed|required|version).+)/i
      |> Regex.scan(content)
      |> Enum.map(fn [_, req] -> String.trim(req) end)
      |> Enum.take(10)

    %{requirements | other: other_reqs}
  end

  defp extract_contributing_setup_steps(content) do
    steps = []

    clone_step =
      case Regex.run(~r/```(?:bash|sh)?\n(git clone[^\n]+)\n/m, content) do
        [_, cmd] -> %{order: 1, title: "Clone the repository", command: String.trim(cmd)}
        _ -> nil
      end

    steps = if clone_step, do: steps ++ [clone_step], else: steps

    bash_blocks =
      ~r/```(?:bash|sh)?\n((?:[^\n]+\n)+?)```/m
      |> Regex.scan(content)
      |> Enum.map(fn [_, code] -> String.trim(code) end)
      |> Enum.reject(&String.contains?(&1, ["git clone", "example", "your-"]))
      |> Enum.take(8)

    numbered_steps =
      bash_blocks
      |> Enum.with_index(length(steps) + 1)
      |> Enum.map(fn {cmd, idx} ->
        title = infer_step_title(cmd)
        %{order: idx, title: title, command: cmd}
      end)

    steps ++ numbered_steps
  end

  defp infer_step_title(command) do
    cond do
      String.contains?(command, "docker compose up") or String.contains?(command, "docker-compose up") ->
        "Start Docker containers"

      String.contains?(command, "docker compose") or String.contains?(command, "docker-compose") ->
        "Run Docker command"

      String.contains?(command, ["pnpm install", "npm install", "yarn install", "bun install"]) ->
        "Install dependencies"

      String.contains?(command, ["pnpm dev", "npm run dev", "yarn dev"]) ->
        "Start development server"

      String.contains?(command, "setup.sh") or String.contains?(command, "./setup") ->
        "Run setup script"

      String.contains?(command, "chmod") ->
        "Set file permissions"

      String.contains?(command, "cd ") ->
        "Navigate to project directory"

      String.contains?(command, ["migrate", "db:"]) ->
        "Run database migrations"

      String.contains?(command, "seed") ->
        "Seed database"

      String.contains?(command, ["python -m venv", "virtualenv", "venv"]) ->
        "Create virtual environment"

      String.contains?(command, ["pip install", "pip3 install"]) ->
        "Install Python dependencies"

      String.contains?(command, ["poetry install", "pdm install", "hatch"]) ->
        "Install dependencies"

      String.contains?(command, "pre-commit install") ->
        "Install pre-commit hooks"

      String.contains?(command, "pre-commit run") ->
        "Run pre-commit hooks"

      String.contains?(command, "pytest") ->
        "Run tests"

      String.contains?(command, ["ruff", "mypy", "black", "isort"]) ->
        "Run linting/formatting"

      String.contains?(command, "uvicorn") ->
        "Start development server"

      String.contains?(command, "python manage.py runserver") ->
        "Start Django server"

      String.contains?(command, "flask run") ->
        "Start Flask server"

      String.contains?(command, "source") and String.contains?(command, "activate") ->
        "Activate virtual environment"

      true ->
        "Run command"
    end
  end

  defp extract_coding_guidelines(content) do
    guidelines = []

    guidelines =
      if String.contains?(content, ["ESLint", "eslint"]) do
        eslint_info =
          case Regex.run(~r/ESLint\s*(\d+)?/i, content) do
            [_, version] -> "ESLint #{version}"
            _ -> "ESLint"
          end

        guidelines ++ [%{tool: "linting", description: eslint_info}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["Prettier", "prettier"]) do
        guidelines ++ [%{tool: "formatting", description: "Prettier"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["Ruff", "ruff"]) do
        guidelines ++ [%{tool: "linting", description: "Ruff for linting and formatting"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["Black", "black"]) and not String.contains?(content, "blacklist") do
        guidelines ++ [%{tool: "formatting", description: "Black for code formatting"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["isort", "import sorting"]) do
        guidelines ++ [%{tool: "imports", description: "isort for import sorting"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["mypy", "type hints", "type checking"]) do
        guidelines ++ [%{tool: "types", description: "mypy for type checking"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["pytest", "unit test", "test suite"]) do
        guidelines ++ [%{tool: "testing", description: "pytest for testing"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["pre-commit", "pre_commit"]) do
        guidelines ++ [%{tool: "hooks", description: "pre-commit hooks required"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["TypeScript", "typescript", "type-aware"]) do
        guidelines ++ [%{tool: "types", description: "TypeScript required"}]
      else
        guidelines
      end

    guidelines =
      if Regex.match?(~r/PEP\s*8|pep8|pycodestyle/i, content) do
        guidelines ++ [%{tool: "style", description: "Follow PEP 8 style guide"}]
      else
        guidelines
      end

    guidelines =
      if Regex.match?(~r/docstring|google\s+style|numpy\s+style|sphinx/i, content) do
        guidelines ++ [%{tool: "documentation", description: "Docstrings required"}]
      else
        guidelines
      end

    guidelines =
      if String.contains?(content, ["coverage", "test coverage", "100%"]) do
        guidelines ++ [%{tool: "coverage", description: "Test coverage required"}]
      else
        guidelines
      end

    guidelines
  end

  defp extract_issue_conventions(content) do
    conventions = %{
      naming_patterns: [],
      templates_mentioned: false,
      labels_mentioned: false,
      branch_naming: nil,
      commit_convention: nil,
      pr_title_format: nil
    }

    naming_patterns =
      ~r/[-*]\s+(?:For\s+)?(\w+):\s+`([^`]+)`/
      |> Regex.scan(content)
      |> Enum.map(fn
        [_, type, pattern] -> %{type: String.downcase(type), pattern: pattern}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    conventions = %{conventions | naming_patterns: naming_patterns}

    conventions =
      if String.contains?(content, ["issue form", "issue template", "New Issue"]) do
        %{conventions | templates_mentioned: true}
      else
        conventions
      end

    conventions =
      if String.contains?(content, ["labels=", "label:"]) do
        %{conventions | labels_mentioned: true}
      else
        conventions
      end

    branch_naming =
      cond do
        Regex.match?(~r/branch.*name.*(?:feature|fix|bugfix|hotfix)/i, content) ->
          case Regex.run(~r/`([^`]*(?:feature|fix|bugfix|hotfix)[^`]*)`/i, content) do
            [_, pattern] -> pattern
            _ -> "feature/<description> or fix/<description>"
          end

        String.contains?(content, ["feature/", "fix/", "bugfix/"]) ->
          "feature/<description> or fix/<description>"

        true ->
          nil
      end

    conventions = %{conventions | branch_naming: branch_naming}

    commit_convention =
      cond do
        String.contains?(content, ["Conventional Commits", "conventional commits", "conventionalcommits"]) ->
          "Conventional Commits (feat:, fix:, docs:, etc.)"

        String.contains?(content, ["semantic commit", "Semantic Commit"]) ->
          "Semantic Commits"

        Regex.match?(~r/commit.*message.*should.*(?:start|begin|use)/i, content) ->
          case Regex.run(~r/commit.*message.*should.*(?:start|begin|use).*`([^`]+)`/i, content) do
            [_, pattern] -> pattern
            _ -> nil
          end

        true ->
          nil
      end

    conventions = %{conventions | commit_convention: commit_convention}

    pr_title_format =
      if String.contains?(content, ["PR title", "pull request title"]) do
        case Regex.run(~r/(?:PR|pull request)\s+title.*(?:should|must|format).*`([^`]+)`/i, content) do
          [_, format] -> format
          _ -> nil
        end
      else
        nil
      end

    %{conventions | pr_title_format: pr_title_format}
  end

  defp extract_ways_to_contribute(content) do
    content_lower = String.downcase(content)

    ways = []

    ways =
      if Regex.match?(
           ~r/\breport\b.*\bbug|bug\s*report|open\s+an?\s+issue|create\s+an?\s+issue|file\s+an?\s+issue|submit\s+an?\s+issue/i,
           content
         ) do
        ways ++ ["Report bugs"]
      else
        ways
      end

    ways =
      if Regex.match?(
           ~r/feature\s*request|request\s+a?\s*feature|new\s+feature|suggest.*feature|enhancement|propose.*change/i,
           content
         ) do
        ways ++ ["Request features"]
      else
        ways
      end

    ways =
      if String.contains?(content_lower, ["documentation", " docs", "readme", "tutorial", "typos", "docstring"]) or
           Regex.match?(~r/improve.*doc|update.*doc|fix.*doc|write.*doc/i, content) do
        ways ++ ["Improve documentation"]
      else
        ways
      end

    ways =
      if String.contains?(content_lower, ["translation", "i18n", "locales", "translate", "internationalization"]) or
           Regex.match?(~r/add.*language|new.*language|translat/i, content) do
        ways ++ ["Add translations"]
      else
        ways
      end

    ways =
      if String.contains?(content_lower, ["integration", "plugin", "extension", "third-party"]) do
        ways ++ ["Add integrations"]
      else
        ways
      end

    ways =
      if Regex.match?(
           ~r/pull\s*request|submit.*pr|create.*pr|open.*pr|fork.*repo|clone.*repo|contribute.*code|send.*patch/i,
           content
         ) or
           String.contains?(content_lower, [" prs ", " prs.", "pull requests"]) do
        ways ++ ["Submit pull requests"]
      else
        ways
      end

    ways =
      if Regex.match?(~r/write.*test|add.*test|run.*test|testing|test\s+suite|pytest|unittest/i, content) and
           not String.contains?(content_lower, "latest") do
        ways ++ ["Write tests"]
      else
        ways
      end

    ways =
      if Regex.match?(~r/review.*pr|review.*pull|code\s+review|reviewing.*code|peer\s+review/i, content) do
        ways ++ ["Review pull requests"]
      else
        ways
      end

    ways =
      if Regex.match?(~r/security.*issue|report.*vulnerabilit|security.*bug|responsible\s+disclosure/i, content) do
        ways ++ ["Report security issues"]
      else
        ways
      end

    ways =
      if String.contains?(content_lower, [
           "sponsor",
           "funding",
           "donate",
           "github sponsors",
           "support the project",
           "open collective"
         ]) do
        ways ++ ["Sponsor the project"]
      else
        ways
      end

    ways =
      if Regex.match?(~r/answer.*question|help.*user|support.*community|stack\s*overflow|discord|discuss/i, content) do
        ways ++ ["Help other users"]
      else
        ways
      end

    ways =
      if Regex.match?(~r/blog.*post|write.*about|share.*experience|tutorial|example|demo/i, content) do
        ways ++ ["Share examples and tutorials"]
      else
        ways
      end

    ways =
      if Regex.match?(~r/triage.*issue|label.*issue|help.*maintain|maintain.*project/i, content) do
        ways ++ ["Triage issues"]
      else
        ways
      end

    ways =
      if String.contains?(content_lower, ["example", "cookbook", "recipe"]) do
        ways ++ ["Share examples"]
      else
        ways
      end

    ways =
      if String.contains?(content_lower, ["question", "help others", "answer", "discussion"]) do
        ways ++ ["Help other users"]
      else
        ways
      end

    ways
  end

  defp parse_agents_md(content) do
    commands = extract_agents_commands(content)
    code_style = extract_agents_code_style(content)
    sections = extract_agents_sections(content)

    %{
      type: :agents_md,
      has_content: byte_size(content) > 100,
      commands: commands,
      code_style: code_style,
      sections: sections,
      content_preview: String.slice(content, 0, 5000)
    }
  end

  defp extract_agents_commands(content) do
    commands_section =
      case Regex.run(~r/##\s*Commands\s*\n((?:[-*`].*\n?)+)/im, content) do
        [_, section] -> section
        _ -> ""
      end

    if commands_section != "" do
      ~r/[-*]\s*`([^`]+)`\s*[-–—:]\s*(.+)/
      |> Regex.scan(commands_section)
      |> Enum.map(fn
        [_, cmd, desc] -> %{command: String.trim(cmd), description: String.trim(desc)}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp extract_agents_code_style(content) do
    style_section =
      case Regex.run(~r/##\s*Code\s*Style\s*\n((?:[-*].*\n?)+)/im, content) do
        [_, section] -> section
        _ -> ""
      end

    if style_section != "" do
      ~r/[-*]\s*\*\*([^*]+)\*\*:\s*(.+)/
      |> Regex.scan(style_section)
      |> Enum.map(fn
        [_, category, guideline] ->
          %{category: String.trim(category), guideline: String.trim(guideline)}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp extract_agents_sections(content) do
    ~r/##\s*([^\n]+)/
    |> Regex.scan(content)
    |> Enum.map(fn
      [_, title] -> String.trim(title)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_security_md(content) do
    security_email =
      cond do
        match = Regex.run(~r/security@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/, content) ->
          List.first(match)

        match = Regex.run(~r/mailto:([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/, content) ->
          Enum.at(match, 1)

        match = Regex.run(~r/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/, content) ->
          email = Enum.at(match, 1)
          if email && String.contains?(String.downcase(email), "security"), do: email, else: nil

        true ->
          nil
      end

    has_vulnerability_reporting =
      String.contains?(content, ["vulnerability", "Vulnerability", "security issue", "Security issue"])

    discourages_public_disclosure =
      String.contains?(content, [
        "publicly discussing",
        "public disclosure",
        "confidential",
        "privately",
        "do not publicly"
      ])

    response_time =
      case Regex.run(~r/(\d+)\s*(?:business\s+)?days?/i, content) do
        [_, days] -> "#{days} days"
        _ -> nil
      end

    out_of_scope =
      if String.contains?(content, ["Out of scope", "out of scope", "Out-of-scope"]) do
        content
        |> String.split(~r/##?\s*Out[- ]of[- ]scope/i)
        |> Enum.at(1, "")
        |> String.split(~r/##?\s*[A-Z]/)
        |> Enum.at(0, "")
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "-"))
        |> Enum.map(&String.replace(&1, ~r/^-\s*/, ""))
        |> Enum.take(5)
      else
        []
      end

    reporting_guidelines =
      cond do
        String.contains?(content, "submit your findings") -> "Submit findings via security email"
        String.contains?(content, "sending an email") -> "Report via email"
        String.contains?(content, "GitHub Security") -> "Use GitHub Security Advisories"
        true -> nil
      end

    %{
      type: :security_md,
      has_content: byte_size(content) > 100,
      has_vulnerability_reporting: has_vulnerability_reporting,
      security_email: security_email,
      discourages_public_disclosure: discourages_public_disclosure,
      response_time: response_time,
      out_of_scope: out_of_scope,
      reporting_guidelines: reporting_guidelines
    }
  end

  defp parse_env_example(content) do
    vars =
      content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> %{key: String.trim(key), example_value: String.trim(value)}
          [key] -> %{key: String.trim(key), example_value: nil}
        end
      end)

    %{
      type: :env_example,
      variables: vars
    }
  end

  defp parse_node_version_file(content) do
    version = content |> String.trim() |> String.replace(~r/^v/, "")

    %{
      type: :node_version,
      version: version
    }
  end

  defp parse_tool_versions(content) do
    versions =
      content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(fn line ->
        case String.split(line, ~r/\s+/, parts: 2) do
          [tool, version] -> {tool, version}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    %{
      type: :tool_versions,
      versions: versions
    }
  end

  defp parse_tsconfig(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        compiler_options = Map.get(json, "compilerOptions", %{})

        %{
          type: :tsconfig,
          target: Map.get(compiler_options, "target"),
          module: Map.get(compiler_options, "module"),
          strict: Map.get(compiler_options, "strict", false),
          jsx: Map.get(compiler_options, "jsx")
        }

      {:error, _} ->
        %{type: :tsconfig, error: "Invalid JSON"}
    end
  end

  defp parse_pyproject(content) do
    name = extract_regex(content, ~r/name\s*=\s*"([^"]+)"/)
    version = extract_regex(content, ~r/version\s*=\s*"([^"]+)"/)

    python_version =
      extract_regex(content, ~r/requires-python\s*=\s*"([^"]+)"/) ||
        extract_regex(content, ~r/python_requires\s*=\s*"([^"]+)"/)

    description = extract_regex(content, ~r/description\s*=\s*"([^"]+)"/)

    license =
      extract_regex(content, ~r/license\s*=\s*\{?\s*text\s*=\s*"([^"]+)"/) ||
        extract_regex(content, ~r/license\s*=\s*"([^"]+)"/)

    dependencies =
      case Regex.run(~r/dependencies\s*=\s*\[(.*?)\]/s, content) do
        [_, deps_str] ->
          Regex.scan(~r/"([^"]+)"/, deps_str)
          |> Enum.map(fn [_, dep] ->
            case Regex.run(~r/^([a-zA-Z0-9_-]+)(.*)$/, String.trim(dep)) do
              [_, dep_name, version_spec] -> %{name: dep_name, version: String.trim(version_spec)}
              _ -> %{name: dep, version: nil}
            end
          end)

        _ ->
          []
      end

    dev_dependencies =
      case Regex.run(~r/\[project\.optional-dependencies\]\s*dev\s*=\s*\[(.*?)\]/s, content) do
        [_, deps_str] ->
          Regex.scan(~r/"([^"]+)"/, deps_str)
          |> Enum.map(fn [_, dep] -> extract_dep_name(dep) end)

        _ ->
          case Regex.run(~r/\[tool\.hatch\.envs\.default\]\s*dependencies\s*=\s*\[(.*?)\]/s, content) do
            [_, deps_str] ->
              Regex.scan(~r/"([^"]+)"/, deps_str)
              |> Enum.map(fn [_, dep] -> extract_dep_name(dep) end)

            _ ->
              []
          end
      end

    scripts =
      case Regex.run(~r/\[project\.scripts\]\s*(.*?)(?:\n\[|\z)/s, content) do
        [_, scripts_str] ->
          Regex.scan(~r/(\w+)\s*=\s*"([^"]+)"/, scripts_str)
          |> Enum.map(fn [_, name, cmd] -> %{name: name, command: cmd} end)

        _ ->
          []
      end

    has_pytest = String.contains?(content, ["pytest", "pytest-cov", "pytest-asyncio"])
    has_mypy = String.contains?(content, "mypy")
    has_ruff = String.contains?(content, "ruff")
    has_black = String.contains?(content, "black")
    has_isort = String.contains?(content, "isort")
    has_pre_commit = String.contains?(content, "pre-commit")
    has_coverage = String.contains?(content, ["coverage", "pytest-cov"])

    build_backend_line = extract_regex(content, ~r/build-backend\s*=\s*["']([^"']+)["']/)

    build_backend =
      cond do
        build_backend_line && String.contains?(build_backend_line, "hatchling") -> "hatch"
        build_backend_line && String.contains?(build_backend_line, "poetry") -> "poetry"
        build_backend_line && String.contains?(build_backend_line, "pdm") -> "pdm"
        build_backend_line && String.contains?(build_backend_line, "flit") -> "flit"
        build_backend_line && String.contains?(build_backend_line, "setuptools") -> "setuptools"
        String.contains?(content, "[tool.hatch]") or String.contains?(content, "[tool.hatch.") -> "hatch"
        String.contains?(content, "[tool.poetry]") -> "poetry"
        String.contains?(content, "[tool.pdm]") -> "pdm"
        String.contains?(content, "[tool.flit]") -> "flit"
        true -> nil
      end

    %{
      type: :pyproject,
      name: name,
      version: version,
      description: description,
      license: license,
      python_version: python_version,
      dependencies: dependencies,
      dev_dependencies: dev_dependencies,
      scripts: scripts,
      build_backend: build_backend,
      testing: %{
        has_pytest: has_pytest,
        has_coverage: has_coverage
      },
      linting: %{
        has_mypy: has_mypy,
        has_ruff: has_ruff,
        has_black: has_black,
        has_isort: has_isort
      },
      has_pre_commit: has_pre_commit
    }
  end

  defp extract_dep_name(dep) do
    case Regex.run(~r/^([a-zA-Z0-9_-]+)/, String.trim(dep)) do
      [_, name] -> name
      _ -> dep
    end
  end

  defp parse_requirements_txt(content, req_type) do
    deps =
      content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#") or String.starts_with?(&1, "-")))
      |> Enum.map(fn line ->
        line = String.replace(line, ~r/\s*#.*$/, "")

        cond do
          String.contains?(line, "==") ->
            [name, ver] = String.split(line, "==", parts: 2)
            %{name: String.trim(name), operator: "==", version: String.trim(ver)}

          String.contains?(line, ">=") ->
            [name, ver] = String.split(line, ">=", parts: 2)
            %{name: String.trim(name), operator: ">=", version: String.trim(ver)}

          String.contains?(line, "<=") ->
            [name, ver] = String.split(line, "<=", parts: 2)
            %{name: String.trim(name), operator: "<=", version: String.trim(ver)}

          String.contains?(line, ">") ->
            [name, ver] = String.split(line, ">", parts: 2)
            %{name: String.trim(name), operator: ">", version: String.trim(ver)}

          String.contains?(line, "<") ->
            [name, ver] = String.split(line, "<", parts: 2)
            %{name: String.trim(name), operator: "<", version: String.trim(ver)}

          String.contains?(line, "[") ->
            name = String.replace(line, ~r/\[.*\]/, "") |> String.trim()
            %{name: name, operator: nil, version: nil}

          true ->
            %{name: String.trim(line), operator: nil, version: nil}
        end
      end)
      |> Enum.reject(fn dep -> dep[:name] == "" end)

    %{
      type: :requirements_txt,
      req_type: req_type,
      dependencies: deps,
      dep_count: length(deps)
    }
  end

  defp parse_license(content) do
    license_type =
      cond do
        String.contains?(content, "MIT License") or
            String.contains?(content, "Permission is hereby granted, free of charge") ->
          "MIT"

        String.contains?(content, "Apache License") and String.contains?(content, "Version 2.0") ->
          "Apache-2.0"

        String.contains?(content, "GNU GENERAL PUBLIC LICENSE") and String.contains?(content, "Version 3") ->
          "GPL-3.0"

        String.contains?(content, "GNU GENERAL PUBLIC LICENSE") and String.contains?(content, "Version 2") ->
          "GPL-2.0"

        String.contains?(content, "BSD 3-Clause") or
            String.contains?(content, "Redistribution and use in source and binary forms") ->
          "BSD-3-Clause"

        String.contains?(content, "BSD 2-Clause") ->
          "BSD-2-Clause"

        String.contains?(content, "ISC License") ->
          "ISC"

        String.contains?(content, "Mozilla Public License") ->
          "MPL-2.0"

        String.contains?(content, "The Unlicense") ->
          "Unlicense"

        String.contains?(content, "Creative Commons") ->
          "CC"

        true ->
          "Unknown"
      end

    %{
      type: :license,
      license_type: license_type
    }
  end

  defp parse_citation_cff(content) do
    title = extract_regex(content, ~r/title:\s*["']?([^"'\n]+)["']?/)
    version = extract_regex(content, ~r/version:\s*["']?([^"'\n]+)["']?/)
    doi = extract_regex(content, ~r/doi:\s*["']?([^"'\n]+)["']?/)
    url = extract_regex(content, ~r/url:\s*["']?([^"'\n]+)["']?/)
    repository = extract_regex(content, ~r/repository-code:\s*["']?([^"'\n]+)["']?/)
    license_name = extract_regex(content, ~r/license:\s*["']?([^"'\n]+)["']?/)

    authors =
      case Regex.run(~r/authors:\s*\n((?:\s+-.*\n?)+)/m, content) do
        [_, authors_section] ->
          Regex.scan(~r/given-names:\s*["']?([^"'\n]+)["']?.*?family-names:\s*["']?([^"'\n]+)["']?/s, authors_section)
          |> Enum.map(fn
            [_, given, family] -> "#{given} #{family}"
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    %{
      type: :citation_cff,
      title: title,
      version: version,
      doi: doi,
      url: url,
      repository: repository,
      license: license_name,
      authors: authors
    }
  end

  defp parse_setup_py(content) do
    name = extract_regex(content, ~r/name\s*=\s*["']([^"']+)["']/)
    version = extract_regex(content, ~r/version\s*=\s*["']([^"']+)["']/)
    description = extract_regex(content, ~r/description\s*=\s*["']([^"']+)["']/)
    python_requires = extract_regex(content, ~r/python_requires\s*=\s*["']([^"']+)["']/)

    has_install_requires = String.contains?(content, "install_requires")
    has_extras_require = String.contains?(content, "extras_require")
    has_entry_points = String.contains?(content, "entry_points")

    %{
      type: :setup_py,
      name: name,
      version: version,
      description: description,
      python_requires: python_requires,
      has_install_requires: has_install_requires,
      has_extras_require: has_extras_require,
      has_entry_points: has_entry_points
    }
  end

  defp parse_setup_cfg(content) do
    name = extract_regex(content, ~r/name\s*=\s*(.+)/)
    version = extract_regex(content, ~r/version\s*=\s*(.+)/)
    description = extract_regex(content, ~r/description\s*=\s*(.+)/)
    python_requires = extract_regex(content, ~r/python_requires\s*=\s*(.+)/)

    has_options = String.contains?(content, "[options]")
    has_flake8 = String.contains?(content, "[flake8]")
    has_mypy = String.contains?(content, "[mypy]")
    has_pytest = String.contains?(content, "[tool:pytest]") or String.contains?(content, "[pytest]")

    %{
      type: :setup_cfg,
      name: name && String.trim(name),
      version: version && String.trim(version),
      description: description && String.trim(description),
      python_requires: python_requires && String.trim(python_requires),
      has_flake8: has_flake8,
      has_mypy: has_mypy,
      has_pytest: has_pytest,
      has_options: has_options
    }
  end

  defp parse_tox_ini(content) do
    envlist = extract_regex(content, ~r/envlist\s*=\s*(.+)/)

    envs =
      if envlist do
        envlist
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      else
        []
      end

    has_pytest = String.contains?(content, "pytest")
    has_coverage = String.contains?(content, "coverage")
    has_mypy = String.contains?(content, "mypy")
    has_flake8 = String.contains?(content, "flake8")
    has_black = String.contains?(content, "black")

    %{
      type: :tox_ini,
      environments: envs,
      has_pytest: has_pytest,
      has_coverage: has_coverage,
      has_mypy: has_mypy,
      has_flake8: has_flake8,
      has_black: has_black
    }
  end

  defp parse_noxfile(content) do
    sessions =
      Regex.scan(~r/@nox\.session(?:\([^)]*\))?\s*def\s+(\w+)/, content)
      |> Enum.map(fn [_, name] -> name end)

    has_pytest = String.contains?(content, "pytest")
    has_coverage = String.contains?(content, "coverage")
    has_mypy = String.contains?(content, "mypy")
    has_lint = String.contains?(content, ["ruff", "flake8", "lint"])
    has_docs = String.contains?(content, ["sphinx", "mkdocs", "docs"])

    %{
      type: :noxfile,
      sessions: sessions,
      has_pytest: has_pytest,
      has_coverage: has_coverage,
      has_mypy: has_mypy,
      has_lint: has_lint,
      has_docs: has_docs
    }
  end

  defp parse_gemfile(content) do
    gems =
      Regex.scan(~r/^\s*gem\s+['"]([^'"]+)['"](?:,\s*['"]([^'"]+)['"])?/m, content)
      |> Enum.map(fn
        [_, name, version] -> %{name: name, version: version}
        [_, name] -> %{name: name, version: nil}
      end)

    ruby_version = extract_regex(content, ~r/ruby\s+['"]([^'"]+)['"]/)

    groups =
      Regex.scan(~r/group\s+:(\w+)/m, content)
      |> Enum.map(fn [_, group] -> group end)
      |> Enum.uniq()

    has_rails = Enum.any?(gems, fn g -> g.name == "rails" end)
    has_rspec = Enum.any?(gems, fn g -> String.contains?(g.name, "rspec") end)
    has_minitest = Enum.any?(gems, fn g -> g.name == "minitest" end)
    has_rubocop = Enum.any?(gems, fn g -> String.contains?(g.name, "rubocop") end)
    has_standard = Enum.any?(gems, fn g -> g.name == "standard" end)

    rails_version =
      gems
      |> Enum.find(fn g -> g.name == "rails" end)
      |> case do
        %{version: v} when not is_nil(v) -> extract_version_number(v)
        _ -> nil
      end

    %{
      type: :gemfile,
      gems: gems,
      ruby_version: ruby_version,
      rails_version: rails_version,
      groups: groups,
      has_rails: has_rails,
      has_rspec: has_rspec,
      has_minitest: has_minitest,
      has_rubocop: has_rubocop,
      has_standard: has_standard,
      gem_count: length(gems),
      source: extract_regex(content, ~r/source\s+['"]([^'"]+)['"]/)
    }
  end

  defp extract_version_number(version_string) do
    case Regex.run(~r/(\d+\.\d+(?:\.\d+)?)/, version_string) do
      [_, version] -> version
      _ -> version_string
    end
  end

  defp parse_gemfile_lock(content) do
    bundled_with = extract_regex(content, ~r/BUNDLED WITH\s*\n\s*(\d+\.\d+\.\d+)/)
    ruby_version = extract_regex(content, ~r/RUBY VERSION\s*\n\s*ruby\s+(\d+\.\d+\.\d+)/)

    platforms =
      case Regex.run(~r/PLATFORMS\s*\n((?:\s+\S+\s*\n)+)/, content) do
        [_, platforms_str] -> String.split(platforms_str, ~r/\s+/, trim: true)
        _ -> []
      end

    %{
      type: :gemfile_lock,
      bundled_with: bundled_with,
      ruby_version: ruby_version,
      platforms: platforms
    }
  end

  defp parse_ruby_version_file(content) do
    version = String.trim(content)

    %{
      type: :ruby_version,
      version: version,
      is_jruby: String.contains?(version, "jruby"),
      is_truffleruby: String.contains?(version, "truffleruby")
    }
  end

  defp parse_rvmrc(content) do
    ruby_string = extract_regex(content, ~r/rvm\s+(?:use\s+)?([^\s]+)/)
    gemset = extract_regex(content, ~r/@(\w+)/)

    %{
      type: :rvmrc,
      ruby_string: ruby_string,
      gemset: gemset
    }
  end

  defp parse_rubocop_config(content) do
    inherit_from =
      case Regex.scan(~r/inherit_from:\s*(?:\n\s*-\s*)?([^\n]+)/, content) do
        [_ | _] = matches -> Enum.map(matches, fn [_, file] -> String.trim(file) end)
        _ -> []
      end

    disabled_cops =
      Regex.scan(~r/^(\w+\/\w+):\s*\n\s*Enabled:\s*false/m, content)
      |> Enum.map(fn [_, cop] -> cop end)

    all_cops_exclude =
      case Regex.run(~r/AllCops:\s*\n(?:\s+[^\n]+\n)*\s*Exclude:\s*\n((?:\s+-[^\n]+\n)+)/, content) do
        [_, excludes] ->
          Regex.scan(~r/-\s*['"]?([^'"\n]+)['"]?/, excludes)
          |> Enum.map(fn [_, path] -> String.trim(path) end)

        _ ->
          []
      end

    target_ruby =
      case Regex.run(~r/TargetRubyVersion:\s*(\d+\.\d+)/, content) do
        [_, version] -> version
        _ -> nil
      end

    %{
      type: :rubocop_config,
      inherit_from: inherit_from,
      disabled_cops: disabled_cops,
      all_cops_exclude: all_cops_exclude,
      target_ruby_version: target_ruby,
      has_rails_cops: String.contains?(content, "Rails/"),
      has_rspec_cops: String.contains?(content, "RSpec/"),
      has_performance_cops: String.contains?(content, "Performance/")
    }
  end

  defp parse_standard_rb_config(content) do
    ignore =
      case Regex.run(~r/ignore:\s*\n((?:\s+-[^\n]+\n)+)/, content) do
        [_, ignores] ->
          Regex.scan(~r/-\s*['"]?([^'"\n:]+)['"]?/, ignores)
          |> Enum.map(fn [_, path] -> String.trim(path) end)

        _ ->
          []
      end

    %{
      type: :standard_rb,
      ignore: ignore,
      has_parallel: String.contains?(content, "parallel:"),
      has_fix: String.contains?(content, "fix:")
    }
  end

  defp parse_rakefile(content) do
    tasks =
      Regex.scan(~r/(?:task|desc)\s+[:'"]([^'":\s]+)/, content)
      |> Enum.map(fn [_, task] -> task end)
      |> Enum.uniq()

    has_rails = String.contains?(content, "Rails")
    has_rspec = String.contains?(content, ["RSpec", "rspec"])
    has_cucumber = String.contains?(content, "cucumber")

    namespaces =
      Regex.scan(~r/namespace\s+:(\w+)/, content)
      |> Enum.map(fn [_, ns] -> ns end)
      |> Enum.uniq()

    %{
      type: :rakefile,
      tasks: tasks,
      namespaces: namespaces,
      has_rails: has_rails,
      has_rspec: has_rspec,
      has_cucumber: has_cucumber
    }
  end

  defp parse_rack_config(content) do
    run_app = extract_regex(content, ~r/run\s+([^\s\n]+)/)

    uses =
      Regex.scan(~r/use\s+([^\s\n(]+)/, content)
      |> Enum.map(fn [_, middleware] -> middleware end)

    %{
      type: :rack_config,
      run_app: run_app,
      middleware: uses,
      is_rails: String.contains?(content, "Rails.application")
    }
  end

  defp parse_brewfile(content) do
    brews =
      Regex.scan(~r/brew\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, name] -> %{type: :brew, name: name} end)

    casks =
      Regex.scan(~r/cask\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, name] -> %{type: :cask, name: name} end)

    taps =
      Regex.scan(~r/tap\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, name] -> name end)

    mas_apps =
      Regex.scan(~r/mas\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, name] -> name end)

    %{
      type: :brewfile,
      brews: brews,
      casks: casks,
      taps: taps,
      mas_apps: mas_apps,
      total_count: length(brews) + length(casks)
    }
  end

  defp parse_gemspec(content) do
    name = extract_regex(content, ~r/\.name\s*=\s*['"]([^'"]+)['"]/)
    version = extract_regex(content, ~r/\.version\s*=\s*['"]?([^'"}\s]+)['"]?/)
    summary = extract_regex(content, ~r/\.summary\s*=\s*['"]([^'"]+)['"]/)
    description = extract_regex(content, ~r/\.description\s*=\s*['"]([^'"]+)['"]/)
    license = extract_regex(content, ~r/\.license\s*=\s*['"]([^'"]+)['"]/)
    homepage = extract_regex(content, ~r/\.homepage\s*=\s*['"]([^'"]+)['"]/)

    required_ruby =
      case Regex.run(~r/\.required_ruby_version\s*=\s*['"]?([^'"}\n]+)['"]?/, content) do
        [_, version] -> String.trim(version)
        _ -> nil
      end

    authors =
      case Regex.run(~r/\.authors\s*=\s*\[([^\]]+)\]/, content) do
        [_, authors_str] ->
          Regex.scan(~r/['"]([^'"]+)['"]/, authors_str)
          |> Enum.map(fn [_, author] -> author end)

        _ ->
          []
      end

    dependencies =
      Regex.scan(~r/\.add_(?:runtime_)?dependency\s*\(?['"]([^'"]+)['"](?:,\s*['"]([^'"]+)['"])?\)?/, content)
      |> Enum.map(fn
        [_, name, version] -> %{name: name, version: version, type: :runtime}
        [_, name] -> %{name: name, version: nil, type: :runtime}
      end)

    dev_dependencies =
      Regex.scan(~r/\.add_development_dependency\s*\(?['"]([^'"]+)['"](?:,\s*['"]([^'"]+)['"])?\)?/, content)
      |> Enum.map(fn
        [_, name, version] -> %{name: name, version: version, type: :development}
        [_, name] -> %{name: name, version: nil, type: :development}
      end)

    %{
      type: :gemspec,
      name: name,
      version: version,
      summary: summary,
      description: description,
      license: license,
      homepage: homepage,
      required_ruby_version: required_ruby,
      authors: authors,
      dependencies: dependencies,
      dev_dependencies: dev_dependencies
    }
  end

  defp parse_database_yml(content) do
    adapters =
      Regex.scan(~r/adapter:\s*(\w+)/, content)
      |> Enum.map(fn [_, adapter] -> adapter end)
      |> Enum.uniq()

    databases =
      Regex.scan(~r/database:\s*([^\n#]+)/, content)
      |> Enum.map(fn [_, db] -> String.trim(db) end)
      |> Enum.uniq()

    environments =
      ["development", "test", "production"]
      |> Enum.filter(fn env -> String.contains?(content, "#{env}:") end)

    has_env_vars = String.contains?(content, ["ENV[", "<%="])

    %{
      type: :database_yml,
      adapters: adapters,
      databases: databases,
      environments: environments,
      has_env_vars: has_env_vars,
      has_postgresql: "postgresql" in adapters,
      has_mysql: "mysql2" in adapters or "mysql" in adapters,
      has_sqlite: "sqlite3" in adapters
    }
  end

  defp parse_routes_rb(content) do
    route_count =
      Regex.scan(~r/\b(get|post|put|patch|delete|resources?|root|match|namespace|scope|mount)\b/, content)
      |> length()

    resources =
      Regex.scan(~r/resources?\s+:(\w+)/, content)
      |> Enum.map(fn [_, resource] -> resource end)

    namespaces =
      Regex.scan(~r/namespace\s+:(\w+)/, content)
      |> Enum.map(fn [_, ns] -> ns end)

    has_api = String.contains?(content, ["/api", "namespace :api"])
    has_devise = String.contains?(content, "devise_for")
    has_admin = String.contains?(content, ["namespace :admin", "/admin"])

    %{
      type: :routes_rb,
      route_count: route_count,
      resources: resources,
      namespaces: namespaces,
      has_api: has_api,
      has_devise: has_devise,
      has_admin: has_admin
    }
  end

  defp parse_application_rb(content) do
    app_name = extract_regex(content, ~r/module\s+(\w+)\s*\n\s*class\s+Application/)
    rails_version = extract_regex(content, ~r/config\.load_defaults\s+(\d+\.\d+)/)

    config_options =
      Regex.scan(~r/config\.(\w+(?:\.\w+)?)\s*=/, content)
      |> Enum.map(fn [_, opt] -> opt end)
      |> Enum.uniq()

    has_api_only = String.contains?(content, "config.api_only = true")
    has_zeitwerk = String.contains?(content, "config.autoloader = :zeitwerk")

    %{
      type: :application_rb,
      app_name: app_name,
      rails_version: rails_version,
      config_options: config_options,
      has_api_only: has_api_only,
      has_zeitwerk: has_zeitwerk,
      is_rails: true
    }
  end

  defp parse_db_schema(content, filename) do
    type = if String.ends_with?(filename, ".sql"), do: :structure_sql, else: :schema_rb

    tables =
      if type == :schema_rb do
        Regex.scan(~r/create_table\s+["'](\w+)["']/, content)
        |> Enum.map(fn [_, table] -> table end)
      else
        Regex.scan(~r/CREATE TABLE\s+(?:`|")?(\w+)(?:`|")?/i, content)
        |> Enum.map(fn [_, table] -> table end)
      end

    version = extract_regex(content, ~r/ActiveRecord::Schema(?:\[\d+\.\d+\])?\.define\(version:\s*(\d+)/)

    %{
      type: type,
      schema_type: type,
      tables: tables,
      table_count: length(tables),
      version: version,
      has_extensions: String.contains?(content, ["enable_extension", "CREATE EXTENSION"])
    }
  end

  defp parse_rspec_config(content) do
    options =
      content
      |> String.split(~r/\s+/, trim: true)
      |> Enum.filter(&String.starts_with?(&1, "--"))

    %{
      type: :rspec_config,
      options: options,
      has_format: Enum.any?(options, &String.starts_with?(&1, "--format")),
      has_color: "--color" in options or "--colour" in options
    }
  end

  defp parse_spec_helper(content, filename) do
    is_rails_helper = String.contains?(filename, "rails_helper")

    requires =
      Regex.scan(~r/require\s+['"]([^'"]+)['"]/, content)
      |> Enum.map(fn [_, req] -> req end)

    has_factory_bot = String.contains?(content, ["FactoryBot", "factory_bot"])
    has_shoulda = String.contains?(content, "shoulda")
    has_vcr = String.contains?(content, "VCR")
    has_webmock = String.contains?(content, "WebMock")
    has_simplecov = String.contains?(content, "SimpleCov")
    has_database_cleaner = String.contains?(content, "DatabaseCleaner")

    %{
      type: :spec_helper,
      is_rails_helper: is_rails_helper,
      requires: requires,
      has_factory_bot: has_factory_bot,
      has_shoulda: has_shoulda,
      has_vcr: has_vcr,
      has_webmock: has_webmock,
      has_simplecov: has_simplecov,
      has_database_cleaner: has_database_cleaner
    }
  end

  defp parse_guardfile(content) do
    guards =
      Regex.scan(~r/guard\s*(?::(\w+)|['"](\w+)['"])/, content)
      |> Enum.map(fn
        [_, name, ""] -> name
        [_, "", name] -> name
        [_, name] -> name
      end)

    %{
      type: :guardfile,
      guards: guards,
      has_rspec: "rspec" in guards,
      has_rubocop: "rubocop" in guards,
      has_bundler: "bundler" in guards
    }
  end

  defp parse_procfile(content, filename) do
    is_dev = String.contains?(filename, ".dev")

    processes =
      Regex.scan(~r/^(\w+):\s*(.+)$/m, content)
      |> Enum.map(fn [_, name, command] -> %{name: name, command: String.trim(command)} end)

    %{
      type: :procfile,
      is_dev: is_dev,
      processes: processes,
      has_web: Enum.any?(processes, fn p -> p.name == "web" end),
      has_worker: Enum.any?(processes, fn p -> String.contains?(p.name, "worker") end),
      has_sidekiq: Enum.any?(processes, fn p -> String.contains?(p.command, "sidekiq") end)
    }
  end

  defp parse_server_config(content, filename) do
    server_type = if String.contains?(filename, "puma"), do: :puma, else: :unicorn

    workers = extract_regex(content, ~r/workers?\s*(?:\(?\s*)?(\d+)/)

    threads =
      case Regex.run(~r/threads\s*(?:\(?\s*)?(\d+)\s*,\s*(\d+)/, content) do
        [_, min, max] -> %{min: String.to_integer(min), max: String.to_integer(max)}
        _ -> nil
      end

    port = extract_regex(content, ~r/port\s*(?:\(?\s*)?(\d+)/)

    %{
      type: :server_config,
      server_type: server_type,
      workers: workers,
      threads: threads,
      port: port,
      has_preload: String.contains?(content, "preload_app"),
      has_ssl: String.contains?(content, ["ssl", "https"])
    }
  end

  defp parse_cargo_toml(content) do
    name = extract_regex(content, ~r/name\s*=\s*"([^"]+)"/)
    version = extract_regex(content, ~r/version\s*=\s*"([^"]+)"/)
    edition = extract_regex(content, ~r/edition\s*=\s*"([^"]+)"/)

    %{
      type: :cargo_toml,
      name: name,
      version: version,
      edition: edition
    }
  end

  defp parse_go_mod(content) do
    module_name = extract_regex(content, ~r/^module\s+(.+)$/m)
    go_version = extract_regex(content, ~r/^go\s+(\d+\.\d+(?:\.\d+)?)$/m)
    toolchain = extract_regex(content, ~r/^toolchain\s+go(\d+\.\d+\.\d+)$/m)

    require_block = extract_require_block(content)
    dependencies = parse_go_dependencies(require_block)

    framework = detect_go_framework(dependencies)

    %{
      type: :go_mod,
      module: module_name,
      go_version: go_version,
      toolchain: toolchain,
      dependencies: dependencies,
      framework: framework,
      has_replace: String.contains?(content, "replace "),
      dep_count: length(dependencies)
    }
  end

  defp extract_require_block(content) do
    case Regex.run(~r/require\s*\(\s*(.*?)\s*\)/s, content) do
      [_, block] -> block
      _ -> ""
    end
  end

  defp parse_go_dependencies(require_block) do
    require_block
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "//")))
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [name, version] ->
          version = String.replace(version, ~r{\s*//.*$}, "")
          %{name: name, version: String.trim(version)}

        [name] ->
          %{name: name, version: nil}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp detect_go_framework(dependencies) do
    dep_names = Enum.map(dependencies, & &1[:name]) |> Enum.reject(&is_nil/1)

    cond do
      Enum.any?(dep_names, &String.contains?(&1, "danielgtaylor/huma")) -> "huma"
      Enum.any?(dep_names, &String.contains?(&1, "gin-gonic/gin")) -> "gin"
      Enum.any?(dep_names, &String.contains?(&1, "labstack/echo")) -> "echo"
      Enum.any?(dep_names, &String.contains?(&1, "go-chi/chi")) -> "chi"
      Enum.any?(dep_names, &String.contains?(&1, "gofiber/fiber")) -> "fiber"
      Enum.any?(dep_names, &String.contains?(&1, "gorilla/mux")) -> "gorilla"
      Enum.any?(dep_names, &String.contains?(&1, "beego/beego")) -> "beego"
      Enum.any?(dep_names, &String.contains?(&1, "revel/revel")) -> "revel"
      Enum.any?(dep_names, &String.contains?(&1, "kataras/iris")) -> "iris"
      Enum.any?(dep_names, &String.contains?(&1, "goadesign/goa")) -> "goa"
      true -> nil
    end
  end

  defp parse_go_sum(content) do
    lines = String.split(content, "\n") |> Enum.reject(&(&1 == ""))
    dep_count = div(length(lines), 2)

    %{
      type: :go_sum,
      dep_count: dep_count
    }
  end

  defp parse_air_toml(content) do
    bin = extract_regex(content, ~r/bin\s*=\s*"([^"]+)"/)
    cmd = extract_regex(content, ~r/cmd\s*=\s*"([^"]+)"/)
    has_live_reload = String.contains?(content, "[build]")

    %{
      type: :air_config,
      bin: bin,
      cmd: cmd,
      has_live_reload: has_live_reload
    }
  end

  defp parse_golangci(content) do
    has_linters = String.contains?(content, "linters:")
    has_run = String.contains?(content, "run:")

    enabled_linters =
      case Regex.run(~r/enable:\s*\n((?:\s+-\s+\w+\n?)+)/s, content) do
        [_, block] ->
          block
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.replace(&1, ~r/^-\s*/, ""))
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end

    %{
      type: :golangci_config,
      has_linters: has_linters,
      has_run: has_run,
      enabled_linters: enabled_linters
    }
  end

  defp extract_regex(content, regex) do
    case Regex.run(regex, content) do
      [_, match] -> match
      _ -> nil
    end
  end

  defp detect_project_type(parsed_files) do
    file_types =
      parsed_files
      |> Enum.map(& &1[:type])
      |> Enum.reject(&is_nil/1)

    has_rails_markers = :application_rb in file_types or :routes_rb in file_types or :schema_rb in file_types
    gemfile = Enum.find(parsed_files, &(&1[:type] == :gemfile))
    has_rails_gem = gemfile != nil and gemfile[:has_rails] == true

    cond do
      :package_json in file_types and :mix_exs in file_types -> :mixed_elixir
      (has_rails_markers or has_rails_gem) and :gemfile in file_types -> :ruby
      :package_json in file_types and :gemfile in file_types -> :mixed_ruby
      :go_mod in file_types -> :go
      :cargo_toml in file_types -> :rust
      :mix_exs in file_types -> :elixir
      :gemfile in file_types or :gemspec in file_types -> :ruby
      :pyproject in file_types or :requirements_txt in file_types -> :python
      :package_json in file_types -> :node
      true -> :unknown
    end
  end

  defp detect_framework(parsed_files) do
    package_json = Enum.find(parsed_files, &(&1[:type] == :package_json))
    gemfile = Enum.find(parsed_files, &(&1[:type] == :gemfile))
    gemspec = Enum.find(parsed_files, &(&1[:type] == :gemspec))
    go_mod = Enum.find(parsed_files, &(&1[:type] == :go_mod))

    framework_file =
      Enum.find(parsed_files, fn f ->
        f[:framework] != nil
      end)

    cond do
      framework_file != nil ->
        framework_file[:framework]

      go_mod != nil and go_mod[:framework] != nil ->
        go_mod[:framework]

      gemfile != nil ->
        detect_ruby_framework(gemfile, gemspec, parsed_files)

      package_json != nil ->
        deps = Map.merge(package_json[:dependencies] || %{}, package_json[:dev_dependencies] || %{})

        cond do
          Map.has_key?(deps, "next") -> "next"
          Map.has_key?(deps, "nuxt") -> "nuxt"
          Map.has_key?(deps, "@angular/core") -> "angular"
          Map.has_key?(deps, "vue") -> "vue"
          Map.has_key?(deps, "react") -> "react"
          Map.has_key?(deps, "svelte") -> "svelte"
          Map.has_key?(deps, "express") -> "express"
          Map.has_key?(deps, "fastify") -> "fastify"
          true -> nil
        end

      true ->
        nil
    end
  end

  defp detect_ruby_framework(gemfile, gemspec, parsed_files) do
    gems = gemfile[:gems] || []
    gem_names = Enum.map(gems, & &1.name)

    application_rb = Enum.find(parsed_files, &(&1[:type] == :application_rb))
    routes_rb = Enum.find(parsed_files, &(&1[:type] == :routes_rb))

    cond do
      gemfile[:has_rails] or application_rb != nil or routes_rb != nil ->
        "rails"

      "sinatra" in gem_names ->
        "sinatra"

      "hanami" in gem_names ->
        "hanami"

      "grape" in gem_names ->
        "grape"

      "roda" in gem_names ->
        "roda"

      "padrino" in gem_names ->
        "padrino"

      "cuba" in gem_names ->
        "cuba"

      gemspec != nil and gemspec[:name] == "rails" ->
        "rails"

      true ->
        nil
    end
  end

  defp extract_dependencies(parsed_files) do
    package_json = Enum.find(parsed_files, &(&1[:type] == :package_json))
    mix_exs = Enum.find(parsed_files, &(&1[:type] == :mix_exs))
    gemfile = Enum.find(parsed_files, &(&1[:type] == :gemfile))
    gemspec = Enum.find(parsed_files, &(&1[:type] == :gemspec))

    node_deps =
      if package_json do
        deps = package_json[:dependencies] || %{}
        dev_deps = package_json[:dev_dependencies] || %{}

        (Map.keys(deps) ++ Map.keys(dev_deps))
        |> Enum.map(&%{name: &1, ecosystem: :npm})
      else
        []
      end

    elixir_deps =
      if mix_exs do
        (mix_exs[:dependencies] || [])
        |> Enum.map(fn dep -> Map.put(dep, :ecosystem, :hex) end)
      else
        []
      end

    ruby_deps =
      cond do
        gemfile != nil ->
          (gemfile[:gems] || [])
          |> Enum.map(fn gem -> Map.put(gem, :ecosystem, :rubygems) end)

        gemspec != nil ->
          all_deps = (gemspec[:dependencies] || []) ++ (gemspec[:dev_dependencies] || [])
          Enum.map(all_deps, fn dep -> Map.put(dep, :ecosystem, :rubygems) end)

        true ->
          []
      end

    pyproject = Enum.find(parsed_files, &(&1[:type] == :pyproject))
    requirements_files = Enum.filter(parsed_files, &(&1[:type] == :requirements_txt))

    python_deps =
      cond do
        pyproject != nil ->
          main_deps = pyproject[:dependencies] || []
          dev_deps = pyproject[:dev_dependencies] || []

          (main_deps ++ dev_deps)
          |> Enum.map(fn dep ->
            if is_map(dep), do: Map.put(dep, :ecosystem, :pypi), else: %{name: to_string(dep), ecosystem: :pypi}
          end)

        length(requirements_files) > 0 ->
          requirements_files
          |> Enum.flat_map(fn req -> req[:packages] || [] end)
          |> Enum.map(fn pkg ->
            if is_map(pkg), do: Map.put(pkg, :ecosystem, :pypi), else: %{name: to_string(pkg), ecosystem: :pypi}
          end)

        true ->
          []
      end

    go_mod = Enum.find(parsed_files, &(&1[:type] == :go_mod))

    go_deps =
      if go_mod do
        (go_mod[:dependencies] || [])
        |> Enum.map(fn dep ->
          if is_map(dep), do: Map.put(dep, :ecosystem, :go), else: %{name: to_string(dep), ecosystem: :go}
        end)
      else
        []
      end

    node_deps ++ elixir_deps ++ ruby_deps ++ python_deps ++ go_deps
  end

  defp extract_scripts(parsed_files) do
    package_json = Enum.find(parsed_files, &(&1[:type] == :package_json))
    mix_exs = Enum.find(parsed_files, &(&1[:type] == :mix_exs))
    makefile = Enum.find(parsed_files, &(&1[:type] == :makefile))

    rakefile = Enum.find(parsed_files, &(&1[:type] == :rakefile))

    npm_scripts =
      if package_json && package_json[:scripts] do
        package_json[:scripts]
        |> Enum.map(fn {name, cmd} ->
          %{name: name, command: cmd, runner: "npm run"}
        end)
      else
        []
      end

    mix_aliases =
      if mix_exs && mix_exs[:aliases] do
        mix_exs[:aliases]
        |> Enum.map(fn name ->
          %{name: name, command: nil, runner: "mix"}
        end)
      else
        []
      end

    make_targets =
      if makefile && makefile[:targets] do
        makefile[:targets]
        |> Enum.map(fn name ->
          %{name: name, command: nil, runner: "make"}
        end)
      else
        []
      end

    rake_tasks =
      if rakefile && rakefile[:tasks] do
        rakefile[:tasks]
        |> Enum.map(fn name ->
          %{name: name, command: nil, runner: "rake"}
        end)
      else
        []
      end

    npm_scripts ++ mix_aliases ++ make_targets ++ rake_tasks
  end

  defp extract_env_vars(parsed_files) do
    env_file = Enum.find(parsed_files, &(&1[:type] == :env_example))

    if env_file do
      env_file[:variables] || []
    else
      []
    end
  end

  defp extract_docker_config(parsed_files) do
    dockerfile = Enum.find(parsed_files, &(&1[:type] == :dockerfile))
    compose = Enum.find(parsed_files, &(&1[:type] == :docker_compose))

    %{
      has_dockerfile: dockerfile != nil,
      base_image: dockerfile && dockerfile[:base_image],
      exposed_ports: (dockerfile && dockerfile[:exposed_ports]) || [],
      compose_services: (compose && compose[:services]) || []
    }
  end

  defp extract_node_version(parsed_files) do
    nvmrc = Enum.find(parsed_files, &(&1[:type] == :node_version))
    tool_versions = Enum.find(parsed_files, &(&1[:type] == :tool_versions))
    package_json = Enum.find(parsed_files, &(&1[:type] == :package_json))

    cond do
      nvmrc != nil -> nvmrc[:version]
      tool_versions != nil -> tool_versions[:versions]["nodejs"]
      package_json != nil && package_json[:engines] -> package_json[:engines]["node"]
      true -> nil
    end
  end

  defp extract_elixir_version(parsed_files) do
    mix_exs = Enum.find(parsed_files, &(&1[:type] == :mix_exs))
    tool_versions = Enum.find(parsed_files, &(&1[:type] == :tool_versions))

    cond do
      mix_exs != nil && mix_exs[:elixir_version] -> mix_exs[:elixir_version]
      tool_versions != nil -> tool_versions[:versions]["elixir"]
      true -> nil
    end
  end

  defp extract_ruby_version(parsed_files) do
    ruby_version_file = Enum.find(parsed_files, &(&1[:type] == :ruby_version))
    gemfile = Enum.find(parsed_files, &(&1[:type] == :gemfile))
    gemfile_lock = Enum.find(parsed_files, &(&1[:type] == :gemfile_lock))
    tool_versions = Enum.find(parsed_files, &(&1[:type] == :tool_versions))

    cond do
      ruby_version_file != nil -> ruby_version_file[:version]
      gemfile != nil && gemfile[:ruby_version] -> gemfile[:ruby_version]
      gemfile_lock != nil && gemfile_lock[:ruby_version] -> gemfile_lock[:ruby_version]
      tool_versions != nil && tool_versions[:versions]["ruby"] -> tool_versions[:versions]["ruby"]
      true -> nil
    end
  end

  defp extract_go_version(parsed_files) do
    go_mod = Enum.find(parsed_files, &(&1[:type] == :go_mod))
    tool_versions = Enum.find(parsed_files, &(&1[:type] == :tool_versions))

    cond do
      go_mod != nil && go_mod[:go_version] -> go_mod[:go_version]
      tool_versions != nil && tool_versions[:versions]["golang"] -> tool_versions[:versions]["golang"]
      true -> nil
    end
  end

  defp extract_python_version(parsed_files) do
    pyproject = Enum.find(parsed_files, &(&1[:type] == :pyproject))
    tool_versions = Enum.find(parsed_files, &(&1[:type] == :tool_versions))

    cond do
      pyproject != nil && pyproject[:python_version] -> pyproject[:python_version]
      tool_versions != nil && tool_versions[:versions]["python"] -> tool_versions[:versions]["python"]
      true -> nil
    end
  end

  defp extract_make_targets(parsed_files) do
    makefile = Enum.find(parsed_files, &(&1[:type] == :makefile))

    if makefile do
      makefile[:targets] || []
    else
      []
    end
  end

  defp extract_ci_config(parsed_files) do
    github_workflows =
      parsed_files
      |> Enum.filter(&(&1[:type] == :github_workflow))
      |> Enum.map(fn f -> %{name: f[:workflow_name], file: f[:name], triggers: f[:triggers]} end)

    gitlab_ci = Enum.find(parsed_files, &(&1[:type] == :gitlab_ci))
    circleci = Enum.find(parsed_files, &(&1[:type] == :circleci))
    travis = Enum.find(parsed_files, &(&1[:type] == :travis_ci))
    jenkins = Enum.find(parsed_files, &(&1[:type] == :jenkinsfile))
    bitbucket = Enum.find(parsed_files, &(&1[:type] == :bitbucket_pipelines))

    %{
      has_ci:
        length(github_workflows) > 0 or gitlab_ci != nil or circleci != nil or travis != nil or jenkins != nil or
          bitbucket != nil,
      github_actions: github_workflows,
      gitlab_ci: if(gitlab_ci, do: %{stages: gitlab_ci[:stages], jobs: gitlab_ci[:jobs]}, else: nil),
      circleci: if(circleci, do: %{jobs: circleci[:jobs]}, else: nil),
      travis_ci: travis != nil,
      jenkins: jenkins != nil,
      bitbucket: bitbucket != nil
    }
  end

  defp extract_git_workflow(parsed_files) do
    husky_hooks =
      parsed_files
      |> Enum.filter(&(&1[:type] == :husky_hook))
      |> Enum.map(&%{hook: &1[:hook_name], command: &1[:command]})

    pre_commit = Enum.find(parsed_files, &(&1[:type] == :pre_commit_config))
    commitlint = Enum.find(parsed_files, &(&1[:type] == :commitlint_config))
    commitizen = Enum.find(parsed_files, &(&1[:type] == :commitizen_config))
    codeowners = Enum.find(parsed_files, &(&1[:type] == :codeowners))
    pr_template = Enum.find(parsed_files, &(&1[:type] == :pr_template))
    dependabot = Enum.find(parsed_files, &(&1[:type] == :dependabot_config))

    issue_templates =
      parsed_files
      |> Enum.filter(&(&1[:type] == :issue_template))
      |> Enum.map(&%{name: &1[:template_name], file: &1[:name]})

    %{
      has_git_hooks: length(husky_hooks) > 0 or pre_commit != nil,
      husky_hooks: husky_hooks,
      pre_commit: if(pre_commit, do: %{repos: pre_commit[:repos]}, else: nil),
      commitlint: if(commitlint, do: %{extends: commitlint[:extends], rules: commitlint[:rules]}, else: nil),
      commitizen: commitizen != nil,
      codeowners: if(codeowners, do: %{owners: codeowners[:owners]}, else: nil),
      pr_template: pr_template != nil,
      issue_templates: issue_templates,
      dependabot: if(dependabot, do: %{ecosystems: dependabot[:ecosystems]}, else: nil)
    }
  end

  defp extract_code_quality(parsed_files) do
    eslint = Enum.find(parsed_files, &(&1[:type] in [:eslint_config, :eslint_flat_config]))
    prettier = Enum.find(parsed_files, &(&1[:type] == :prettier_config))
    biome = Enum.find(parsed_files, &(&1[:type] == :biome_config))
    stylelint = Enum.find(parsed_files, &(&1[:type] == :stylelint_config))
    tsconfig = Enum.find(parsed_files, &(&1[:type] == :tsconfig))

    rubocop = Enum.find(parsed_files, &(&1[:type] == :rubocop_config))
    standard_rb = Enum.find(parsed_files, &(&1[:type] == :standard_rb))
    gemfile = Enum.find(parsed_files, &(&1[:type] == :gemfile))

    has_rubocop = rubocop != nil or (gemfile != nil and gemfile[:has_rubocop] == true)
    has_standard = standard_rb != nil or (gemfile != nil and gemfile[:has_standard] == true)

    pyproject = Enum.find(parsed_files, &(&1[:type] == :pyproject))
    python_linting = if pyproject, do: pyproject[:linting] || %{}, else: %{}

    has_ruff = python_linting[:has_ruff] == true
    has_mypy = python_linting[:has_mypy] == true
    has_black = python_linting[:has_black] == true
    has_isort = python_linting[:has_isort] == true

    has_python_linting = has_ruff or has_mypy or has_black

    golangci = Enum.find(parsed_files, &(&1[:type] == :golangci_config))
    has_golangci_lint = golangci != nil

    %{
      has_linting:
        eslint != nil or biome != nil or has_rubocop == true or has_standard == true or has_python_linting or
          has_golangci_lint,
      has_formatting:
        prettier != nil or biome != nil or has_rubocop == true or has_standard == true or has_black or has_ruff,
      eslint: if(eslint, do: %{extends: eslint[:extends], plugins: eslint[:plugins]}, else: nil),
      prettier: prettier != nil,
      biome: biome != nil,
      stylelint: stylelint != nil,
      typescript: if(tsconfig, do: %{strict: tsconfig[:strict], target: tsconfig[:target]}, else: nil),
      rubocop:
        if(has_rubocop,
          do: %{
            target_ruby: rubocop && rubocop[:target_ruby_version],
            has_rails_cops: rubocop && rubocop[:has_rails_cops],
            has_rspec_cops: rubocop && rubocop[:has_rspec_cops]
          },
          else: nil
        ),
      standard_rb: has_standard,
      ruff: has_ruff,
      mypy: has_mypy,
      black: has_black,
      isort: has_isort,
      golangci_lint: has_golangci_lint
    }
  end

  defp extract_testing_config(parsed_files) do
    vitest = Enum.find(parsed_files, &(&1[:type] == :vitest_config))
    jest = Enum.find(parsed_files, &(&1[:type] == :jest_config))
    cypress = Enum.find(parsed_files, &(&1[:type] == :cypress_config))
    playwright = Enum.find(parsed_files, &(&1[:type] == :playwright_config))
    storybook_files = Enum.filter(parsed_files, &(&1[:type] == :storybook_config))

    gemfile = Enum.find(parsed_files, &(&1[:type] == :gemfile))
    rspec_config = Enum.find(parsed_files, &(&1[:type] == :rspec_config))
    spec_helper = Enum.find(parsed_files, &(&1[:type] == :spec_helper))

    has_rspec = rspec_config != nil or spec_helper != nil or (gemfile != nil and gemfile[:has_rspec] == true)
    has_minitest = gemfile != nil and gemfile[:has_minitest] == true

    has_cucumber =
      Enum.any?(parsed_files, fn f ->
        f[:type] == :rakefile and f[:has_cucumber] == true
      end) or (gemfile != nil and Enum.any?(gemfile[:gems] || [], fn g -> g.name == "cucumber" end))

    pyproject = Enum.find(parsed_files, &(&1[:type] == :pyproject))
    python_testing = if pyproject, do: pyproject[:testing] || %{}, else: %{}
    has_pytest = python_testing[:has_pytest] == true
    has_coverage = python_testing[:has_coverage] == true

    go_mod = Enum.find(parsed_files, &(&1[:type] == :go_mod))
    has_go_test = go_mod != nil

    has_testify =
      go_mod != nil and
        Enum.any?(go_mod[:dependencies] || [], fn dep ->
          dep_name = if is_map(dep), do: dep[:name] || dep[:module] || "", else: to_string(dep)
          String.contains?(dep_name, "testify")
        end)

    frameworks = []
    frameworks = if vitest, do: frameworks ++ ["vitest"], else: frameworks
    frameworks = if jest, do: frameworks ++ ["jest"], else: frameworks
    frameworks = if cypress, do: frameworks ++ ["cypress"], else: frameworks
    frameworks = if playwright, do: frameworks ++ ["playwright"], else: frameworks
    frameworks = if has_rspec, do: frameworks ++ ["rspec"], else: frameworks
    frameworks = if has_minitest, do: frameworks ++ ["minitest"], else: frameworks
    frameworks = if has_cucumber, do: frameworks ++ ["cucumber"], else: frameworks
    frameworks = if has_pytest, do: frameworks ++ ["pytest"], else: frameworks
    frameworks = if has_go_test, do: frameworks ++ ["go-test"], else: frameworks
    frameworks = if has_testify, do: frameworks ++ ["testify"], else: frameworks

    %{
      has_testing: length(frameworks) > 0,
      frameworks: frameworks,
      has_e2e: cypress != nil or playwright != nil or has_cucumber,
      has_storybook: length(storybook_files) > 0,
      vitest: vitest != nil,
      jest: jest != nil,
      cypress: cypress != nil,
      playwright: playwright != nil,
      rspec: has_rspec,
      minitest: has_minitest,
      cucumber: has_cucumber,
      pytest: has_pytest,
      coverage: has_coverage,
      go_test: has_go_test,
      testify: has_testify
    }
  end

  defp extract_monorepo_config(parsed_files) do
    pnpm_workspace = Enum.find(parsed_files, &(&1[:type] == :pnpm_workspace))
    lerna = Enum.find(parsed_files, &(&1[:type] == :lerna_config))
    nx = Enum.find(parsed_files, &(&1[:type] == :nx_config))
    turbo = Enum.find(parsed_files, &(&1[:type] == :turbo_config))
    rush = Enum.find(parsed_files, &(&1[:type] == :rush_config))

    tool =
      cond do
        nx != nil -> "nx"
        turbo != nil -> "turborepo"
        lerna != nil -> "lerna"
        pnpm_workspace != nil -> "pnpm-workspaces"
        rush != nil -> "rush"
        true -> nil
      end

    %{
      is_monorepo: tool != nil,
      tool: tool,
      workspaces: if(pnpm_workspace, do: pnpm_workspace[:packages], else: nil),
      nx_config: if(nx, do: %{affected: nx[:affected]}, else: nil),
      turbo_config: if(turbo, do: %{pipeline: turbo[:pipeline]}, else: nil)
    }
  end

  defp extract_ai_context_files(parsed_files) do
    claude_md = Enum.find(parsed_files, &(&1[:type] == :claude_md))
    cursorrules = Enum.find(parsed_files, &(&1[:type] == :cursorrules))
    cursorignore = Enum.find(parsed_files, &(&1[:type] == :cursorignore))
    suchconfig = Enum.find(parsed_files, &(&1[:type] == :suchconfig))

    %{
      has_claude_md: claude_md != nil,
      has_cursorrules: cursorrules != nil,
      has_cursorignore: cursorignore != nil,
      has_suchconfig: suchconfig != nil,
      claude_md_preview: if(claude_md, do: claude_md[:content_preview], else: nil),
      suchconfig: if(suchconfig, do: suchconfig[:config], else: nil)
    }
  end

  defp parse_jsconfig(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        compiler_options = Map.get(json, "compilerOptions", %{})

        %{
          type: :jsconfig,
          base_url: compiler_options["baseUrl"],
          paths: compiler_options["paths"],
          target: compiler_options["target"]
        }

      {:error, _} ->
        %{type: :jsconfig, error: "Invalid JSON"}
    end
  end

  defp parse_github_workflow(content, filename) do
    workflow_name =
      case Regex.run(~r/^name:\s*['"]?([^'"\n]+)['"]?/m, content) do
        [_, name] -> String.trim(name)
        _ -> Path.basename(filename, Path.extname(filename))
      end

    triggers =
      case Regex.run(~r/^on:\s*\n((?:\s+.+\n)+)/m, content) do
        [_, trigger_block] ->
          Regex.scan(~r/^\s+(\w+):/m, trigger_block)
          |> Enum.map(fn [_, trigger] -> trigger end)

        _ ->
          case Regex.run(~r/^on:\s*\[([^\]]+)\]/m, content) do
            [_, triggers_str] -> String.split(triggers_str, ~r/,\s*/)
            _ -> []
          end
      end

    jobs =
      Regex.scan(~r/^\s{2}(\w+):\s*$/m, content)
      |> Enum.map(fn [_, job] -> job end)

    %{
      type: :github_workflow,
      workflow_name: workflow_name,
      triggers: triggers,
      jobs: jobs
    }
  end

  defp parse_gitlab_ci(content) do
    stages =
      case Regex.run(~r/^stages:\s*\n((?:\s+-\s+.+\n)+)/m, content) do
        [_, stages_block] ->
          Regex.scan(~r/-\s+(\w+)/m, stages_block)
          |> Enum.map(fn [_, stage] -> stage end)

        _ ->
          []
      end

    jobs =
      Regex.scan(~r/^(\w+):\s*$/m, content)
      |> Enum.map(fn [_, job] -> job end)
      |> Enum.reject(&(&1 in ["stages", "variables", "default", "include", "workflow"]))

    %{
      type: :gitlab_ci,
      stages: stages,
      jobs: jobs
    }
  end

  defp parse_bitbucket_pipelines(content) do
    pipelines =
      Regex.scan(~r/^\s{4}(\w+):/m, content)
      |> Enum.map(fn [_, pipeline] -> pipeline end)

    %{
      type: :bitbucket_pipelines,
      pipelines: pipelines
    }
  end

  defp parse_circleci_config(content) do
    jobs =
      case Regex.run(~r/^jobs:\s*\n((?:\s+.+\n)+)/m, content) do
        [_, jobs_block] ->
          Regex.scan(~r/^\s{2}(\w+):/m, jobs_block)
          |> Enum.map(fn [_, job] -> job end)

        _ ->
          []
      end

    %{
      type: :circleci,
      jobs: jobs
    }
  end

  defp parse_jenkinsfile(content) do
    stages =
      Regex.scan(~r/stage\s*\(\s*['"]([^'"]+)['"]\s*\)/m, content)
      |> Enum.map(fn [_, stage] -> stage end)

    %{
      type: :jenkinsfile,
      stages: stages
    }
  end

  defp parse_travis_ci(content) do
    language = extract_regex(content, ~r/^language:\s*(\w+)/m)

    %{
      type: :travis_ci,
      language: language
    }
  end

  defp parse_husky_hook(content, filename) do
    hook_name = Path.basename(filename)

    %{
      type: :husky_hook,
      hook_name: hook_name,
      command: String.trim(content)
    }
  end

  defp parse_pre_commit_config(content) do
    repos =
      Regex.scan(~r/repo:\s*([^\n]+)/m, content)
      |> Enum.map(fn [_, repo] -> String.trim(repo) end)
      |> Enum.reject(&String.starts_with?(&1, "local"))

    hooks =
      Regex.scan(~r/-\s*id:\s*([^\n]+)/m, content)
      |> Enum.map(fn [_, hook] -> String.trim(hook) end)

    has_ruff = String.contains?(content, "ruff") or Enum.any?(hooks, &String.contains?(&1, "ruff"))
    has_black = String.contains?(content, "black") or Enum.any?(hooks, &String.contains?(&1, "black"))
    has_mypy = String.contains?(content, "mypy") or Enum.any?(hooks, &String.contains?(&1, "mypy"))
    has_isort = String.contains?(content, "isort") or Enum.any?(hooks, &String.contains?(&1, "isort"))
    has_prettier = String.contains?(content, "prettier")
    has_eslint = String.contains?(content, "eslint")
    has_trailing_whitespace = Enum.any?(hooks, &(&1 == "trailing-whitespace"))
    has_end_of_file_fixer = Enum.any?(hooks, &(&1 == "end-of-file-fixer"))

    %{
      type: :pre_commit_config,
      repos: repos,
      hooks: hooks,
      has_ruff: has_ruff,
      has_black: has_black,
      has_mypy: has_mypy,
      has_isort: has_isort,
      has_prettier: has_prettier,
      has_eslint: has_eslint,
      has_trailing_whitespace: has_trailing_whitespace,
      has_end_of_file_fixer: has_end_of_file_fixer,
      hook_count: length(hooks)
    }
  end

  defp parse_commitlint_config(content) do
    extends =
      case Regex.run(~r/extends:\s*\[([^\]]+)\]/m, content) do
        [_, extends_str] ->
          String.split(extends_str, ~r/,\s*/)
          |> Enum.map(&String.replace(&1, ~r/['"]/, ""))

        _ ->
          []
      end

    %{
      type: :commitlint_config,
      extends: extends,
      rules: %{}
    }
  end

  defp parse_commitizen_config(_content) do
    %{
      type: :commitizen_config
    }
  end

  defp parse_codeowners(content) do
    owners =
      content
      |> String.split("\n")
      |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
      |> Enum.map(fn line ->
        case String.split(line, ~r/\s+/, parts: 2) do
          [pattern, owner] -> %{pattern: pattern, owner: String.trim(owner)}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(20)

    %{
      type: :codeowners,
      owners: owners
    }
  end

  defp parse_pr_template(content) do
    sections =
      Regex.scan(~r/^##\s+(.+)$/m, content)
      |> Enum.map(fn [_, section] -> section end)

    %{
      type: :pr_template,
      sections: sections
    }
  end

  defp parse_issue_template(content, filename) do
    template_name =
      case Regex.run(~r/^name:\s*['"]?([^'"\n]+)['"]?/m, content) do
        [_, name] -> String.trim(name)
        _ -> Path.basename(filename, Path.extname(filename))
      end

    %{
      type: :issue_template,
      template_name: template_name
    }
  end

  defp parse_dependabot_config(content) do
    ecosystems =
      Regex.scan(~r/package-ecosystem:\s*['"]?(\w+)['"]?/m, content)
      |> Enum.map(fn [_, eco] -> eco end)

    %{
      type: :dependabot_config,
      ecosystems: ecosystems
    }
  end

  defp parse_eslint_config(content, filename) do
    if String.ends_with?(filename, ".json") or String.ends_with?(filename, ".yaml") or
         String.ends_with?(filename, ".yml") do
      case Jason.decode(content) do
        {:ok, json} ->
          %{
            type: :eslint_config,
            extends: List.wrap(Map.get(json, "extends", [])),
            plugins: List.wrap(Map.get(json, "plugins", []))
          }

        {:error, _} ->
          %{type: :eslint_config, extends: [], plugins: []}
      end
    else
      extends =
        case Regex.run(~r/extends:\s*\[([^\]]+)\]/m, content) do
          [_, extends_str] -> String.split(extends_str, ~r/,\s*/)
          _ -> []
        end

      %{
        type: :eslint_config,
        extends: extends,
        plugins: []
      }
    end
  end

  defp parse_eslint_flat_config(content) do
    plugins =
      Regex.scan(~r/import\s+\w+\s+from\s+['"](@?\w[^'"]+)['"]/m, content)
      |> Enum.map(fn [_, plugin] -> plugin end)
      |> Enum.filter(&String.contains?(&1, "eslint"))

    %{
      type: :eslint_flat_config,
      plugins: plugins
    }
  end

  defp parse_prettier_config(content, filename) do
    if String.ends_with?(filename, ".json") or filename == ".prettierrc" do
      case Jason.decode(content) do
        {:ok, json} ->
          %{
            type: :prettier_config,
            tab_width: Map.get(json, "tabWidth"),
            semi: Map.get(json, "semi"),
            single_quote: Map.get(json, "singleQuote")
          }

        {:error, _} ->
          %{type: :prettier_config}
      end
    else
      %{type: :prettier_config}
    end
  end

  defp parse_biome_config(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        %{
          type: :biome_config,
          formatter: Map.has_key?(json, "formatter"),
          linter: Map.has_key?(json, "linter")
        }

      {:error, _} ->
        %{type: :biome_config}
    end
  end

  defp parse_stylelint_config(_content) do
    %{type: :stylelint_config}
  end

  defp parse_pnpm_workspace(content) do
    packages =
      Regex.scan(~r/-\s+['"]?([^'"\n]+)['"]?/m, content)
      |> Enum.map(fn [_, pkg] -> String.trim(pkg) end)

    %{
      type: :pnpm_workspace,
      packages: packages
    }
  end

  defp parse_lerna_config(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        %{
          type: :lerna_config,
          version: Map.get(json, "version"),
          packages: Map.get(json, "packages", [])
        }

      {:error, _} ->
        %{type: :lerna_config}
    end
  end

  defp parse_nx_config(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        %{
          type: :nx_config,
          affected: Map.get(json, "affected"),
          target_defaults: Map.has_key?(json, "targetDefaults")
        }

      {:error, _} ->
        %{type: :nx_config}
    end
  end

  defp parse_turbo_config(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        pipeline = Map.get(json, "pipeline") || Map.get(json, "tasks", %{})

        %{
          type: :turbo_config,
          pipeline: Map.keys(pipeline)
        }

      {:error, _} ->
        %{type: :turbo_config, pipeline: []}
    end
  end

  defp parse_rush_config(content) do
    case Jason.decode(content) do
      {:ok, json} ->
        %{
          type: :rush_config,
          projects: length(Map.get(json, "projects", []))
        }

      {:error, _} ->
        %{type: :rush_config}
    end
  end

  defp parse_vitest_config(_content) do
    %{type: :vitest_config}
  end

  defp parse_jest_config(content, filename) do
    if String.ends_with?(filename, ".json") do
      case Jason.decode(content) do
        {:ok, json} ->
          %{
            type: :jest_config,
            test_environment: Map.get(json, "testEnvironment"),
            coverage: Map.has_key?(json, "collectCoverage") or Map.has_key?(json, "coverageDirectory")
          }

        {:error, _} ->
          %{type: :jest_config}
      end
    else
      %{type: :jest_config}
    end
  end

  defp parse_cypress_config(_content) do
    %{type: :cypress_config}
  end

  defp parse_playwright_config(_content) do
    %{type: :playwright_config}
  end

  defp parse_storybook_config(_content, filename) do
    %{
      type: :storybook_config,
      file: filename
    }
  end

  defp parse_claude_md(content) do
    sections =
      Regex.scan(~r/^##\s+(.+)$/m, content)
      |> Enum.map(fn [_, section] -> section end)

    %{
      type: :claude_md,
      sections: sections
    }
  end

  defp parse_cursorrules(content) do
    %{
      type: :cursorrules,
      line_count: length(String.split(content, "\n"))
    }
  end

  defp parse_cursorignore(content) do
    patterns =
      content
      |> String.split("\n")
      |> Enum.reject(&(String.starts_with?(&1, "#") or String.trim(&1) == ""))
      |> Enum.take(50)

    %{
      type: :cursorignore,
      patterns: patterns
    }
  end

  def parse_suchconfig(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, config} ->
        %{
          type: :suchconfig,
          config: config
        }

      {:error, _} ->
        case Jason.decode(content) do
          {:ok, config} ->
            %{
              type: :suchconfig,
              config: config
            }

          {:error, _} ->
            %{type: :suchconfig, error: "Invalid YAML or JSON"}
        end
    end
  end
end
