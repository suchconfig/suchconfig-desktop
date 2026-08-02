defmodule SuchConfigCore.Generators.AIContext.Node do
  @moduledoc """
  Node.js/TypeScript-specific AI context generation.

  Handles JavaScript and TypeScript projects including:
  - Next.js, React, Vue, Angular, Svelte frameworks
  - npm, yarn, pnpm package managers
  - ESLint, Prettier, Biome tooling
  - Vitest, Jest, Cypress, Playwright testing
  - Tailwind CSS, styled-components styling
  """

  alias SuchConfigCore.Generators.AIContext.{Helpers, FrameworkPractices}

  @node_frameworks ["next", "react", "vue", "angular", "svelte", "nuxt", "express", "nestjs", "fastify"]
  @ui_libraries [
    "tailwindcss",
    "@tailwindcss/forms",
    "styled-components",
    "emotion",
    "chakra-ui",
    "material-ui",
    "@mui/material"
  ]

  def build_tech_stack(project_data) do
    deps = project_data[:dependencies] || []
    dep_names = Enum.map(deps, & &1[:name]) |> Enum.reject(&is_nil/1)

    items = []

    items =
      cond do
        "drizzle-orm" in dep_names -> items ++ ["- **Database ORM**: Drizzle"]
        "@prisma/client" in dep_names or "prisma" in dep_names -> items ++ ["- **Database ORM**: Prisma"]
        "typeorm" in dep_names -> items ++ ["- **Database ORM**: TypeORM"]
        "sequelize" in dep_names -> items ++ ["- **Database ORM**: Sequelize"]
        true -> items
      end

    items =
      cond do
        "pg" in dep_names or "postgres" in dep_names -> items ++ ["- **Database**: PostgreSQL"]
        "mysql2" in dep_names or "mysql" in dep_names -> items ++ ["- **Database**: MySQL"]
        "mongodb" in dep_names or "mongoose" in dep_names -> items ++ ["- **Database**: MongoDB"]
        "better-sqlite3" in dep_names -> items ++ ["- **Database**: SQLite"]
        true -> items
      end

    items = if "tailwindcss" in dep_names, do: items ++ ["- **Styling**: Tailwind CSS"], else: items

    items =
      if "stripe" in dep_names or "@stripe/stripe-js" in dep_names do
        items ++ ["- **Payments**: Stripe"]
      else
        items
      end

    items =
      cond do
        "next-auth" in dep_names or "@auth/core" in dep_names -> items ++ ["- **Auth**: NextAuth.js"]
        "@clerk/nextjs" in dep_names -> items ++ ["- **Auth**: Clerk"]
        "lucia" in dep_names -> items ++ ["- **Auth**: Lucia"]
        true -> items
      end

    items
  end

  def build_quick_start(project_data) do
    files = project_data[:files] || []
    pkg_json = Helpers.find_file(files, :package_json)

    if pkg_json do
      steps = []

      steps =
        steps ++
          [
            "1. **Clone the repository**\n   ```bash\n   git clone <repository-url>\n   cd #{project_data[:project_name] || "project"}\n   ```"
          ]

      pkg_mgr = detect_package_manager(project_data)
      install_cmd = "#{pkg_mgr} install"

      steps = steps ++ ["2. **Install dependencies**\n   ```bash\n   #{install_cmd}\n   ```"]

      framework = detect_framework(project_data)

      run_cmd =
        case framework do
          "Next.js" -> "#{pkg_mgr} run dev"
          "Express" -> "#{pkg_mgr} start"
          _ -> "#{pkg_mgr} run dev"
        end

      port =
        case framework do
          "Next.js" -> "3000"
          "Vue.js" -> "5173"
          "Express" -> "3000"
          _ -> "3000"
        end

      steps =
        steps ++
          [
            "3. **Start development server**\n   ```bash\n   #{run_cmd}\n   ```\n   Open http://localhost:#{port} in your browser."
          ]

      if length(steps) > 1 do
        content = Enum.join(steps, "\n\n")

        """
        ## Quick Start

        #{content}
        """
      else
        nil
      end
    else
      nil
    end
  end

  def build_dependencies(project_data) do
    deps = project_data[:dependencies] || []

    if length(deps) > 0 do
      categorized = categorize_deps(deps)
      sections = []

      sections =
        if length(categorized[:frameworks] || []) > 0 do
          items = Enum.map(categorized[:frameworks], fn d -> "- `#{d[:name]}` #{d[:version] || ""}" end)
          sections ++ ["### Frameworks\n#{Enum.join(items, "\n")}"]
        else
          sections
        end

      sections =
        if length(categorized[:ui] || []) > 0 do
          items = Enum.map(categorized[:ui], fn d -> "- `#{d[:name]}`" end)
          sections ++ ["### UI & Styling\n#{Enum.join(items, "\n")}"]
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
    scripts = project_data[:scripts] || []

    scripts
    |> Enum.filter(fn s -> s[:runner] == "npm run" end)
    |> Enum.take(15)
    |> Enum.map(fn s ->
      "| `npm run #{s[:name]}` | #{Helpers.describe_script(s[:name])} |"
    end)
  end

  def build_framework_practices(project_data) do
    framework = detect_framework(project_data)

    if framework do
      FrameworkPractices.get_best_practices(framework)
    else
      nil
    end
  end

  def build_restrictions do
    [
      "- `node_modules/` - Dependencies (auto-generated)",
      "- `dist/`, `build/`, `.next/` - Build outputs (auto-generated)",
      "- `.git/` - Git internals"
    ]
  end

  def build_caution_items do
    [
      "- `.env*` - Environment configuration (contains secrets)",
      "- `*.lock` - Lock files (auto-generated)",
      "- `*.pem`, `*.key` - Security certificates"
    ]
  end

  def detect_framework(project_data) do
    deps = project_data[:dependencies] || []
    dep_names = Enum.map(deps, fn d -> String.downcase(d[:name] || "") end)

    cond do
      "next" in dep_names -> "Next.js"
      "react" in dep_names and "next" not in dep_names -> "React"
      "vue" in dep_names -> "Vue.js"
      "@angular/core" in dep_names -> "Angular"
      "svelte" in dep_names -> "Svelte"
      "express" in dep_names -> "Express"
      "fastify" in dep_names -> "Fastify"
      "@nestjs/core" in dep_names -> "NestJS"
      true -> nil
    end
  end

  defp detect_package_manager(project_data) do
    files = project_data[:files] || []

    cond do
      Helpers.has_file?(files, :pnpm_lock) -> "pnpm"
      Helpers.has_file?(files, :yarn_lock) -> "yarn"
      Helpers.has_file?(files, :bun_lock) -> "bun"
      true -> "npm"
    end
  end

  defp categorize_deps(deps) do
    %{
      frameworks: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @node_frameworks end),
      ui: Enum.filter(deps, fn d -> String.downcase(d[:name] || "") in @ui_libraries end)
    }
  end
end
