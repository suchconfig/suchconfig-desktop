defmodule SuchConfigCore.Generators.AIContext.Go do
  @moduledoc """
  Go-specific AI context generation.

  Handles Go projects including:
  - Gin, Echo, Chi, Fiber, Huma, Gorilla frameworks
  - go.mod and go.sum dependency management
  - Testing with go test and testify
  - Linting with golangci-lint
  - Air hot reload for development
  """

  alias SuchConfigCore.Generators.AIContext.{Helpers, FrameworkPractices}

  @web_frameworks ["gin", "echo", "chi", "fiber", "huma", "gorilla", "beego", "revel", "iris", "goa"]

  def build_tech_stack(project_data) do
    files = project_data[:files] || []
    go_mod = Helpers.find_file(files, :go_mod)
    golangci = Helpers.find_file(files, :golangci_config)
    air_config = Helpers.find_file(files, :air_config)

    items = []

    framework = detect_framework(go_mod)
    items = if framework, do: items ++ ["- **Framework**: #{format_framework(framework)}"], else: items

    go_version = project_data[:go_version] || (go_mod && go_mod[:go_version])
    items = if go_version, do: items ++ ["- **Go**: #{go_version}"], else: items

    toolchain = go_mod && go_mod[:toolchain]
    items = if toolchain, do: items ++ ["- **Toolchain**: go#{toolchain}"], else: items

    items =
      if golangci != nil do
        items ++ ["- **Linting**: golangci-lint"]
      else
        items
      end

    items = if air_config, do: items ++ ["- **Hot Reload**: Air"], else: items

    database_type = detect_database(go_mod)
    items = if database_type, do: items ++ ["- **Database**: #{database_type}"], else: items

    testing_type = detect_testing(go_mod)
    items = if testing_type, do: items ++ ["- **Testing**: #{testing_type}"], else: items

    queue_type = detect_queue(go_mod)
    items = if queue_type, do: items ++ ["- **Queue**: #{queue_type}"], else: items

    items
  end

  def build_quick_start(project_data) do
    files = project_data[:files] || []
    go_mod = Helpers.find_file(files, :go_mod)
    air_config = Helpers.find_file(files, :air_config)
    makefile = Helpers.find_file(files, :makefile)
    docker_compose = Helpers.find_file(files, :docker_compose)
    contributing = Helpers.find_file(files, :contributing)

    steps = []

    steps =
      steps ++
        [
          "1. **Clone the repository**\n   ```bash\n   git clone <repository-url>\n   cd #{project_data[:project_name] || "project"}\n   ```"
        ]

    go_version = project_data[:go_version] || (go_mod && go_mod[:go_version])

    go_step =
      if go_version do
        "2. **Install Go #{go_version}**\n   ```bash\n   # Using asdf\n   asdf install golang #{go_version}\n   asdf local golang #{go_version}\n   \n   # Or download from https://go.dev/dl/\n   ```"
      else
        nil
      end

    steps = if go_step, do: steps ++ [go_step], else: steps

    docker_step =
      if docker_compose do
        "#{length(steps) + 1}. **Start Docker services**\n   ```bash\n   docker-compose up -d\n   ```"
      else
        nil
      end

    steps = if docker_step, do: steps ++ [docker_step], else: steps

    deps_step = "#{length(steps) + 1}. **Install dependencies**\n   ```bash\n   go mod download\n   ```"
    steps = steps ++ [deps_step]

    run_step =
      cond do
        makefile && Enum.member?(makefile[:targets] || [], "run") ->
          "#{length(steps) + 1}. **Run the project**\n   ```bash\n   make run\n   ```"

        air_config ->
          "#{length(steps) + 1}. **Run with hot reload**\n   ```bash\n   air\n   # Or without Air:\n   go run ./cmd/api/main.go\n   ```"

        makefile && Enum.member?(makefile[:targets] || [], "build") ->
          "#{length(steps) + 1}. **Build and run**\n   ```bash\n   make build\n   ./bin/server\n   ```"

        true ->
          "#{length(steps) + 1}. **Run the project**\n   ```bash\n   go run .\n   ```"
      end

    steps = steps ++ [run_step]

    contributing_note =
      if contributing do
        "\n> 📖 See `CONTRIBUTING.md` for detailed development guidelines"
      else
        nil
      end

    content = Enum.join(steps, "\n\n")

    """
    ## Quick Start

    #{content}#{contributing_note || ""}
    """
  end

  def build_dependencies(project_data) do
    files = project_data[:files] || []
    go_mod = Helpers.find_file(files, :go_mod)

    if go_mod && go_mod[:dependencies] do
      deps = go_mod[:dependencies] || []

      categorized = categorize_dependencies(deps)

      sections =
        categorized
        |> Enum.filter(fn {_category, packages} -> length(packages) > 0 end)
        |> Enum.sort_by(fn {category, _} -> category_order(category) end)
        |> Enum.map_join("\n\n", fn {category, packages} ->
          package_list =
            packages
            |> Enum.take(10)
            |> Enum.map_join("\n", fn dep -> "- `#{dep[:name]}` #{dep[:version] || ""}" end)

          "### #{category}\n#{package_list}"
        end)

      if sections != "" do
        """
        ## Dependencies

        #{sections}
        """
      else
        nil
      end
    else
      nil
    end
  end

  def build_framework_practices(project_data) do
    files = project_data[:files] || []
    go_mod = Helpers.find_file(files, :go_mod)
    framework = detect_framework(go_mod) || project_data[:framework]

    if framework && framework in @web_frameworks do
      FrameworkPractices.get_practices(framework)
    else
      FrameworkPractices.get_practices("go")
    end
  end

  def build_commands(project_data) do
    files = project_data[:files] || []
    air_config = Helpers.find_file(files, :air_config)
    golangci = Helpers.find_file(files, :golangci_config)

    commands = []

    commands =
      commands ++
        [
          "| `go build ./...` | Build all packages |",
          "| `go test ./...` | Run all tests |",
          "| `go test -v ./...` | Run tests with verbose output |",
          "| `go test -race ./...` | Run tests with race detector |",
          "| `go test -cover ./...` | Run tests with coverage |",
          "| `go mod tidy` | Clean up dependencies |",
          "| `go mod download` | Download dependencies |",
          "| `go vet ./...` | Run static analysis |"
        ]

    commands = if air_config, do: commands ++ ["| `air` | Run with hot reload |"], else: commands

    commands =
      if golangci do
        commands ++
          [
            "| `golangci-lint run` | Run linters |",
            "| `golangci-lint run --fix` | Run linters with auto-fix |"
          ]
      else
        commands
      end

    commands
  end

  def build_restrictions do
    [
      "- `vendor/` - Vendored dependencies",
      "- `bin/`, `dist/` - Build outputs",
      "- `*.exe`, `*.dll`, `*.so` - Compiled binaries",
      "- `.git/` - Git internals"
    ]
  end

  def build_caution_items do
    [
      "- `go.mod`, `go.sum` - Dependency management (run `go mod tidy` after changes)",
      "- `*.pb.go` - Generated protobuf files",
      "- `*_gen.go`, `*_generated.go` - Generated code"
    ]
  end

  defp detect_framework(nil), do: nil

  defp detect_framework(go_mod) do
    go_mod[:framework]
  end

  defp detect_database(nil), do: nil

  defp detect_database(go_mod) do
    deps = go_mod[:dependencies] || []
    dep_names = Enum.map(deps, & &1[:name]) |> Enum.reject(&is_nil/1)

    cond do
      Enum.any?(dep_names, &String.contains?(&1, "jackc/pgx")) -> "PostgreSQL (pgx)"
      Enum.any?(dep_names, &String.contains?(&1, "go-pg/pg")) -> "PostgreSQL (go-pg)"
      Enum.any?(dep_names, &String.contains?(&1, "lib/pq")) -> "PostgreSQL (lib/pq)"
      Enum.any?(dep_names, &String.contains?(&1, "gorm.io/gorm")) -> "GORM"
      Enum.any?(dep_names, &String.contains?(&1, "ent")) -> "Ent"
      Enum.any?(dep_names, &String.contains?(&1, "jmoiron/sqlx")) -> "sqlx"
      Enum.any?(dep_names, &String.contains?(&1, "mongo-driver")) -> "MongoDB"
      Enum.any?(dep_names, &String.contains?(&1, "redis")) -> "Redis"
      true -> nil
    end
  end

  defp detect_testing(nil), do: nil

  defp detect_testing(go_mod) do
    deps = go_mod[:dependencies] || []
    dep_names = Enum.map(deps, & &1[:name]) |> Enum.reject(&is_nil/1)

    tools = []
    tools = if Enum.any?(dep_names, &String.contains?(&1, "testify")), do: tools ++ ["testify"], else: tools
    tools = if Enum.any?(dep_names, &String.contains?(&1, "gomock")), do: tools ++ ["gomock"], else: tools
    tools = if Enum.any?(dep_names, &String.contains?(&1, "ginkgo")), do: tools ++ ["ginkgo"], else: tools
    tools = if Enum.any?(dep_names, &String.contains?(&1, "goconvey")), do: tools ++ ["goconvey"], else: tools

    if length(tools) > 0, do: Enum.join(tools, ", "), else: "go test"
  end

  defp detect_queue(nil), do: nil

  defp detect_queue(go_mod) do
    deps = go_mod[:dependencies] || []
    dep_names = Enum.map(deps, & &1[:name]) |> Enum.reject(&is_nil/1)

    cond do
      Enum.any?(dep_names, &String.contains?(&1, "riverqueue/river")) -> "River"
      Enum.any?(dep_names, &String.contains?(&1, "hibiken/asynq")) -> "Asynq"
      Enum.any?(dep_names, &String.contains?(&1, "machinery")) -> "Machinery"
      Enum.any?(dep_names, &String.contains?(&1, "rabbitmq")) -> "RabbitMQ"
      true -> nil
    end
  end

  defp format_framework("gin"), do: "Gin"
  defp format_framework("echo"), do: "Echo"
  defp format_framework("chi"), do: "Chi"
  defp format_framework("fiber"), do: "Fiber"
  defp format_framework("huma"), do: "Huma"
  defp format_framework("gorilla"), do: "Gorilla Mux"
  defp format_framework("beego"), do: "Beego"
  defp format_framework("revel"), do: "Revel"
  defp format_framework("iris"), do: "Iris"
  defp format_framework("goa"), do: "Goa"
  defp format_framework(name), do: name

  defp categorize_dependencies(deps) do
    categories = %{
      "🚀 Web Frameworks" => [],
      "🗄️ Database" => [],
      "🔐 Authentication" => [],
      "📊 Logging" => [],
      "⚡ Queue & Jobs" => [],
      "🧪 Testing" => [],
      "☁️ AWS" => [],
      "🛠️ Utilities" => [],
      "🔧 Other" => []
    }

    Enum.reduce(deps, categories, fn dep, acc ->
      category = categorize_dep(dep[:name] || "")
      Map.update!(acc, category, fn packages -> packages ++ [dep] end)
    end)
  end

  defp categorize_dep(name) do
    cond do
      String.contains?(name, [
        "gin-gonic",
        "labstack/echo",
        "go-chi/chi",
        "gofiber",
        "huma",
        "gorilla/mux",
        "beego",
        "revel",
        "iris"
      ]) ->
        "🚀 Web Frameworks"

      String.contains?(name, ["pgx", "go-pg", "lib/pq", "gorm", "ent", "sqlx", "mongo", "redis", "database"]) ->
        "🗄️ Database"

      String.contains?(name, ["jwt", "oauth", "session", "auth", "bcrypt", "argon"]) ->
        "🔐 Authentication"

      String.contains?(name, ["zap", "logrus", "zerolog", "logging"]) ->
        "📊 Logging"

      String.contains?(name, ["river", "asynq", "machinery", "rabbitmq", "queue"]) ->
        "⚡ Queue & Jobs"

      String.contains?(name, ["testify", "gomock", "ginkgo", "goconvey", "dockertest"]) ->
        "🧪 Testing"

      String.contains?(name, ["aws-sdk"]) ->
        "☁️ AWS"

      String.contains?(name, ["uuid", "validator", "godotenv", "viper", "cobra", "spf13"]) ->
        "🛠️ Utilities"

      true ->
        "🔧 Other"
    end
  end

  defp category_order(category) do
    order = %{
      "🚀 Web Frameworks" => 1,
      "🗄️ Database" => 2,
      "🔐 Authentication" => 3,
      "📊 Logging" => 4,
      "⚡ Queue & Jobs" => 5,
      "🧪 Testing" => 6,
      "☁️ AWS" => 7,
      "🛠️ Utilities" => 8,
      "🔧 Other" => 99
    }

    Map.get(order, category, 50)
  end
end
