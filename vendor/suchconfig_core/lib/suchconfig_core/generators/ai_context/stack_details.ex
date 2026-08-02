defmodule SuchConfigCore.Generators.AIContext.StackDetails do
  @moduledoc """
  Generates comprehensive stack detection details for projects.

  This module analyzes project data and generates a detailed markdown report
  covering all detected technologies across multiple categories:

  - Frontend Technologies
  - Backend Technologies
  - Databases & Data Storage
  - DevOps & Deployment
  - Development Practices
  - Mobile Development
  - Emerging Technologies
  """

  alias SuchConfigCore.Generators.AIContext.Helpers

  @frontend_frameworks %{
    "react" => %{name: "React", category: "UI Library", docs: "https://react.dev"},
    "next" => %{name: "Next.js", category: "React Framework", docs: "https://nextjs.org/docs"},
    "vue" => %{name: "Vue.js", category: "UI Framework", docs: "https://vuejs.org"},
    "nuxt" => %{name: "Nuxt", category: "Vue Framework", docs: "https://nuxt.com/docs"},
    "angular" => %{name: "Angular", category: "Full Framework", docs: "https://angular.io/docs"},
    "svelte" => %{name: "Svelte", category: "Compiler", docs: "https://svelte.dev/docs"},
    "solid" => %{name: "SolidJS", category: "Reactive Library", docs: "https://solidjs.com"},
    "astro" => %{name: "Astro", category: "Static Site", docs: "https://docs.astro.build"},
    "remix" => %{name: "Remix", category: "Full Stack", docs: "https://remix.run/docs"},
    "gatsby" => %{name: "Gatsby", category: "Static Site", docs: "https://www.gatsbyjs.com/docs"},
    "vite" => %{name: "Vite", category: "Build Tool", docs: "https://vitejs.dev"},
    "webpack" => %{name: "Webpack", category: "Bundler", docs: "https://webpack.js.org"},
    "tailwindcss" => %{name: "Tailwind CSS", category: "CSS Framework", docs: "https://tailwindcss.com/docs"},
    "styled-components" => %{name: "Styled Components", category: "CSS-in-JS", docs: "https://styled-components.com"},
    "emotion" => %{name: "Emotion", category: "CSS-in-JS", docs: "https://emotion.sh/docs"},
    "sass" => %{name: "Sass", category: "CSS Preprocessor", docs: "https://sass-lang.com/documentation"},
    "less" => %{name: "Less", category: "CSS Preprocessor", docs: "https://lesscss.org"}
  }

  @backend_frameworks %{
    "fastapi" => %{name: "FastAPI", language: "Python", docs: "https://fastapi.tiangolo.com"},
    "django" => %{name: "Django", language: "Python", docs: "https://docs.djangoproject.com"},
    "flask" => %{name: "Flask", language: "Python", docs: "https://flask.palletsprojects.com"},
    "express" => %{name: "Express", language: "Node.js", docs: "https://expressjs.com"},
    "nestjs" => %{name: "NestJS", language: "Node.js", docs: "https://docs.nestjs.com"},
    "hono" => %{name: "Hono", language: "Node.js", docs: "https://hono.dev"},
    "rails" => %{name: "Ruby on Rails", language: "Ruby", docs: "https://guides.rubyonrails.org"},
    "sinatra" => %{name: "Sinatra", language: "Ruby", docs: "https://sinatrarb.com/documentation.html"},
    "phoenix" => %{name: "Phoenix", language: "Elixir", docs: "https://hexdocs.pm/phoenix"},
    "gin" => %{name: "Gin", language: "Go", docs: "https://gin-gonic.com/docs"},
    "echo" => %{name: "Echo", language: "Go", docs: "https://echo.labstack.com"},
    "chi" => %{name: "Chi", language: "Go", docs: "https://go-chi.io"},
    "fiber" => %{name: "Fiber", language: "Go", docs: "https://docs.gofiber.io"},
    "huma" => %{name: "Huma", language: "Go", docs: "https://huma.rocks"},
    "actix" => %{name: "Actix Web", language: "Rust", docs: "https://actix.rs/docs"},
    "axum" => %{name: "Axum", language: "Rust", docs: "https://docs.rs/axum"},
    "spring" => %{name: "Spring Boot", language: "Java", docs: "https://spring.io/projects/spring-boot"},
    "dotnet" => %{name: ".NET Core", language: "C#", docs: "https://docs.microsoft.com/dotnet"}
  }

  @databases %{
    "pg" => %{name: "PostgreSQL", type: "Relational", docs: "https://www.postgresql.org/docs"},
    "postgres" => %{name: "PostgreSQL", type: "Relational", docs: "https://www.postgresql.org/docs"},
    "mysql" => %{name: "MySQL", type: "Relational", docs: "https://dev.mysql.com/doc"},
    "sqlite" => %{name: "SQLite", type: "Relational", docs: "https://sqlite.org/docs.html"},
    "mongodb" => %{name: "MongoDB", type: "Document", docs: "https://www.mongodb.com/docs"},
    "redis" => %{name: "Redis", type: "Key-Value", docs: "https://redis.io/docs"},
    "prisma" => %{name: "Prisma", type: "ORM", docs: "https://www.prisma.io/docs"},
    "drizzle" => %{name: "Drizzle", type: "ORM", docs: "https://orm.drizzle.team"},
    "typeorm" => %{name: "TypeORM", type: "ORM", docs: "https://typeorm.io"},
    "sequelize" => %{name: "Sequelize", type: "ORM", docs: "https://sequelize.org"},
    "sqlalchemy" => %{name: "SQLAlchemy", type: "ORM", docs: "https://docs.sqlalchemy.org"},
    "ecto" => %{name: "Ecto", type: "ORM", docs: "https://hexdocs.pm/ecto"},
    "gorm" => %{name: "GORM", type: "ORM", docs: "https://gorm.io/docs"},
    "elasticsearch" => %{name: "Elasticsearch", type: "Search", docs: "https://www.elastic.co/guide"},
    "dynamodb" => %{name: "DynamoDB", type: "NoSQL", docs: "https://docs.aws.amazon.com/dynamodb"}
  }

  @devops_tools %{
    "docker" => %{name: "Docker", category: "Containerization", docs: "https://docs.docker.com"},
    "kubernetes" => %{name: "Kubernetes", category: "Orchestration", docs: "https://kubernetes.io/docs"},
    "terraform" => %{name: "Terraform", category: "IaC", docs: "https://developer.hashicorp.com/terraform/docs"},
    "ansible" => %{name: "Ansible", category: "Configuration", docs: "https://docs.ansible.com"},
    "github-actions" => %{name: "GitHub Actions", category: "CI/CD", docs: "https://docs.github.com/actions"},
    "gitlab-ci" => %{name: "GitLab CI", category: "CI/CD", docs: "https://docs.gitlab.com/ee/ci"},
    "circleci" => %{name: "CircleCI", category: "CI/CD", docs: "https://circleci.com/docs"},
    "jenkins" => %{name: "Jenkins", category: "CI/CD", docs: "https://www.jenkins.io/doc"},
    "aws" => %{name: "AWS", category: "Cloud", docs: "https://docs.aws.amazon.com"},
    "gcp" => %{name: "Google Cloud", category: "Cloud", docs: "https://cloud.google.com/docs"},
    "azure" => %{name: "Azure", category: "Cloud", docs: "https://docs.microsoft.com/azure"},
    "vercel" => %{name: "Vercel", category: "Platform", docs: "https://vercel.com/docs"},
    "netlify" => %{name: "Netlify", category: "Platform", docs: "https://docs.netlify.com"},
    "fly" => %{name: "Fly.io", category: "Platform", docs: "https://fly.io/docs"},
    "railway" => %{name: "Railway", category: "Platform", docs: "https://docs.railway.app"},
    "render" => %{name: "Render", category: "Platform", docs: "https://render.com/docs"},
    "nginx" => %{name: "Nginx", category: "Web Server", docs: "https://nginx.org/en/docs"},
    "caddy" => %{name: "Caddy", category: "Web Server", docs: "https://caddyserver.com/docs"}
  }

  @testing_tools %{
    "jest" => %{name: "Jest", language: "JavaScript", docs: "https://jestjs.io/docs"},
    "vitest" => %{name: "Vitest", language: "JavaScript", docs: "https://vitest.dev"},
    "mocha" => %{name: "Mocha", language: "JavaScript", docs: "https://mochajs.org"},
    "cypress" => %{name: "Cypress", language: "JavaScript", docs: "https://docs.cypress.io"},
    "playwright" => %{name: "Playwright", language: "JavaScript", docs: "https://playwright.dev/docs"},
    "pytest" => %{name: "pytest", language: "Python", docs: "https://docs.pytest.org"},
    "unittest" => %{name: "unittest", language: "Python", docs: "https://docs.python.org/3/library/unittest.html"},
    "rspec" => %{name: "RSpec", language: "Ruby", docs: "https://rspec.info/documentation"},
    "minitest" => %{name: "Minitest", language: "Ruby", docs: "https://docs.seattlerb.org/minitest"},
    "exunit" => %{name: "ExUnit", language: "Elixir", docs: "https://hexdocs.pm/ex_unit"},
    "go-test" => %{name: "Go Test", language: "Go", docs: "https://pkg.go.dev/testing"}
  }

  @linting_tools %{
    "eslint" => %{name: "ESLint", language: "JavaScript", docs: "https://eslint.org/docs"},
    "prettier" => %{name: "Prettier", language: "JavaScript", docs: "https://prettier.io/docs"},
    "biome" => %{name: "Biome", language: "JavaScript", docs: "https://biomejs.dev/guides"},
    "ruff" => %{name: "Ruff", language: "Python", docs: "https://docs.astral.sh/ruff"},
    "black" => %{name: "Black", language: "Python", docs: "https://black.readthedocs.io"},
    "mypy" => %{name: "mypy", language: "Python", docs: "https://mypy.readthedocs.io"},
    "isort" => %{name: "isort", language: "Python", docs: "https://pycqa.github.io/isort"},
    "flake8" => %{name: "Flake8", language: "Python", docs: "https://flake8.pycqa.org"},
    "pylint" => %{name: "Pylint", language: "Python", docs: "https://pylint.readthedocs.io"},
    "rubocop" => %{name: "RuboCop", language: "Ruby", docs: "https://docs.rubocop.org"},
    "standard" => %{name: "Standard", language: "Ruby", docs: "https://github.com/standardrb/standard"},
    "credo" => %{name: "Credo", language: "Elixir", docs: "https://hexdocs.pm/credo"},
    "dialyzer" => %{name: "Dialyzer", language: "Elixir", docs: "https://www.erlang.org/doc/man/dialyzer"},
    "golangci-lint" => %{name: "golangci-lint", language: "Go", docs: "https://golangci-lint.run"}
  }

  @python_tools %{
    "pydantic" => %{name: "Pydantic", category: "Data Validation", docs: "https://docs.pydantic.dev"},
    "starlette" => %{name: "Starlette", category: "ASGI Framework", docs: "https://www.starlette.io"},
    "uvicorn" => %{name: "Uvicorn", category: "ASGI Server", docs: "https://www.uvicorn.org"},
    "gunicorn" => %{name: "Gunicorn", category: "WSGI Server", docs: "https://gunicorn.org"},
    "httpx" => %{name: "HTTPX", category: "HTTP Client", docs: "https://www.python-httpx.org"},
    "aiohttp" => %{name: "aiohttp", category: "Async HTTP", docs: "https://docs.aiohttp.org"},
    "celery" => %{name: "Celery", category: "Task Queue", docs: "https://docs.celeryq.dev"},
    "alembic" => %{name: "Alembic", category: "Migrations", docs: "https://alembic.sqlalchemy.org"},
    "poetry" => %{name: "Poetry", category: "Package Manager", docs: "https://python-poetry.org/docs"},
    "pdm" => %{name: "PDM", category: "Package Manager", docs: "https://pdm-project.org"},
    "pip-tools" => %{name: "pip-tools", category: "Dependency Management", docs: "https://pip-tools.readthedocs.io"},
    "pre-commit" => %{name: "pre-commit", category: "Git Hooks", docs: "https://pre-commit.com"},
    "tox" => %{name: "tox", category: "Test Runner", docs: "https://tox.wiki"},
    "nox" => %{name: "Nox", category: "Test Runner", docs: "https://nox.thea.codes"}
  }

  @mobile_tools %{
    "react-native" => %{name: "React Native", platform: "Cross-platform", docs: "https://reactnative.dev/docs"},
    "expo" => %{name: "Expo", platform: "React Native", docs: "https://docs.expo.dev"},
    "flutter" => %{name: "Flutter", platform: "Cross-platform", docs: "https://docs.flutter.dev"},
    "ionic" => %{name: "Ionic", platform: "Hybrid", docs: "https://ionicframework.com/docs"},
    "capacitor" => %{name: "Capacitor", platform: "Hybrid", docs: "https://capacitorjs.com/docs"},
    "tauri" => %{name: "Tauri", platform: "Desktop", docs: "https://tauri.app/v1/guides"},
    "electron" => %{name: "Electron", platform: "Desktop", docs: "https://www.electronjs.org/docs"}
  }

  @emerging_tech %{
    "openai" => %{name: "OpenAI API", category: "AI/ML", docs: "https://platform.openai.com/docs"},
    "langchain" => %{name: "LangChain", category: "AI/ML", docs: "https://docs.langchain.com"},
    "anthropic" => %{name: "Anthropic API", category: "AI/ML", docs: "https://docs.anthropic.com"},
    "tensorflow" => %{name: "TensorFlow", category: "ML Framework", docs: "https://www.tensorflow.org/api_docs"},
    "pytorch" => %{name: "PyTorch", category: "ML Framework", docs: "https://pytorch.org/docs"},
    "huggingface" => %{name: "Hugging Face", category: "ML Hub", docs: "https://huggingface.co/docs"},
    "wasm" => %{name: "WebAssembly", category: "Runtime", docs: "https://webassembly.org"},
    "graphql" => %{name: "GraphQL", category: "API", docs: "https://graphql.org/learn"},
    "trpc" => %{name: "tRPC", category: "API", docs: "https://trpc.io/docs"},
    "grpc" => %{name: "gRPC", category: "API", docs: "https://grpc.io/docs"}
  }

  def generate(project_data) do
    sections = [
      build_header(project_data),
      build_overview(project_data),
      build_frontend_section(project_data),
      build_backend_section(project_data),
      build_python_ecosystem_section(project_data),
      build_database_section(project_data),
      build_devops_section(project_data),
      build_development_practices(project_data),
      build_mobile_section(project_data),
      build_emerging_tech_section(project_data),
      build_environment_setup(project_data),
      build_ide_extensions(project_data),
      build_getting_started(project_data)
    ]

    content =
      sections
      |> Enum.reject(fn s -> is_nil(s) or s == "" end)
      |> Enum.join("\n\n")

    {:ok, content}
  end

  defp build_header(project_data) do
    project_name = project_data[:project_name] || "Project"

    """
    # Stack Detection: #{project_name}

    > Comprehensive technology stack analysis generated by SuchConfig
    """
  end

  defp build_overview(project_data) do
    project_type = project_data[:project_type]
    framework = project_data[:framework]

    type_label = format_project_type(project_type)
    framework_label = if framework, do: " using **#{Helpers.format_framework(framework)}**", else: ""

    """
    ## Overview

    This is a **#{type_label}** project#{framework_label}.
    """
  end

  defp build_frontend_section(project_data) do
    files = project_data[:files] || []
    dependencies = project_data[:dependencies] || []

    detected = detect_frontend_stack(files, dependencies)

    if length(detected) > 0 do
      items =
        Enum.map(detected, fn {_key, info} ->
          "| #{info.name} | #{info[:category] || "Library"} | [Docs](#{info.docs}) |"
        end)

      """
      ## Frontend Technologies

      | Technology | Category | Documentation |
      |------------|----------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_backend_section(project_data) do
    project_type = project_data[:project_type]
    framework = project_data[:framework]
    files = project_data[:files] || []
    dependencies = project_data[:dependencies] || []

    detected = detect_backend_stack(project_type, framework, files, dependencies)

    if length(detected) > 0 do
      items =
        Enum.map(detected, fn {_key, info} ->
          "| #{info.name} | #{info[:language] || "N/A"} | [Docs](#{info.docs}) |"
        end)

      """
      ## Backend Technologies

      | Technology | Language | Documentation |
      |------------|----------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_python_ecosystem_section(project_data) do
    project_type = project_data[:project_type]

    if project_type == :python do
      files = project_data[:files] || []
      dependencies = project_data[:dependencies] || []
      code_quality = project_data[:code_quality] || %{}

      detected = detect_python_tools(files, dependencies, code_quality)

      if length(detected) > 0 do
        items =
          Enum.map(detected, fn {_key, info} ->
            "| #{info.name} | #{info.category} | [Docs](#{info.docs}) |"
          end)

        """
        ## Python Ecosystem

        | Tool | Category | Documentation |
        |------|----------|---------------|
        #{Enum.join(items, "\n")}
        """
      else
        nil
      end
    else
      nil
    end
  end

  defp build_database_section(project_data) do
    files = project_data[:files] || []
    dependencies = project_data[:dependencies] || []

    detected = detect_databases(files, dependencies)

    if length(detected) > 0 do
      items =
        Enum.map(detected, fn {_key, info} ->
          "| #{info.name} | #{info.type} | [Docs](#{info.docs}) |"
        end)

      """
      ## Databases & Data Storage

      | Technology | Type | Documentation |
      |------------|------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_devops_section(project_data) do
    files = project_data[:files] || []

    detected = detect_devops_tools(files)

    if length(detected) > 0 do
      items =
        Enum.map(detected, fn {_key, info} ->
          "| #{info.name} | #{info.category} | [Docs](#{info.docs}) |"
        end)

      """
      ## DevOps & Deployment

      | Tool | Category | Documentation |
      |------|----------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_development_practices(project_data) do
    code_quality = project_data[:code_quality] || %{}
    testing_config = project_data[:testing_config] || %{}

    linting_items = detect_linting_tools(code_quality)
    testing_items = detect_testing_tools(testing_config)

    all_items = linting_items ++ testing_items

    if length(all_items) > 0 do
      items =
        Enum.map(all_items, fn {_key, info} ->
          "| #{info.name} | #{info[:language] || info[:category] || "N/A"} | [Docs](#{info.docs}) |"
        end)

      """
      ## Development Practices

      | Tool | Language/Category | Documentation |
      |------|-------------------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_mobile_section(project_data) do
    files = project_data[:files] || []
    dependencies = project_data[:dependencies] || []

    detected = detect_mobile_tools(files, dependencies)

    if length(detected) > 0 do
      items =
        Enum.map(detected, fn {_key, info} ->
          "| #{info.name} | #{info.platform} | [Docs](#{info.docs}) |"
        end)

      """
      ## Mobile & Desktop Development

      | Technology | Platform | Documentation |
      |------------|----------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_emerging_tech_section(project_data) do
    dependencies = project_data[:dependencies] || []

    detected = detect_emerging_tech(dependencies)

    if length(detected) > 0 do
      items =
        Enum.map(detected, fn {_key, info} ->
          "| #{info.name} | #{info.category} | [Docs](#{info.docs}) |"
        end)

      """
      ## Emerging Technologies

      | Technology | Category | Documentation |
      |------------|----------|---------------|
      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_environment_setup(project_data) do
    project_type = project_data[:project_type]
    node_version = project_data[:node_version]
    python_version = project_data[:python_version]
    ruby_version = project_data[:ruby_version]
    go_version = project_data[:go_version]
    elixir_version = project_data[:elixir_version]

    env_vars = project_data[:env_vars] || []

    version_items = []

    version_items = if node_version, do: version_items ++ ["- **Node.js**: #{node_version}"], else: version_items
    version_items = if python_version, do: version_items ++ ["- **Python**: #{python_version}"], else: version_items
    version_items = if ruby_version, do: version_items ++ ["- **Ruby**: #{ruby_version}"], else: version_items
    version_items = if go_version, do: version_items ++ ["- **Go**: #{go_version}"], else: version_items
    version_items = if elixir_version, do: version_items ++ ["- **Elixir**: #{elixir_version}"], else: version_items

    shell_setup =
      build_shell_setup(project_type, node_version, python_version, ruby_version, go_version, elixir_version)

    env_section =
      if length(env_vars) > 0 do
        vars =
          env_vars
          |> Enum.take(10)
          |> Enum.map_join("\n", fn var ->
            "- `#{var[:key]}`#{if var[:description], do: " - #{var[:description]}", else: ""}"
          end)

        """

        ### Environment Variables

        #{vars}
        """
      else
        ""
      end

    if length(version_items) > 0 or shell_setup != nil do
      """
      ## Environment Setup

      ### Required Versions

      #{Enum.join(version_items, "\n")}
      #{shell_setup || ""}#{env_section}
      """
    else
      nil
    end
  end

  defp build_shell_setup(_project_type, node_version, python_version, ruby_version, go_version, elixir_version) do
    items = []

    items =
      if node_version do
        items ++
          [
            """
            **Node.js (using nvm)**:
            ```bash
            nvm install #{node_version}
            nvm use #{node_version}
            ```
            """
          ]
      else
        items
      end

    items =
      if python_version do
        items ++
          [
            """
            **Python (using pyenv)**:
            ```bash
            pyenv install #{python_version}
            pyenv local #{python_version}
            ```
            """
          ]
      else
        items
      end

    items =
      if ruby_version do
        items ++
          [
            """
            **Ruby (using rbenv)**:
            ```bash
            rbenv install #{ruby_version}
            rbenv local #{ruby_version}
            ```
            """
          ]
      else
        items
      end

    items =
      if go_version do
        items ++
          [
            """
            **Go (using asdf)**:
            ```bash
            asdf install golang #{go_version}
            asdf local golang #{go_version}
            ```
            """
          ]
      else
        items
      end

    items =
      if elixir_version do
        items ++
          [
            """
            **Elixir (using asdf)**:
            ```bash
            asdf install elixir #{elixir_version}
            asdf local elixir #{elixir_version}
            ```
            """
          ]
      else
        items
      end

    if length(items) > 0 do
      """

      ### Shell Configuration

      #{Enum.join(items, "\n")}

      > 💡 **Tip**: Use [asdf](https://asdf-vm.com) for unified version management across all languages
      """
    else
      nil
    end
  end

  defp build_ide_extensions(project_data) do
    project_type = project_data[:project_type]
    framework = project_data[:framework]
    code_quality = project_data[:code_quality] || %{}

    extensions = build_extension_list(project_type, framework, code_quality)

    if length(extensions) > 0 do
      items = Enum.map(extensions, fn ext -> "- #{ext}" end)

      """
      ## Recommended IDE Extensions

      ### VS Code / Cursor

      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_extension_list(project_type, framework, code_quality) do
    base_extensions = ["GitLens", "Error Lens", "Todo Tree"]

    language_extensions =
      case project_type do
        :node -> ["ESLint", "Prettier", "JavaScript and TypeScript Nightly"]
        :python -> ["Python", "Pylance", "Python Debugger", "Ruff"]
        :ruby -> ["Ruby LSP", "Ruby Solargraph", "Ruby Test Explorer"]
        :go -> ["Go", "Go Test Explorer"]
        :elixir -> ["ElixirLS", "Phoenix Framework"]
        :rust -> ["rust-analyzer", "crates"]
        _ -> []
      end

    framework_extensions =
      case framework do
        f when f in ["next", "react"] -> ["ES7+ React/Redux/React-Native snippets", "Tailwind CSS IntelliSense"]
        f when f in ["vue", "nuxt"] -> ["Vue - Official", "Tailwind CSS IntelliSense"]
        f when f in ["rails"] -> ["Rails", "Ruby on Rails"]
        f when f in ["fastapi", "django", "flask"] -> ["Python Docstring Generator"]
        f when f in ["phoenix"] -> ["Phoenix Framework"]
        _ -> []
      end

    linting_extensions =
      cond do
        code_quality[:eslint] != nil -> ["ESLint"]
        code_quality[:biome] == true -> ["Biome"]
        code_quality[:has_rubocop] == true -> ["ruby-rubocop"]
        true -> []
      end

    (base_extensions ++ language_extensions ++ framework_extensions ++ linting_extensions)
    |> Enum.uniq()
  end

  defp build_getting_started(project_data) do
    project_type = project_data[:project_type]
    framework = project_data[:framework]
    files = project_data[:files] || []

    has_docker = Helpers.has_file?(files, :dockerfile) or Helpers.has_file?(files, :docker_compose)
    has_makefile = Helpers.has_file?(files, :makefile)

    steps = []

    steps = steps ++ ["1. Clone the repository and install dependencies"]

    install_cmd =
      case project_type do
        :node -> "npm install"
        :python -> "pip install -r requirements.txt"
        :ruby -> "bundle install"
        :go -> "go mod tidy"
        :elixir -> "mix deps.get"
        _ -> nil
      end

    steps =
      if install_cmd do
        steps ++ ["2. Run `#{install_cmd}` to install dependencies"]
      else
        steps
      end

    steps =
      if has_docker do
        steps ++ ["#{length(steps) + 1}. Use `docker compose up` for containerized development"]
      else
        steps
      end

    steps =
      if has_makefile do
        steps ++ ["#{length(steps) + 1}. Check `Makefile` for available commands (`make help` if available)"]
      else
        steps
      end

    run_cmd =
      case {project_type, framework} do
        {:node, "next"} -> "npm run dev"
        {:node, _} -> "npm start"
        {:python, "fastapi"} -> "uvicorn main:app --reload"
        {:python, "django"} -> "python manage.py runserver"
        {:python, "flask"} -> "flask run"
        {:ruby, "rails"} -> "rails server"
        {:go, _} -> "go run . or air (if using hot reload)"
        {:elixir, "phoenix"} -> "mix phx.server"
        _ -> nil
      end

    steps =
      if run_cmd do
        steps ++ ["#{length(steps) + 1}. Start the development server with `#{run_cmd}`"]
      else
        steps
      end

    """
    ## Getting Started

    #{Enum.join(steps, "\n")}

    > 📖 Check `README.md` and `CONTRIBUTING.md` for project-specific setup instructions
    """
  end

  defp detect_frontend_stack(_files, dependencies) do
    dep_names = Enum.map(dependencies, fn d -> String.downcase(d[:name] || "") end)

    @frontend_frameworks
    |> Enum.filter(fn {key, _info} ->
      Enum.any?(dep_names, &String.contains?(&1, key))
    end)
  end

  defp detect_backend_stack(project_type, framework, _files, dependencies) do
    dep_names = Enum.map(dependencies, fn d -> String.downcase(d[:name] || "") end)

    framework_match =
      if framework do
        framework_key = String.downcase(framework)

        Enum.filter(@backend_frameworks, fn {key, _info} ->
          String.contains?(framework_key, key) or key == framework_key
        end)
      else
        []
      end

    dep_matches =
      @backend_frameworks
      |> Enum.filter(fn {key, _info} ->
        Enum.any?(dep_names, &String.contains?(&1, key))
      end)

    type_match =
      case project_type do
        :elixir -> [{"phoenix", @backend_frameworks["phoenix"]}]
        _ -> []
      end
      |> Enum.filter(fn {_k, v} -> v != nil end)

    (framework_match ++ dep_matches ++ type_match)
    |> Enum.uniq_by(fn {k, _v} -> k end)
  end

  defp detect_databases(_files, dependencies) do
    dep_names = Enum.map(dependencies, fn d -> String.downcase(d[:name] || "") end)

    @databases
    |> Enum.filter(fn {key, _info} ->
      Enum.any?(dep_names, &String.contains?(&1, key))
    end)
  end

  defp detect_devops_tools(files) do
    detected = []

    detected =
      if Helpers.has_file?(files, :dockerfile), do: detected ++ [{"docker", @devops_tools["docker"]}], else: detected

    detected =
      if Helpers.has_file?(files, :docker_compose),
        do: detected ++ [{"docker", @devops_tools["docker"]}],
        else: detected

    has_github_actions =
      Enum.any?(files, fn f ->
        path = f[:path] || f[:name] || ""
        String.contains?(path, ".github/workflows")
      end)

    detected =
      if has_github_actions, do: detected ++ [{"github-actions", @devops_tools["github-actions"]}], else: detected

    has_gitlab_ci =
      Enum.any?(files, fn f ->
        name = f[:name] || ""
        name == ".gitlab-ci.yml"
      end)

    detected = if has_gitlab_ci, do: detected ++ [{"gitlab-ci", @devops_tools["gitlab-ci"]}], else: detected

    fly_config = Helpers.find_file(files, :fly_config)
    detected = if fly_config, do: detected ++ [{"fly", @devops_tools["fly"]}], else: detected

    detected
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.uniq_by(fn {k, _v} -> k end)
  end

  defp detect_linting_tools(code_quality) do
    detected = []

    detected = if code_quality[:eslint] != nil, do: detected ++ [{"eslint", @linting_tools["eslint"]}], else: detected

    detected =
      if code_quality[:prettier] == true, do: detected ++ [{"prettier", @linting_tools["prettier"]}], else: detected

    detected = if code_quality[:biome] == true, do: detected ++ [{"biome", @linting_tools["biome"]}], else: detected

    detected =
      if code_quality[:has_rubocop] == true, do: detected ++ [{"rubocop", @linting_tools["rubocop"]}], else: detected

    detected = if code_quality[:ruff] == true, do: detected ++ [{"ruff", @linting_tools["ruff"]}], else: detected
    detected = if code_quality[:black] == true, do: detected ++ [{"black", @linting_tools["black"]}], else: detected
    detected = if code_quality[:mypy] == true, do: detected ++ [{"mypy", @linting_tools["mypy"]}], else: detected
    detected = if code_quality[:isort] == true, do: detected ++ [{"isort", @linting_tools["isort"]}], else: detected
    detected = if code_quality[:flake8] == true, do: detected ++ [{"flake8", @linting_tools["flake8"]}], else: detected
    detected = if code_quality[:pylint] == true, do: detected ++ [{"pylint", @linting_tools["pylint"]}], else: detected

    detected =
      if code_quality[:golangci_lint] == true,
        do: detected ++ [{"golangci-lint", @linting_tools["golangci-lint"]}],
        else: detected

    detected = if code_quality[:credo] == true, do: detected ++ [{"credo", @linting_tools["credo"]}], else: detected

    detected
    |> Enum.filter(fn {_k, v} -> v != nil end)
  end

  defp detect_testing_tools(testing_config) do
    frameworks = testing_config[:frameworks] || []

    frameworks
    |> Enum.map(fn f ->
      key = String.downcase(to_string(f))
      {key, @testing_tools[key]}
    end)
    |> Enum.filter(fn {_k, v} -> v != nil end)
  end

  defp detect_mobile_tools(_files, dependencies) do
    dep_names = Enum.map(dependencies, fn d -> String.downcase(d[:name] || "") end)

    @mobile_tools
    |> Enum.filter(fn {key, _info} ->
      Enum.any?(dep_names, &String.contains?(&1, key))
    end)
  end

  defp detect_emerging_tech(dependencies) do
    dep_names = Enum.map(dependencies, fn d -> String.downcase(d[:name] || "") end)

    @emerging_tech
    |> Enum.filter(fn {key, _info} ->
      Enum.any?(dep_names, &String.contains?(&1, key))
    end)
  end

  defp detect_python_tools(files, dependencies, code_quality) do
    dep_names = Enum.map(dependencies, fn d -> String.downcase(d[:name] || "") end)

    detected =
      @python_tools
      |> Enum.filter(fn {key, _info} ->
        Enum.any?(dep_names, &String.contains?(&1, key))
      end)

    pyproject = Helpers.find_file(files, :pyproject)

    detected =
      if pyproject do
        build_backend = pyproject[:build_backend]

        detected =
          cond do
            build_backend && String.contains?(build_backend, "pdm") ->
              detected ++ [{"pdm", @python_tools["pdm"]}]

            build_backend && String.contains?(build_backend, "poetry") ->
              detected ++ [{"poetry", @python_tools["poetry"]}]

            build_backend && String.contains?(build_backend, "hatch") ->
              detected ++ [{"hatch", %{name: "Hatch", category: "Build Backend", docs: "https://hatch.pypa.io"}}]

            build_backend && String.contains?(build_backend, "setuptools") ->
              detected ++
                [{"setuptools", %{name: "Setuptools", category: "Build Backend", docs: "https://setuptools.pypa.io"}}]

            true ->
              detected
          end

        detected
      else
        detected
      end

    detected =
      if code_quality[:ruff] == true do
        detected ++ [{"ruff", %{name: "Ruff", category: "Linter & Formatter", docs: "https://docs.astral.sh/ruff"}}]
      else
        detected
      end

    detected =
      if code_quality[:mypy] == true do
        detected ++ [{"mypy", %{name: "mypy", category: "Type Checker", docs: "https://mypy.readthedocs.io"}}]
      else
        detected
      end

    detected =
      if code_quality[:black] == true do
        detected ++ [{"black", %{name: "Black", category: "Formatter", docs: "https://black.readthedocs.io"}}]
      else
        detected
      end

    detected =
      if code_quality[:isort] == true do
        detected ++ [{"isort", %{name: "isort", category: "Import Sorter", docs: "https://pycqa.github.io/isort"}}]
      else
        detected
      end

    pre_commit = Helpers.find_file(files, :pre_commit_config)

    detected =
      if pre_commit do
        detected ++ [{"pre-commit", @python_tools["pre-commit"]}]
      else
        detected
      end

    tox_file = Enum.find(files, fn f -> f[:name] == "tox.ini" end)

    detected =
      if tox_file do
        detected ++ [{"tox", @python_tools["tox"]}]
      else
        detected
      end

    nox_file = Enum.find(files, fn f -> f[:name] == "noxfile.py" end)

    detected =
      if nox_file do
        detected ++ [{"nox", @python_tools["nox"]}]
      else
        detected
      end

    detected
    |> Enum.filter(fn {_k, v} -> v != nil end)
    |> Enum.uniq_by(fn {k, _v} -> k end)
  end

  defp format_project_type(type) do
    case type do
      :node -> "Node.js/JavaScript"
      :python -> "Python"
      :ruby -> "Ruby"
      :mixed_ruby -> "Ruby (Mixed)"
      :go -> "Go"
      :elixir -> "Elixir"
      :rust -> "Rust"
      :mixed_elixir -> "Elixir (Mixed)"
      _ -> "Unknown"
    end
  end
end
