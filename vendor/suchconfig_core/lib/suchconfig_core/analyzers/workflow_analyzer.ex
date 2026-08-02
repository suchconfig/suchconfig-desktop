defmodule SuchConfigCore.Analyzers.WorkflowAnalyzer do
  @moduledoc """
  Workflow analyzer for generating project setup plans.

  This module takes parsed project data from `SuchConfigCore.Parsers.ProjectParser`
  and generates a comprehensive setup plan in markdown format.

  ## Features

  - Detects required runtime versions (Node.js, Elixir, Python, etc.)
  - Generates step-by-step setup instructions
  - Identifies environment variables that need to be configured
  - Suggests common development commands
  - Provides framework-specific setup guidance
  - Extracts setup instructions from README files
  - Generates universal AI context files

  ## Output Formats

  - `:setup_guide` - Traditional markdown setup instructions (default)
  - `:ai_context` - Universal AI context file (save as CLAUDE.md, .cursorrules, or AGENTS.md)
  - `:suchconfig` - Team configuration template

  """

  alias SuchConfigCore.Generators.AIContextGenerator

  @doc """
  Generates a workflow setup plan from parsed project data.

  ## Options

  - `:format` - Output format (`:setup_guide`, `:ai_context`, `:suchconfig`)
    Defaults to `:setup_guide`

  ## Examples

      iex> generate_plan(project_data)
      {:ok, %{markdown: "...", format: :setup_guide, ...}}

      iex> generate_plan(project_data, format: :ai_context)
      {:ok, %{markdown: "...", format: :ai_context, ...}}
  """
  def generate_plan(project_data, options \\ []) when is_map(project_data) do
    format = Keyword.get(options, :format, :setup_guide)

    requirements = detect_requirements(project_data)
    tech_stack = detect_tech_stack(project_data)
    steps = generate_steps(project_data, requirements, tech_stack)
    notes = generate_notes(project_data, tech_stack)
    commands = generate_common_commands(project_data)
    readme_info = extract_readme_info(project_data)

    markdown =
      case format do
        :setup_guide ->
          build_markdown(project_data, requirements, steps, notes, commands, tech_stack, readme_info)

        :ai_context ->
          {:ok, content} = AIContextGenerator.generate(project_data, :ai_context)
          content

        :contributing ->
          {:ok, content} = AIContextGenerator.generate(project_data, :contributing)
          content

        :stack_details ->
          {:ok, content} = AIContextGenerator.generate(project_data, :stack_details)
          content

        :suchconfig ->
          {:ok, content} = AIContextGenerator.generate(project_data, :suchconfig)
          content

        _ ->
          build_markdown(project_data, requirements, steps, notes, commands, tech_stack, readme_info)
      end

    {:ok,
     %{
       markdown: markdown,
       format: format,
       steps: steps,
       requirements: requirements,
       notes: notes,
       commands: commands,
       tech_stack: tech_stack,
       generated_at: DateTime.utc_now()
     }}
  end

  @doc """
  Detects runtime and tool requirements from project data.
  """
  def detect_requirements(project_data) do
    %{
      node: detect_node_requirement(project_data),
      elixir: detect_elixir_requirement(project_data),
      ruby: detect_ruby_requirement(project_data),
      python: detect_python_requirement(project_data),
      go: detect_go_requirement(project_data),
      docker: detect_docker_requirement(project_data),
      database: detect_database_requirement(project_data),
      package_manager: detect_package_manager(project_data),
      build_tool: detect_build_tool(project_data)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp detect_tech_stack(project_data) do
    deps = project_data[:dependencies] || []
    files = project_data[:files] || []
    scripts = project_data[:scripts] || []

    dep_names = Enum.map(deps, & &1[:name]) |> Enum.reject(&is_nil/1)
    script_names = Enum.map(scripts, & &1[:name]) |> Enum.reject(&is_nil/1)

    pyproject = Enum.find(files, &(&1[:type] == :pyproject))

    python_linting =
      if pyproject && pyproject[:linting] do
        pyproject[:linting]
      else
        %{}
      end

    %{
      framework: detect_framework_details(project_data, dep_names),
      orm: detect_orm(dep_names, files),
      auth: detect_auth(dep_names),
      payments: detect_payments(dep_names),
      styling: detect_styling(dep_names, files),
      testing: detect_testing(dep_names, script_names, project_data),
      deployment: detect_deployment(files),
      database_type: detect_database_type(dep_names, project_data),
      has_typescript: "typescript" in dep_names or Enum.any?(files, fn f -> f[:name] == "tsconfig.json" end),
      has_docker: project_data[:docker_config][:has_dockerfile] || false,
      scripts: extract_notable_scripts(scripts),
      python_linting: python_linting,
      python_build_backend: if(pyproject, do: pyproject[:build_backend], else: nil)
    }
  end

  defp detect_framework_details(project_data, dep_names) do
    framework = project_data[:framework]
    py_dep_names = extract_python_dep_names(project_data)

    cond do
      framework == "next" or "next" in dep_names ->
        %{name: "Next.js", type: :fullstack, dev_port: 3000}

      framework == "nuxt" or "nuxt" in dep_names ->
        %{name: "Nuxt", type: :fullstack, dev_port: 3000}

      "vue" in dep_names ->
        %{name: "Vue.js", type: :frontend, dev_port: 5173}

      "react" in dep_names and "express" in dep_names ->
        %{name: "React + Express", type: :fullstack, dev_port: 3000}

      "react" in dep_names ->
        %{name: "React", type: :frontend, dev_port: 3000}

      "@angular/core" in dep_names ->
        %{name: "Angular", type: :frontend, dev_port: 4200}

      "svelte" in dep_names or "sveltekit" in dep_names ->
        %{name: "SvelteKit", type: :fullstack, dev_port: 5173}

      project_data[:project_type] == :elixir ->
        %{name: "Phoenix", type: :fullstack, dev_port: 4000}

      project_data[:project_type] in [:ruby, :mixed_ruby] and project_data[:framework] == "rails" ->
        %{name: "Ruby on Rails", type: :fullstack, dev_port: 3000}

      project_data[:project_type] in [:ruby, :mixed_ruby] and project_data[:framework] == "sinatra" ->
        %{name: "Sinatra", type: :backend, dev_port: 4567}

      project_data[:project_type] in [:ruby, :mixed_ruby] ->
        %{name: "Ruby", type: :backend, dev_port: 3000}

      "fastapi" in py_dep_names ->
        %{name: "FastAPI", type: :backend, dev_port: 8000}

      "django" in py_dep_names ->
        %{name: "Django", type: :fullstack, dev_port: 8000}

      "flask" in py_dep_names ->
        %{name: "Flask", type: :backend, dev_port: 5000}

      "starlette" in py_dep_names ->
        %{name: "Starlette", type: :backend, dev_port: 8000}

      "tornado" in py_dep_names ->
        %{name: "Tornado", type: :backend, dev_port: 8888}

      "aiohttp" in py_dep_names ->
        %{name: "aiohttp", type: :backend, dev_port: 8080}

      project_data[:project_type] == :go and project_data[:framework] == "huma" ->
        %{name: "Huma", type: :backend, dev_port: 8081}

      project_data[:project_type] == :go and project_data[:framework] == "gin" ->
        %{name: "Gin", type: :backend, dev_port: 8080}

      project_data[:project_type] == :go and project_data[:framework] == "echo" ->
        %{name: "Echo", type: :backend, dev_port: 8080}

      project_data[:project_type] == :go and project_data[:framework] == "chi" ->
        %{name: "Chi", type: :backend, dev_port: 8080}

      project_data[:project_type] == :go and project_data[:framework] == "fiber" ->
        %{name: "Fiber", type: :backend, dev_port: 3000}

      project_data[:project_type] == :go and project_data[:framework] == "gorilla" ->
        %{name: "Gorilla Mux", type: :backend, dev_port: 8080}

      project_data[:project_type] == :go ->
        %{name: "Go", type: :backend, dev_port: 8080}

      true ->
        nil
    end
  end

  defp extract_python_dep_names(project_data) do
    files = project_data[:files] || []
    pyproject = Enum.find(files, &(&1[:type] == :pyproject))
    requirements = Enum.find(files, &(&1[:type] == :requirements_txt))

    project_name =
      if pyproject && pyproject[:name] do
        [String.downcase(pyproject[:name])]
      else
        []
      end

    py_deps =
      cond do
        pyproject && pyproject[:dependencies] ->
          Enum.map(pyproject[:dependencies], fn dep ->
            String.downcase(dep[:name] || "")
          end)

        requirements && requirements[:dependencies] ->
          Enum.map(requirements[:dependencies], fn dep ->
            String.downcase(dep[:name] || "")
          end)

        true ->
          []
      end

    project_name ++ py_deps
  end

  defp detect_orm(dep_names, files) do
    cond do
      "drizzle-orm" in dep_names ->
        %{
          name: "Drizzle ORM",
          setup_cmd: "pnpm db:migrate",
          has_config: Enum.any?(files, fn f -> String.contains?(f[:name] || "", "drizzle") end)
        }

      "prisma" in dep_names or "@prisma/client" in dep_names ->
        %{name: "Prisma", setup_cmd: "npx prisma migrate dev", has_config: true}

      "typeorm" in dep_names ->
        %{name: "TypeORM", setup_cmd: "npm run migration:run", has_config: true}

      "sequelize" in dep_names ->
        %{name: "Sequelize", setup_cmd: "npx sequelize-cli db:migrate", has_config: true}

      "ecto" in dep_names or "ecto_sql" in dep_names ->
        %{name: "Ecto", setup_cmd: "mix ecto.setup", has_config: true}

      "mongoose" in dep_names ->
        %{name: "Mongoose", setup_cmd: nil, has_config: false}

      true ->
        nil
    end
  end

  defp detect_auth(dep_names) do
    cond do
      "next-auth" in dep_names or "@auth/core" in dep_names ->
        %{name: "NextAuth.js", requires_secret: true}

      "passport" in dep_names ->
        %{name: "Passport.js", requires_secret: false}

      "lucia" in dep_names or "lucia-auth" in dep_names ->
        %{name: "Lucia Auth", requires_secret: true}

      "clerk" in dep_names or "@clerk/nextjs" in dep_names ->
        %{name: "Clerk", requires_api_key: true}

      "supabase" in dep_names or "@supabase/supabase-js" in dep_names ->
        %{name: "Supabase Auth", requires_api_key: true}

      true ->
        nil
    end
  end

  defp detect_payments(dep_names) do
    cond do
      "stripe" in dep_names or "@stripe/stripe-js" in dep_names ->
        %{name: "Stripe", requires_keys: ["STRIPE_SECRET_KEY", "STRIPE_WEBHOOK_SECRET"], has_cli: true}

      "paypal" in dep_names or "@paypal/checkout-server-sdk" in dep_names ->
        %{name: "PayPal", requires_keys: ["PAYPAL_CLIENT_ID", "PAYPAL_CLIENT_SECRET"], has_cli: false}

      "lemon-squeezy" in dep_names or "@lemonsqueezy/lemonsqueezy.js" in dep_names ->
        %{name: "Lemon Squeezy", requires_keys: ["LEMON_SQUEEZY_API_KEY"], has_cli: false}

      true ->
        nil
    end
  end

  defp detect_styling(dep_names, files) do
    styles = []

    styles = if "tailwindcss" in dep_names, do: styles ++ ["Tailwind CSS"], else: styles

    styles =
      if Enum.any?(files, fn f -> String.contains?(f[:name] || "", "tailwind") end),
        do: styles ++ ["Tailwind CSS"],
        else: styles

    styles = if "styled-components" in dep_names, do: styles ++ ["Styled Components"], else: styles
    styles = if "@emotion/react" in dep_names, do: styles ++ ["Emotion"], else: styles
    styles = if "sass" in dep_names, do: styles ++ ["Sass"], else: styles

    styles |> Enum.uniq()
  end

  defp detect_testing(dep_names, script_names, project_data) do
    frameworks = []

    frameworks = if "vitest" in dep_names, do: frameworks ++ ["Vitest"], else: frameworks
    frameworks = if "jest" in dep_names, do: frameworks ++ ["Jest"], else: frameworks
    frameworks = if "@playwright/test" in dep_names, do: frameworks ++ ["Playwright"], else: frameworks
    frameworks = if "cypress" in dep_names, do: frameworks ++ ["Cypress"], else: frameworks

    pyproject = if project_data, do: Enum.find(project_data[:files] || [], &(&1[:type] == :pyproject)), else: nil

    frameworks =
      if pyproject && pyproject[:testing] && pyproject[:testing][:has_pytest] do
        frameworks ++ ["pytest"]
      else
        frameworks
      end

    has_test_script = "test" in script_names

    %{frameworks: Enum.uniq(frameworks), has_test_script: has_test_script}
  end

  defp detect_deployment(files) do
    file_names = Enum.map(files, & &1[:name]) |> Enum.reject(&is_nil/1)

    cond do
      "vercel.json" in file_names -> %{platform: "Vercel", config_file: "vercel.json"}
      "netlify.toml" in file_names -> %{platform: "Netlify", config_file: "netlify.toml"}
      "fly.toml" in file_names -> %{platform: "Fly.io", config_file: "fly.toml"}
      "railway.json" in file_names -> %{platform: "Railway", config_file: "railway.json"}
      "render.yaml" in file_names -> %{platform: "Render", config_file: "render.yaml"}
      true -> nil
    end
  end

  defp detect_database_type(dep_names, project_data) do
    env_vars = project_data[:env_vars] || []
    env_keys = Enum.map(env_vars, & &1[:key]) |> Enum.reject(&is_nil/1)

    cond do
      "pg" in dep_names or "postgres" in dep_names or "postgrex" in dep_names ->
        %{type: "PostgreSQL", env_var: "POSTGRES_URL"}

      Enum.any?(env_keys, &String.contains?(&1, "POSTGRES")) ->
        %{type: "PostgreSQL", env_var: Enum.find(env_keys, &String.contains?(&1, "POSTGRES"))}

      "mysql2" in dep_names or "mysql" in dep_names ->
        %{type: "MySQL", env_var: "DATABASE_URL"}

      "mongodb" in dep_names or "mongoose" in dep_names ->
        %{type: "MongoDB", env_var: "MONGODB_URI"}

      "better-sqlite3" in dep_names or "sqlite3" in dep_names ->
        %{type: "SQLite", env_var: nil}

      true ->
        nil
    end
  end

  defp extract_notable_scripts(scripts) do
    notable = [
      "dev",
      "build",
      "start",
      "test",
      "lint",
      "db:setup",
      "db:migrate",
      "db:seed",
      "db:push",
      "db:studio",
      "generate",
      "typecheck",
      "format"
    ]

    scripts
    |> Enum.filter(fn s -> s[:name] in notable end)
    |> Enum.map(fn s -> %{name: s[:name], command: s[:command], runner: s[:runner]} end)
  end

  defp detect_node_requirement(project_data) do
    case project_data[:node_version] do
      nil ->
        if project_data[:project_type] in [:node, :mixed] do
          %{version: "18.x or later (LTS recommended)", required: true}
        else
          nil
        end

      version ->
        %{version: version, required: true}
    end
  end

  defp detect_elixir_requirement(project_data) do
    case project_data[:elixir_version] do
      nil ->
        if project_data[:project_type] in [:elixir, :mixed_elixir] do
          %{version: "1.15+ (recommended)", required: true}
        else
          nil
        end

      version ->
        %{version: version, required: true}
    end
  end

  defp detect_ruby_requirement(project_data) do
    if project_data[:project_type] in [:ruby, :mixed_ruby] do
      version = project_data[:ruby_version] || "3.0+ (recommended)"
      %{version: version, required: true}
    else
      nil
    end
  end

  defp detect_python_requirement(project_data) do
    if project_data[:project_type] == :python do
      python_file =
        Enum.find(project_data[:files] || [], fn f ->
          f[:type] in [:pyproject, :requirements_txt]
        end)

      version =
        if python_file && python_file[:python_version] do
          python_file[:python_version]
        else
          "3.8+ (recommended)"
        end

      %{version: version, required: true}
    else
      nil
    end
  end

  defp detect_go_requirement(project_data) do
    if project_data[:project_type] == :go do
      version = project_data[:go_version] || "1.21+ (recommended)"
      %{version: version, required: true}
    else
      nil
    end
  end

  defp detect_docker_requirement(project_data) do
    docker_config = project_data[:docker_config] || %{}

    if docker_config[:has_dockerfile] || length(docker_config[:compose_services] || []) > 0 do
      %{required: true, has_compose: length(docker_config[:compose_services] || []) > 0}
    else
      nil
    end
  end

  defp detect_database_requirement(project_data) do
    deps = project_data[:dependencies] || []
    docker_services = (project_data[:docker_config] || %{})[:compose_services] || []

    db_deps =
      deps
      |> Enum.map(& &1[:name])
      |> Enum.filter(fn name ->
        name in [
          "pg",
          "postgres",
          "postgresql",
          "mysql",
          "mysql2",
          "mongodb",
          "mongoose",
          "redis",
          "ioredis",
          "ecto",
          "ecto_sql",
          "postgrex",
          "myxql",
          "sqlite3",
          "better-sqlite3",
          "prisma",
          "@prisma/client",
          "drizzle-orm"
        ]
      end)

    db_services =
      docker_services
      |> Enum.filter(fn svc ->
        String.contains?(svc, ["postgres", "mysql", "mongo", "redis", "db", "database"])
      end)

    if length(db_deps) > 0 or length(db_services) > 0 do
      %{detected_deps: db_deps, docker_services: db_services}
    else
      nil
    end
  end

  defp detect_package_manager(project_data) do
    project_type = project_data[:project_type]

    cond do
      project_type in [:ruby] ->
        "bundler"

      project_type in [:node, :mixed_elixir, :mixed_ruby] ->
        path = project_data[:path] || ""

        cond do
          path != "" and File.exists?(Path.join(path, "pnpm-lock.yaml")) -> "pnpm"
          path != "" and File.exists?(Path.join(path, "yarn.lock")) -> "yarn"
          path != "" and File.exists?(Path.join(path, "bun.lockb")) -> "bun"
          true -> "npm"
        end

      true ->
        nil
    end
  end

  defp detect_build_tool(project_data) do
    files = project_data[:files] || []

    cond do
      Enum.any?(files, fn f -> f[:bundler] == "vite" end) -> "vite"
      Enum.any?(files, fn f -> f[:bundler] == "webpack" end) -> "webpack"
      Enum.any?(files, fn f -> f[:framework] == "next" end) -> "next"
      Enum.any?(files, fn f -> f[:framework] == "nuxt" end) -> "nuxt"
      true -> nil
    end
  end

  defp extract_readme_info(project_data) do
    readme = Enum.find(project_data[:files] || [], fn f -> f[:type] == :readme end)

    if readme && readme[:content_preview] do
      content = readme[:content_preview]

      %{
        has_getting_started: String.contains?(content, ["Getting Started", "Quick Start", "Quickstart"]),
        has_prerequisites: String.contains?(content, ["Prerequisites", "Requirements"]),
        has_installation: String.contains?(content, ["Installation", "Install", "Setup"]),
        has_env_setup: String.contains?(content, [".env", "environment"]),
        title: readme[:title]
      }
    else
      %{}
    end
  end

  defp generate_steps(project_data, requirements, tech_stack) do
    steps = []
    pkg_mgr = requirements[:package_manager] || "npm"
    scripts = tech_stack[:scripts] || []
    script_names = Enum.map(scripts, & &1[:name])

    steps = steps ++ generate_prerequisites_steps(requirements, tech_stack)

    steps =
      if tech_stack[:payments] && tech_stack[:payments][:has_cli] do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Install #{tech_stack[:payments][:name]} CLI",
              description:
                "Install and authenticate with the #{tech_stack[:payments][:name]} CLI for local development",
              command: "#{pkg_mgr} install -g stripe\nstripe login",
              category: :tooling,
              important: true
            }
          ]
      else
        steps
      end

    steps =
      if "db:setup" in script_names do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Setup Environment",
              description: "Run the database setup script to create your `.env` file with required configuration",
              command: "#{pkg_mgr} run db:setup",
              category: :configuration
            }
          ]
      else
        if length(project_data[:env_vars] || []) > 0 do
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Configure Environment Variables",
                description: "Copy the example env file and configure your values",
                command: "cp .env.example .env",
                category: :configuration
              }
            ]
        else
          steps
        end
      end

    steps =
      cond do
        project_data[:project_type] == :python ->
          pyproject = Enum.find(project_data[:files] || [], &(&1[:type] == :pyproject))
          build_backend = if pyproject, do: pyproject[:build_backend], else: nil

          install_cmd =
            case build_backend do
              "poetry" -> "poetry install"
              "pdm" -> "pdm install"
              "hatch" -> "pip install -e .[dev]"
              _ -> "pip install -e .[dev]"
            end

          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Create Virtual Environment",
                description: "Create and activate a Python virtual environment",
                command: "python -m venv venv\nsource venv/bin/activate  # On Windows: .\\venv\\Scripts\\activate",
                category: :environment
              },
              %{
                order: length(steps) + 1,
                title: "Install Dependencies",
                description: "Install all project dependencies",
                command: install_cmd,
                category: :dependencies
              }
            ]

        project_data[:project_type] in [:ruby, :mixed_ruby] ->
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Install Ruby Dependencies",
                description: "Install all Ruby gems using Bundler",
                command: "bundle install",
                category: :dependencies
              }
            ]

        project_data[:project_type] == :go ->
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Install Go Dependencies",
                description: "Download and install Go module dependencies",
                command: "go mod download",
                category: :dependencies
              }
            ]

        pkg_mgr == "pnpm" ->
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Install Dependencies",
                description: "Install all project dependencies using pnpm",
                command: "pnpm install",
                category: :dependencies
              }
            ]

        pkg_mgr == "yarn" ->
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Install Dependencies",
                description: "Install all project dependencies using yarn",
                command: "yarn",
                category: :dependencies
              }
            ]

        pkg_mgr == "bun" ->
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Install Dependencies",
                description: "Install all project dependencies using bun",
                command: "bun install",
                category: :dependencies
              }
            ]

        true ->
          steps ++
            [
              %{
                order: length(steps) + 1,
                title: "Install Dependencies",
                description: "Install all project dependencies using npm",
                command: "npm install",
                category: :dependencies
              }
            ]
      end

    steps =
      if project_data[:project_type] in [:elixir, :mixed_elixir] do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Install Elixir Dependencies",
              description: "Fetch and compile Elixir dependencies",
              command: "mix deps.get && mix deps.compile",
              category: :dependencies
            }
          ]
      else
        steps
      end

    steps = steps ++ generate_database_steps(project_data, requirements, tech_stack, pkg_mgr, script_names)

    steps =
      if tech_stack[:payments] && tech_stack[:payments][:has_cli] do
        framework = tech_stack[:framework]
        port = if framework, do: framework[:dev_port], else: 3000

        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Start #{tech_stack[:payments][:name]} Webhook Listener",
              description: "In a separate terminal, start the webhook listener for local payment testing",
              command: "stripe listen --forward-to localhost:#{port}/api/stripe/webhook",
              category: :tooling,
              separate_terminal: true
            }
          ]
      else
        steps
      end

    steps ++ [generate_start_step(project_data, requirements, tech_stack, pkg_mgr)]
  end

  defp generate_prerequisites_steps(requirements, tech_stack) do
    steps = []

    steps =
      if requirements[:node] do
        steps ++
          [
            %{
              order: 1,
              title: "Install Node.js",
              description:
                "Ensure you have Node.js #{requirements[:node][:version]} installed. Use nvm for easy version management.",
              command:
                "nvm install #{String.replace(requirements[:node][:version], ~r/\s.*/, "")}\nnvm use #{String.replace(requirements[:node][:version], ~r/\s.*/, "")}",
              category: :runtime
            }
          ]
      else
        steps
      end

    steps =
      if requirements[:elixir] do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Install Elixir",
              description:
                "Install Elixir #{requirements[:elixir][:version]} using asdf or your preferred version manager",
              command: "asdf install elixir #{requirements[:elixir][:version]}",
              category: :runtime
            }
          ]
      else
        steps
      end

    steps =
      if requirements[:ruby] do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Install Ruby",
              description:
                "Install Ruby #{requirements[:ruby][:version]} using rbenv, asdf, or your preferred version manager",
              command:
                "rbenv install #{String.replace(requirements[:ruby][:version], ~r/\s.*/, "")}\nrbenv local #{String.replace(requirements[:ruby][:version], ~r/\s.*/, "")}",
              category: :runtime
            }
          ]
      else
        steps
      end

    steps =
      if requirements[:go] do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Install Go",
              description: "Install Go #{requirements[:go][:version]} using asdf or download from go.dev",
              command:
                "# Using asdf:\nasdf install golang #{String.replace(requirements[:go][:version], ~r/\s.*/, "")}\nasdf local golang #{String.replace(requirements[:go][:version], ~r/\s.*/, "")}\n\n# Or download from https://go.dev/dl/",
              category: :runtime
            }
          ]
      else
        steps
      end

    steps =
      if requirements[:docker] && requirements[:docker][:has_compose] do
        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Start Docker Services",
              description: "Start required Docker services (databases, caches, etc.)",
              command: "docker-compose up -d",
              category: :infrastructure
            }
          ]
      else
        steps
      end

    steps =
      if tech_stack[:database_type] && is_nil(requirements[:docker]) do
        db = tech_stack[:database_type]

        steps ++
          [
            %{
              order: length(steps) + 1,
              title: "Setup #{db[:type]} Database",
              description: "Ensure you have a #{db[:type]} database running locally or have a cloud database URL ready",
              command:
                "# Local: Install and start #{db[:type]}\n# Cloud: Get your connection string from your provider",
              category: :infrastructure,
              manual: true
            }
          ]
      else
        steps
      end

    steps
  end

  defp generate_database_steps(_project_data, requirements, tech_stack, pkg_mgr, script_names) do
    steps = []

    if requirements[:database] do
      orm = tech_stack[:orm]

      steps =
        cond do
          "db:migrate" in script_names and "db:seed" in script_names ->
            steps ++
              [
                %{
                  order: 100,
                  title: "Run Database Migrations",
                  description: "Create the database schema by running migrations",
                  command: "#{pkg_mgr} run db:migrate",
                  category: :database
                },
                %{
                  order: 101,
                  title: "Seed Database",
                  description: "Populate the database with initial data (default users, sample data, etc.)",
                  command: "#{pkg_mgr} run db:seed",
                  category: :database
                }
              ]

          "db:push" in script_names ->
            steps ++
              [
                %{
                  order: 100,
                  title: "Push Database Schema",
                  description: "Push the schema to your database",
                  command: "#{pkg_mgr} run db:push",
                  category: :database
                }
              ]

          orm && orm[:setup_cmd] ->
            steps ++
              [
                %{
                  order: 100,
                  title: "Setup Database",
                  description: "Run #{orm[:name]} migrations to create the database schema",
                  command: orm[:setup_cmd],
                  category: :database
                }
              ]

          true ->
            steps
        end

      steps
    else
      steps
    end
  end

  defp generate_start_step(project_data, _requirements, tech_stack, pkg_mgr) do
    scripts = tech_stack[:scripts] || []
    framework = tech_stack[:framework]

    dev_script = Enum.find(scripts, fn s -> s[:name] == "dev" end)
    start_script = Enum.find(scripts, fn s -> s[:name] == "start" end)

    {command, url, description} =
      cond do
        project_data[:project_type] == :python ->
          pyproject = Enum.find(project_data[:files] || [], &(&1[:type] == :pyproject))
          py_scripts = if pyproject, do: pyproject[:scripts] || [], else: []
          py_name = if pyproject, do: pyproject[:name], else: nil
          py_name_lower = if py_name, do: String.downcase(py_name), else: nil

          is_fastapi =
            (is_map(framework) and framework[:name] == "FastAPI") or py_name_lower == "fastapi"

          is_django =
            (is_map(framework) and framework[:name] == "Django") or py_name_lower == "django"

          is_flask =
            (is_map(framework) and framework[:name] == "Flask") or py_name_lower == "flask"

          cond do
            Enum.any?(py_scripts, fn s -> s[:name] in ["dev", "start", "serve"] end) ->
              script = Enum.find(py_scripts, fn s -> s[:name] in ["dev", "start", "serve"] end)
              {"#{script[:name]}", "http://localhost:8000", "Start the development server"}

            is_fastapi ->
              {"uvicorn #{py_name || "main"}:app --reload", "http://localhost:8000",
               "Start the FastAPI development server with hot reload"}

            is_django ->
              {"python manage.py runserver", "http://localhost:8000", "Start the Django development server"}

            is_flask ->
              {"flask run --debug", "http://localhost:5000", "Start the Flask development server with debug mode"}

            true ->
              {"python -m #{py_name || "main"}", nil, "Run the Python application"}
          end

        dev_script ->
          port = if framework, do: framework[:dev_port], else: 3000
          {"#{pkg_mgr} run dev", "http://localhost:#{port}", "Start the development server with hot reload"}

        framework && framework[:name] == "Phoenix" ->
          {"mix phx.server", "http://localhost:4000", "Start the Phoenix development server"}

        start_script ->
          port = if framework, do: framework[:dev_port], else: 3000
          {"#{pkg_mgr} start", "http://localhost:#{port}", "Start the application"}

        project_data[:project_type] == :elixir ->
          {"mix phx.server", "http://localhost:4000", "Start the Phoenix development server"}

        project_data[:project_type] in [:ruby, :mixed_ruby] and project_data[:framework] == "rails" ->
          {"bin/rails server", "http://localhost:3000", "Start the Rails development server"}

        project_data[:project_type] in [:ruby, :mixed_ruby] and project_data[:framework] == "sinatra" ->
          {"ruby app.rb", "http://localhost:4567", "Start the Sinatra application"}

        project_data[:project_type] in [:ruby, :mixed_ruby] ->
          {"bundle exec rackup", "http://localhost:9292", "Start the Rack application"}

        project_data[:project_type] == :go ->
          files = project_data[:files] || []
          air_config = Enum.find(files, &(&1[:type] == :air_config))
          makefile = Enum.find(files, &(&1[:type] == :makefile))
          make_targets = if makefile, do: makefile[:targets] || [], else: []
          port = if framework, do: framework[:dev_port], else: 8080

          cond do
            Enum.member?(make_targets, "run") ->
              {"make run", "http://localhost:#{port}", "Start the application with Make"}

            air_config != nil ->
              {"air", "http://localhost:#{port}", "Start the Go server with hot reload (Air)"}

            Enum.member?(make_targets, "build") ->
              {"make build && ./bin/server", "http://localhost:#{port}", "Build and start the Go server"}

            true ->
              {"go run ./cmd/api/main.go", "http://localhost:#{port}", "Start the Go server"}
          end

        true ->
          {"#{pkg_mgr} run dev", "http://localhost:3000", "Start the development server"}
      end

    %{
      order: 999,
      title: "Start Development Server",
      description: description,
      command: command,
      url: url,
      category: :run
    }
  end

  defp generate_notes(project_data, tech_stack) do
    notes = []

    notes =
      if length(project_data[:env_vars] || []) > 0 do
        env_vars = project_data[:env_vars]

        grouped =
          env_vars
          |> Enum.group_by(fn var ->
            key = var[:key] || ""

            cond do
              String.contains?(key, "STRIPE") -> :payments
              String.contains?(key, ["DATABASE", "POSTGRES", "MYSQL", "MONGO"]) -> :database
              String.contains?(key, ["AUTH", "SECRET", "JWT"]) -> :auth
              String.contains?(key, ["API_KEY", "API_SECRET"]) -> :api
              true -> :other
            end
          end)

        notes =
          if grouped[:database] do
            db_vars = Enum.map_join(grouped[:database], ", ", & &1[:key])

            notes ++
              [
                %{
                  type: :warning,
                  title: "Database Configuration Required",
                  content: "Configure your database connection: #{db_vars}"
                }
              ]
          else
            notes
          end

        notes =
          if grouped[:payments] do
            payment_vars = Enum.map_join(grouped[:payments], ", ", & &1[:key])

            notes ++
              [
                %{
                  type: :warning,
                  title: "Payment Integration Setup",
                  content:
                    "Configure payment provider keys: #{payment_vars}. For Stripe, run `stripe login` to authenticate."
                }
              ]
          else
            notes
          end

        notes =
          if grouped[:auth] do
            auth_vars = Enum.map_join(grouped[:auth], ", ", & &1[:key])

            notes ++
              [
                %{
                  type: :info,
                  title: "Authentication Secrets",
                  content:
                    "Generate secure secrets for: #{auth_vars}. Use `openssl rand -base64 32` to generate random strings."
                }
              ]
          else
            notes
          end

        notes
      else
        notes
      end

    notes =
      if tech_stack[:framework] do
        framework = tech_stack[:framework]

        notes ++
          [
            %{
              type: :info,
              title: "#{framework[:name]} Project",
              content:
                "This is a #{framework[:name]} application. Development server runs on port #{framework[:dev_port]}."
            }
          ]
      else
        notes
      end

    notes =
      if tech_stack[:orm] do
        orm = tech_stack[:orm]

        notes ++
          [
            %{
              type: :tip,
              title: "Database ORM: #{orm[:name]}",
              content: "This project uses #{orm[:name]} for database access. Check the schema files for the data model."
            }
          ]
      else
        notes
      end

    notes =
      if tech_stack[:payments] do
        payments = tech_stack[:payments]

        test_info =
          if payments[:name] == "Stripe" do
            " Use test card 4242 4242 4242 4242 with any future expiry and CVC."
          else
            ""
          end

        notes ++
          [
            %{
              type: :tip,
              title: "Testing #{payments[:name]} Payments",
              content: "Use #{payments[:name]} test mode for development.#{test_info}"
            }
          ]
      else
        notes
      end

    notes =
      if project_data[:docker_config] && project_data[:docker_config][:has_dockerfile] do
        notes ++
          [
            %{
              type: :info,
              title: "Docker Available",
              content:
                "This project includes Docker configuration. You can run it in a container using `docker build` and `docker run`."
            }
          ]
      else
        notes
      end

    notes =
      if length(tech_stack[:testing][:frameworks] || []) > 0 do
        frameworks = Enum.join(tech_stack[:testing][:frameworks], ", ")

        notes ++
          [
            %{
              type: :info,
              title: "Testing Setup",
              content: "This project uses #{frameworks} for testing. Run the test suite before making changes."
            }
          ]
      else
        notes
      end

    notes
  end

  defp generate_common_commands(project_data) do
    scripts = project_data[:scripts] || []
    make_targets = project_data[:make_targets] || []
    pkg_mgr = detect_package_manager(project_data) || "npm"

    common_script_names = [
      "test",
      "lint",
      "build",
      "format",
      "check",
      "typecheck",
      "db:studio",
      "db:generate",
      "dev",
      "start"
    ]

    script_commands =
      scripts
      |> Enum.filter(fn s -> s[:name] in common_script_names end)
      |> Enum.map(fn s ->
        %{
          name: s[:name],
          command: "#{pkg_mgr} run #{s[:name]}",
          description: describe_command(s[:name])
        }
      end)

    make_commands =
      make_targets
      |> Enum.filter(fn t -> t in ["test", "lint", "build", "format", "check", "dev"] end)
      |> Enum.map(fn t ->
        %{
          name: t,
          command: "make #{t}",
          description: describe_command(t)
        }
      end)

    script_commands ++ make_commands
  end

  defp describe_command(name) do
    case name do
      "test" -> "Run the test suite"
      "lint" -> "Run linting checks"
      "build" -> "Build for production"
      "format" -> "Format code"
      "check" -> "Run all checks"
      "typecheck" -> "Run TypeScript type checking"
      "db:studio" -> "Open database GUI"
      "db:generate" -> "Generate database types/migrations"
      "dev" -> "Start development server"
      "start" -> "Start production server"
      _ -> "Run #{name}"
    end
  end

  defp build_markdown(project_data, requirements, steps, notes, commands, tech_stack, _readme_info) do
    project_name = project_data[:project_name] || "Project"

    type_label = build_type_label(project_data, tech_stack)

    sections = [
      "# #{project_name} Setup Guide\n",
      "> #{type_label}\n",
      "---\n",
      build_tech_stack_section(tech_stack),
      build_dependencies_section(project_data),
      build_requirements_section(requirements),
      build_steps_section(steps),
      build_test_credentials_section(tech_stack),
      build_commands_section(commands),
      build_notes_section(notes),
      build_production_section(tech_stack),
      build_footer()
    ]

    Enum.join(sections, "\n")
  end

  defp build_type_label(project_data, tech_stack) do
    framework = tech_stack[:framework]
    project_type = project_data[:project_type]

    base_type =
      case project_type do
        :node -> "Node.js"
        :elixir -> "Elixir/Phoenix"
        :ruby -> "Ruby"
        :mixed_elixir -> "Full-Stack (Elixir)"
        :mixed_ruby -> "Full-Stack (Ruby)"
        :python -> "Python"
        :rust -> "Rust"
        :go -> "Go"
        _ -> "Project"
      end

    framework_name = if framework, do: framework[:name], else: nil
    orm_name = if tech_stack[:orm], do: tech_stack[:orm][:name], else: nil
    db_type = if tech_stack[:database_type], do: tech_stack[:database_type][:type], else: nil

    parts = [framework_name, orm_name, db_type] |> Enum.reject(&is_nil/1)

    if length(parts) > 0 do
      "#{base_type} (#{Enum.join(parts, ", ")})"
    else
      base_type
    end
  end

  defp build_tech_stack_section(tech_stack) do
    items = []

    items =
      if tech_stack[:framework] do
        items ++ ["**Framework**: #{tech_stack[:framework][:name]}"]
      else
        items
      end

    items =
      if tech_stack[:orm] do
        items ++ ["**ORM**: #{tech_stack[:orm][:name]}"]
      else
        items
      end

    items =
      if tech_stack[:database_type] do
        items ++ ["**Database**: #{tech_stack[:database_type][:type]}"]
      else
        items
      end

    items =
      if tech_stack[:auth] do
        items ++ ["**Auth**: #{tech_stack[:auth][:name]}"]
      else
        items
      end

    items =
      if tech_stack[:payments] do
        items ++ ["**Payments**: #{tech_stack[:payments][:name]}"]
      else
        items
      end

    items =
      if length(tech_stack[:styling] || []) > 0 do
        items ++ ["**Styling**: #{Enum.join(tech_stack[:styling], ", ")}"]
      else
        items
      end

    items =
      if tech_stack[:has_typescript] do
        items ++ ["**TypeScript**: Yes"]
      else
        items
      end

    if length(items) > 0 do
      """
      ## Tech Stack

      #{Enum.map_join(items, "\n", fn item -> "- #{item}" end)}
      """
    else
      ""
    end
  end

  defp build_dependencies_section(project_data) do
    files = project_data[:files] || []
    package_json = Enum.find(files, &(&1[:type] == :package_json))

    if package_json do
      deps = package_json[:dependencies] || %{}
      dev_deps = package_json[:dev_dependencies] || %{}

      if map_size(deps) == 0 and map_size(dev_deps) == 0 do
        ""
      else
        categorized = categorize_dependencies(deps, dev_deps)

        sections =
          categorized
          |> Enum.filter(fn {_category, packages} -> length(packages) > 0 end)
          |> Enum.sort_by(fn {category, _} -> category_sort_order(category) end)
          |> Enum.map_join("\n\n", fn {category, packages} ->
            package_list =
              packages
              |> Enum.sort_by(fn {name, _version, _is_dev} -> name end)
              |> Enum.map_join("\n", fn {name, version, is_dev} ->
                dev_badge = if is_dev, do: " `dev`", else: ""
                "  - `#{name}` #{version}#{dev_badge}"
              end)

            "### #{category}\n#{package_list}"
          end)

        """
        ## Dependencies

        #{sections}
        """
      end
    else
      ""
    end
  end

  defp categorize_dependencies(deps, dev_deps) do
    all_deps =
      Enum.map(deps, fn {name, version} -> {name, version, false} end) ++
        Enum.map(dev_deps, fn {name, version} -> {name, version, true} end)

    categories = %{
      "🚀 Framework" => [],
      "🎨 UI Components" => [],
      "💅 Styling" => [],
      "🗄️ Database & ORM" => [],
      "🔐 Authentication" => [],
      "💳 Payments" => [],
      "📊 State Management" => [],
      "✅ Validation" => [],
      "🛠️ Utilities" => [],
      "🎯 Icons" => [],
      "📦 Build Tools" => [],
      "📝 Type Definitions" => [],
      "🧪 Testing" => [],
      "🔧 Other" => []
    }

    Enum.reduce(all_deps, categories, fn {name, version, is_dev}, acc ->
      category = categorize_package(name)
      Map.update!(acc, category, fn packages -> packages ++ [{name, version, is_dev}] end)
    end)
  end

  defp categorize_package(name) do
    cond do
      name in ~w(react react-dom next vue nuxt svelte @angular/core angular express fastify koa hono nestjs) ->
        "🚀 Framework"

      String.starts_with?(name, "@angular/") ->
        "🚀 Framework"

      name in ~w(radix-ui @radix-ui @headlessui/react @headlessui/vue @chakra-ui/react @mantine/core @mui/material antd) or
        String.starts_with?(name, "@radix-ui/") or
        String.starts_with?(name, "@chakra-ui/") or
        String.starts_with?(name, "@mantine/") or
          String.starts_with?(name, "@mui/") ->
        "🎨 UI Components"

      name in ~w(tailwindcss @tailwindcss/postcss postcss autoprefixer styled-components emotion @emotion/react @emotion/styled sass less class-variance-authority clsx tailwind-merge tw-animate-css) ->
        "💅 Styling"

      name in ~w(prisma @prisma/client drizzle-orm drizzle-kit typeorm sequelize mongoose pg postgres mysql mysql2 better-sqlite3 @planetscale/database @neondatabase/serverless @libsql/client) ->
        "🗄️ Database & ORM"

      name in ~w(next-auth @auth/core lucia lucia-auth passport bcrypt bcryptjs argon2 jose jsonwebtoken @clerk/nextjs) or
          String.starts_with?(name, "passport-") ->
        "🔐 Authentication"

      name in ~w(stripe @stripe/stripe-js @paypal/react-paypal-js lemon-squeezy paddle) ->
        "💳 Payments"

      name in ~w(redux @reduxjs/toolkit zustand jotai recoil mobx valtio swr @tanstack/react-query react-query) ->
        "📊 State Management"

      name in ~w(zod yup joi superstruct valibot @hookform/resolvers react-hook-form) ->
        "✅ Validation"

      name in ~w(lodash underscore ramda date-fns dayjs moment luxon uuid nanoid dotenv server-only) ->
        "🛠️ Utilities"

      name in ~w(lucide-react @heroicons/react react-icons @tabler/icons-react @phosphor-icons/react) ->
        "🎯 Icons"

      name in ~w(vite webpack esbuild rollup parcel turbo @vitejs/plugin-react swc @swc/core babel @babel/core) or
          String.starts_with?(name, "@babel/") ->
        "📦 Build Tools"

      String.starts_with?(name, "@types/") or name == "typescript" ->
        "📝 Type Definitions"

      name in ~w(jest vitest @testing-library/react @testing-library/jest-dom cypress playwright msw @playwright/test) or
          String.starts_with?(name, "@testing-library/") ->
        "🧪 Testing"

      true ->
        "🔧 Other"
    end
  end

  defp category_sort_order(category) do
    order = %{
      "🚀 Framework" => 1,
      "🎨 UI Components" => 2,
      "💅 Styling" => 3,
      "🗄️ Database & ORM" => 4,
      "🔐 Authentication" => 5,
      "💳 Payments" => 6,
      "📊 State Management" => 7,
      "✅ Validation" => 8,
      "🛠️ Utilities" => 9,
      "🎯 Icons" => 10,
      "📦 Build Tools" => 11,
      "📝 Type Definitions" => 12,
      "🧪 Testing" => 13,
      "🔧 Other" => 99
    }

    Map.get(order, category, 50)
  end

  defp build_requirements_section(requirements) do
    if map_size(requirements) == 0 do
      ""
    else
      items =
        requirements
        |> Enum.map(fn {key, value} ->
          case key do
            :node ->
              "- **Node.js**: #{value[:version]}"

            :elixir ->
              "- **Elixir**: #{value[:version]}"

            :ruby ->
              "- **Ruby**: #{value[:version]}"

            :python ->
              "- **Python**: #{value[:version]}"

            :go ->
              "- **Go**: #{value[:version]}"

            :docker ->
              compose = if value[:has_compose], do: " (with Docker Compose)", else: ""
              "- **Docker**: Required#{compose}"

            :database ->
              deps = value[:detected_deps] || []
              "- **Database**: #{Enum.join(deps, ", ")}"

            :package_manager ->
              "- **Package Manager**: #{value}"

            :build_tool ->
              "- **Build Tool**: #{value}"

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      """
      ## Requirements

      #{items}
      """
    end
  end

  defp build_steps_section(steps) do
    sorted_steps = Enum.sort_by(steps, & &1[:order])

    step_items =
      sorted_steps
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {step, idx} ->
        url_note = if step[:url], do: "\n\n> Open #{step[:url]} in your browser.", else: ""
        terminal_note = if step[:separate_terminal], do: "\n\n> ⚠️ Run this in a separate terminal window.", else: ""

        manual_note =
          if step[:manual], do: "\n\n> This is a manual step - follow your provider's documentation.", else: ""

        """
        ### #{idx}. #{step[:title]}

        #{step[:description]}

        ```bash
        #{step[:command]}
        ```#{url_note}#{terminal_note}#{manual_note}
        """
      end)

    """
    ## Setup Steps

    #{step_items}
    """
  end

  defp build_test_credentials_section(tech_stack) do
    if tech_stack[:payments] && tech_stack[:payments][:name] == "Stripe" do
      """
      ## Test Credentials

      For testing Stripe payments in development:

      | Field | Value |
      |-------|-------|
      | Card Number | `4242 4242 4242 4242` |
      | Expiration | Any future date |
      | CVC | Any 3 digits |

      """
    else
      ""
    end
  end

  defp build_commands_section(commands) do
    if commands == [] do
      ""
    else
      items =
        Enum.map_join(commands, "\n", fn cmd ->
          "| `#{cmd[:command]}` | #{cmd[:description]} |"
        end)

      """
      ## Common Commands

      | Command | Description |
      |---------|-------------|
      #{items}
      """
    end
  end

  defp build_notes_section(notes) do
    if notes == [] do
      ""
    else
      items =
        Enum.map_join(notes, "\n>\n", fn note ->
          icon =
            case note[:type] do
              :warning -> "⚠️"
              :info -> "ℹ️"
              :tip -> "💡"
              _ -> "📝"
            end

          "> #{icon} **#{note[:title]}**: #{note[:content]}"
        end)

      """
      ## Notes

      #{items}
      """
    end
  end

  defp build_production_section(tech_stack) do
    if tech_stack[:deployment] || tech_stack[:payments] do
      content = []

      content =
        if tech_stack[:payments] && tech_stack[:payments][:name] == "Stripe" do
          content ++
            [
              """
              ### Stripe Webhook Setup

              1. Go to the [Stripe Dashboard](https://dashboard.stripe.com/webhooks) and create a new webhook
              2. Set the endpoint URL to `https://yourdomain.com/api/stripe/webhook`
              3. Select events: `checkout.session.completed`, `customer.subscription.updated`, etc.
              4. Copy the webhook signing secret to your production environment
              """
            ]
        else
          content
        end

      content =
        if tech_stack[:deployment] do
          content ++
            [
              """
              ### Deploy to #{tech_stack[:deployment][:platform]}

              1. Push your code to a Git repository
              2. Connect your repository to #{tech_stack[:deployment][:platform]}
              3. Configure environment variables in your dashboard
              4. Deploy!
              """
            ]
        else
          content
        end

      if length(content) > 0 do
        """
        ## Going to Production

        #{Enum.join(content, "\n")}
        """
      else
        ""
      end
    else
      ""
    end
  end

  defp build_footer do
    """
    ---

    *Generated by SuchConfig Workflow Wizard*
    """
  end
end
