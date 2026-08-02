defmodule SuchConfigCore.Generators.AIContext.Python do
  @moduledoc """
  Python-specific AI context generation.

  Handles Python projects including:
  - FastAPI, Django, Flask, Starlette frameworks
  - pyproject.toml, setup.py, setup.cfg parsing
  - pytest, ruff, mypy, black, isort tooling
  - pre-commit hooks integration
  - tox and nox test runners
  """

  alias SuchConfigCore.Generators.AIContext.{Helpers, FrameworkPractices}

  @python_frameworks ["fastapi", "django", "flask", "starlette", "tornado", "aiohttp", "sanic", "falcon"]
  @async_tools ["uvicorn", "httpx", "aiofiles", "anyio", "asyncio", "gunicorn", "hypercorn"]
  @data_validation ["pydantic", "pydantic-settings", "typing-extensions", "attrs", "marshmallow"]
  @database_tools ["sqlalchemy", "alembic", "sqlmodel", "tortoise-orm", "databases", "asyncpg", "psycopg2"]
  @testing_tools ["pytest", "pytest-cov", "pytest-asyncio", "httpx", "coverage", "hypothesis"]

  def build_tech_stack(project_data) do
    files = project_data[:files] || []
    pyproject = Helpers.find_file(files, :pyproject)
    pre_commit = Helpers.find_file(files, :pre_commit_config)
    tox = Helpers.find_file(files, :tox_ini)
    noxfile = Helpers.find_file(files, :noxfile)
    license_file = Helpers.find_file(files, :license)

    items = []

    py_framework = detect_framework(pyproject, files)
    items = if py_framework, do: items ++ ["- **Framework**: #{py_framework}"], else: items

    items =
      if pyproject && pyproject[:python_version] do
        items ++ ["- **Python**: #{pyproject[:python_version]}"]
      else
        items
      end

    items =
      if pyproject && pyproject[:build_backend] do
        items ++ ["- **Build Tool**: #{format_build_tool(pyproject[:build_backend])}"]
      else
        items
      end

    linting = if pyproject, do: pyproject[:linting] || %{}, else: %{}
    linting_tools = build_linting_tools(linting, pre_commit)

    items =
      if length(linting_tools) > 0,
        do: items ++ ["- **Linting/Formatting**: #{Enum.join(linting_tools, ", ")}"],
        else: items

    testing = if pyproject, do: pyproject[:testing] || %{}, else: %{}
    has_pytest = testing[:has_pytest] || (tox && tox[:has_pytest]) || (noxfile && noxfile[:has_pytest])
    items = if has_pytest, do: items ++ ["- **Testing**: pytest"], else: items

    has_pre_commit = (pyproject && pyproject[:has_pre_commit]) || pre_commit != nil

    items =
      if has_pre_commit do
        hook_count = if pre_commit, do: pre_commit[:hook_count], else: nil
        hook_info = if hook_count && hook_count > 0, do: " (#{hook_count} hooks)", else: ""
        items ++ ["- **Git Hooks**: pre-commit#{hook_info}"]
      else
        items
      end

    items =
      cond do
        tox && noxfile -> items ++ ["- **Test Runner**: tox + nox"]
        tox -> items ++ ["- **Test Runner**: tox"]
        noxfile -> items ++ ["- **Test Runner**: nox"]
        true -> items
      end

    items =
      if license_file && license_file[:license_type] do
        items ++ ["- **License**: #{license_file[:license_type]}"]
      else
        items
      end

    items
  end

  def build_quick_start(project_data) do
    files = project_data[:files] || []
    pyproject = Helpers.find_file(files, :pyproject)
    contributing = Helpers.find_file(files, :contributing)

    steps = []

    steps =
      steps ++
        [
          "1. **Clone the repository**\n   ```bash\n   git clone <repository-url>\n   cd #{project_data[:project_name] || "project"}\n   ```"
        ]

    build_backend = if pyproject, do: pyproject[:build_backend], else: nil

    venv_step =
      "2. **Create virtual environment**\n   ```bash\n   python -m venv venv\n   source venv/bin/activate  # On Windows: .\\venv\\Scripts\\activate\n   ```"

    install_cmd =
      case build_backend do
        "hatch" -> "pip install -e \".[dev]\"\n   # Or use hatch: hatch env create"
        "poetry" -> "poetry install"
        "pdm" -> "pdm install"
        _ -> "pip install -e \".[dev]\""
      end

    install_step = "3. **Install dependencies**\n   ```bash\n   #{install_cmd}\n   ```"

    pre_commit = Helpers.find_file(files, :pre_commit_config)

    pre_commit_step =
      if pre_commit || (pyproject && pyproject[:has_pre_commit]) do
        "4. **Install pre-commit hooks**\n   ```bash\n   pre-commit install\n   ```"
      else
        nil
      end

    steps = (steps ++ [venv_step, install_step, pre_commit_step]) |> Enum.reject(&is_nil/1)

    py_framework = detect_framework(pyproject, files)

    cmd =
      case py_framework do
        "FastAPI" -> "uvicorn fastapi:app --reload"
        "Django" -> "python manage.py runserver"
        "Flask" -> "flask run --debug"
        _ -> "python -m pytest  # Run tests"
      end

    run_step = "#{length(steps) + 1}. **Run the project**\n   ```bash\n   #{cmd}\n   ```"
    steps = steps ++ [run_step]

    contributing_setup =
      if contributing && contributing[:setup_steps] && length(contributing[:setup_steps]) > 0 do
        "\n> 📖 See `CONTRIBUTING.md` for detailed setup instructions"
      else
        nil
      end

    if length(steps) > 1 do
      content = Enum.join(steps, "\n\n")

      """
      ## Quick Start

      #{content}#{contributing_setup || ""}
      """
    else
      nil
    end
  end

  def build_dependencies(project_data) do
    files = project_data[:files] || []
    pyproject = Helpers.find_file(files, :pyproject)
    req_files = Helpers.filter_files(files, :requirements_txt)

    deps = if pyproject, do: pyproject[:dependencies] || [], else: []

    req_deps =
      req_files
      |> Enum.filter(fn f -> f[:req_type] == :main end)
      |> Enum.flat_map(fn f -> f[:dependencies] || [] end)

    all_deps = (deps ++ req_deps) |> Enum.uniq_by(fn d -> d[:name] end) |> Enum.take(20)

    if length(all_deps) > 0 do
      core_deps = categorize_deps(all_deps)
      sections = []

      sections =
        if length(core_deps[:web_frameworks] || []) > 0 do
          items =
            Enum.map(core_deps[:web_frameworks], fn d ->
              "- `#{d[:name]}`#{if d[:version], do: " #{d[:version]}", else: ""}"
            end)

          sections ++ ["### Web Frameworks\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      sections =
        if length(core_deps[:async_tools] || []) > 0 do
          items =
            Enum.map(core_deps[:async_tools], fn d ->
              "- `#{d[:name]}`#{if d[:version], do: " #{d[:version]}", else: ""}"
            end)

          sections ++ ["### Async & HTTP\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      sections =
        if length(core_deps[:data_validation] || []) > 0 do
          items =
            Enum.map(core_deps[:data_validation], fn d ->
              "- `#{d[:name]}`#{if d[:version], do: " #{d[:version]}", else: ""}"
            end)

          sections ++ ["### Data Validation\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      sections =
        if length(core_deps[:database] || []) > 0 do
          items =
            Enum.map(core_deps[:database], fn d ->
              "- `#{d[:name]}`#{if d[:version], do: " #{d[:version]}", else: ""}"
            end)

          sections ++ ["### Database\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      sections =
        if length(core_deps[:testing] || []) > 0 do
          items = Enum.map(core_deps[:testing], fn d -> "- `#{d[:name]}`" end)
          sections ++ ["### Testing\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      sections =
        if length(core_deps[:other] || []) > 0 && length(core_deps[:other]) <= 10 do
          items = Enum.map(core_deps[:other], fn d -> "- `#{d[:name]}`" end)
          sections ++ ["### Other Dependencies\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      if length(sections) > 0 do
        """
        ## Dependencies

        #{Enum.join(sections, "\n\n")}
        """
      else
        nil
      end
    else
      nil
    end
  end

  def build_commands(project_data) do
    files = project_data[:files] || []
    pyproject = Helpers.find_file(files, :pyproject)

    commands = []

    testing = if pyproject, do: pyproject[:testing] || %{}, else: %{}
    linting = if pyproject, do: pyproject[:linting] || %{}, else: %{}

    commands =
      if testing[:has_pytest] do
        commands ++
          [
            "| `pytest` | Run the test suite |",
            "| `pytest -v` | Run tests with verbose output |",
            "| `pytest --cov` | Run tests with coverage |"
          ]
      else
        commands
      end

    commands =
      if linting[:has_ruff] do
        commands ++
          [
            "| `ruff check .` | Run linting checks |",
            "| `ruff format .` | Format code |"
          ]
      else
        commands
      end

    commands = if linting[:has_mypy], do: commands ++ ["| `mypy .` | Run type checking |"], else: commands
    commands = if linting[:has_black], do: commands ++ ["| `black .` | Format code with Black |"], else: commands
    commands = if linting[:has_isort], do: commands ++ ["| `isort .` | Sort imports |"], else: commands

    commands =
      if pyproject && pyproject[:has_pre_commit] do
        commands ++ ["| `pre-commit run --all-files` | Run all pre-commit hooks |"]
      else
        commands
      end

    commands
  end

  def build_framework_practices(project_data) do
    files = project_data[:files] || []
    pyproject = Helpers.find_file(files, :pyproject)
    framework = detect_framework(pyproject, files)

    if framework do
      FrameworkPractices.get_best_practices(framework)
    else
      nil
    end
  end

  def build_restrictions do
    [
      "- `venv/`, `.venv/`, `env/` - Virtual environments",
      "- `__pycache__/`, `*.pyc` - Python bytecode",
      "- `.mypy_cache/`, `.ruff_cache/` - Linter caches",
      "- `dist/`, `build/`, `*.egg-info/` - Build outputs",
      "- `.git/` - Git internals"
    ]
  end

  def build_caution_items do
    [
      "- `.env*` - Environment configuration (contains secrets)",
      "- `*.pem`, `*.key` - Security certificates",
      "- `alembic/versions/` - Database migrations"
    ]
  end

  def detect_framework(pyproject, files) do
    py_name = if pyproject, do: pyproject[:name], else: nil
    py_name_lower = if py_name, do: String.downcase(py_name), else: nil

    deps =
      if pyproject && pyproject[:dependencies] do
        Enum.map(pyproject[:dependencies], fn dep ->
          String.downcase(dep[:name] || "")
        end)
      else
        req_files = Helpers.filter_files(files, :requirements_txt)

        req_files
        |> Enum.flat_map(fn f -> f[:dependencies] || [] end)
        |> Enum.map(fn dep -> String.downcase(dep[:name] || "") end)
      end

    cond do
      py_name_lower == "fastapi" or "fastapi" in deps -> "FastAPI"
      py_name_lower == "django" or "django" in deps -> "Django"
      py_name_lower == "flask" or "flask" in deps -> "Flask"
      py_name_lower == "starlette" or "starlette" in deps -> "Starlette"
      py_name_lower == "tornado" or "tornado" in deps -> "Tornado"
      py_name_lower == "aiohttp" or "aiohttp" in deps -> "aiohttp"
      py_name_lower == "sanic" or "sanic" in deps -> "Sanic"
      py_name_lower == "falcon" or "falcon" in deps -> "Falcon"
      true -> nil
    end
  end

  defp format_build_tool(tool) do
    case tool do
      "hatch" -> "Hatch"
      "poetry" -> "Poetry"
      "pdm" -> "PDM"
      "flit" -> "Flit"
      "setuptools" -> "setuptools"
      _ -> tool
    end
  end

  defp build_linting_tools(linting, pre_commit) do
    tools = []
    tools = if linting[:has_ruff] || (pre_commit && pre_commit[:has_ruff]), do: tools ++ ["Ruff"], else: tools
    tools = if linting[:has_mypy] || (pre_commit && pre_commit[:has_mypy]), do: tools ++ ["mypy"], else: tools
    tools = if linting[:has_black] || (pre_commit && pre_commit[:has_black]), do: tools ++ ["Black"], else: tools
    tools = if linting[:has_isort] || (pre_commit && pre_commit[:has_isort]), do: tools ++ ["isort"], else: tools
    tools
  end

  defp categorize_deps(deps) do
    %{
      web_frameworks: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @python_frameworks end),
      async_tools: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @async_tools end),
      data_validation: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @data_validation end),
      database: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @database_tools end),
      testing: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @testing_tools end),
      other:
        Enum.reject(deps, fn d ->
          name = String.downcase(d[:name] || "")
          name in (@python_frameworks ++ @async_tools ++ @data_validation ++ @database_tools ++ @testing_tools)
        end)
    }
  end
end
