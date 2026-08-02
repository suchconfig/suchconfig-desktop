defmodule SuchConfigCore.Generators.AIContext.Contributing do
  @moduledoc """
  Generates a Contributing guide from parsed CONTRIBUTING.md data.

  This module creates a comprehensive contributor's guide that includes:
  - System requirements and prerequisites
  - Development environment setup steps
  - Coding guidelines and conventions
  - Ways to contribute
  - Issue and PR templates info
  - Testing requirements
  """

  alias SuchConfigCore.Generators.AIContext.Helpers

  def generate(project_data) do
    files = project_data[:files] || []
    contributing = Helpers.find_file(files, :contributing)
    readme = Helpers.find_file(files, :readme)
    code_of_conduct = Helpers.find_file(files, :code_of_conduct)
    security = Helpers.find_file(files, :security_md)
    agents = Helpers.find_file(files, :agents_md)

    if contributing do
      sections = [
        build_header(project_data),
        build_overview(project_data, contributing),
        build_requirements(contributing, project_data),
        build_setup_steps(contributing, project_data),
        build_development_workflow(contributing, project_data),
        build_coding_guidelines(contributing, agents),
        build_testing_section(contributing, project_data),
        build_ways_to_contribute(contributing),
        build_issue_conventions(contributing),
        build_pr_guidelines(contributing),
        build_code_of_conduct(code_of_conduct),
        build_security_info(security),
        build_resources(project_data, readme),
        build_footer()
      ]

      content =
        sections
        |> Enum.reject(fn s -> is_nil(s) or s == "" end)
        |> Enum.join("\n\n")

      {:ok, content}
    else
      {:ok, build_no_contributing_guide(project_data)}
    end
  end

  defp build_header(project_data) do
    project_name = project_data[:project_name] || "Project"

    """
    # Contributing to #{project_name}

    > Auto-generated contributing guide by SuchConfig Workflow Wizard
    """
  end

  defp build_overview(project_data, contributing) do
    project_name = project_data[:project_name] || "this project"
    project_type = Helpers.format_project_type(project_data[:project_type])

    description =
      cond do
        contributing[:description] -> contributing[:description]
        project_type -> "This is a #{project_type} project."
        true -> nil
      end

    overview_parts = ["Thank you for your interest in contributing to #{project_name}!"]
    overview_parts = if description, do: overview_parts ++ [description], else: overview_parts

    if contributing[:has_monorepo_info] do
      overview_parts = overview_parts ++ ["This is a **monorepo** project with multiple packages."]

      """
      ## Overview

      #{Enum.join(overview_parts, " ")}
      """
    else
      """
      ## Overview

      #{Enum.join(overview_parts, " ")}
      """
    end
  end

  defp build_requirements(contributing, project_data) do
    reqs = contributing[:requirements] || %{}

    items = []

    items =
      if reqs[:node_version] do
        items ++ ["- **Node.js**: #{reqs[:node_version]}"]
      else
        if project_data[:node_version] do
          items ++ ["- **Node.js**: #{project_data[:node_version]}"]
        else
          items
        end
      end

    items =
      if reqs[:python_version] do
        items ++ ["- **Python**: #{reqs[:python_version]}"]
      else
        items
      end

    items =
      if project_data[:ruby_version] do
        items ++ ["- **Ruby**: #{project_data[:ruby_version]}"]
      else
        items
      end

    items =
      if project_data[:elixir_version] do
        items ++ ["- **Elixir**: #{project_data[:elixir_version]}"]
      else
        items
      end

    items =
      if reqs[:docker_required] do
        items ++ ["- **Docker**: Required (Docker Engine installed and running)"]
      else
        items
      end

    items =
      if reqs[:postgres_version] do
        items ++ ["- **PostgreSQL**: v#{reqs[:postgres_version]}"]
      else
        items
      end

    items =
      if reqs[:redis_version] do
        items ++ ["- **Redis**: v#{reqs[:redis_version]}"]
      else
        items
      end

    items =
      if reqs[:memory_requirement] do
        items ++ ["- **Memory**: Minimum #{reqs[:memory_requirement]}"]
      else
        items
      end

    if length(items) > 0 do
      """
      ## Prerequisites

      Before you begin, ensure you have the following installed:

      #{Enum.join(items, "\n")}
      """
    else
      nil
    end
  end

  defp build_setup_steps(contributing, project_data) do
    steps = contributing[:setup_steps] || []

    if length(steps) > 0 do
      step_items =
        Enum.map_join(steps, "\n", fn step ->
          description = if step[:description], do: "\n#{step[:description]}", else: ""

          """
          ### #{step[:order]}. #{step[:title]}#{description}

          ```bash
          #{step[:command]}
          ```
          """
        end)

      """
      ## Development Setup

      Follow these steps to set up your development environment:

      #{step_items}
      """
    else
      build_default_setup_steps(project_data)
    end
  end

  defp build_default_setup_steps(project_data) do
    project_type = project_data[:project_type]
    project_name = project_data[:project_name] || "project"

    steps =
      case project_type do
        :node ->
          """
          ### 1. Fork and Clone

          ```bash
          git clone https://github.com/YOUR_USERNAME/#{project_name}.git
          cd #{project_name}
          ```

          ### 2. Install Dependencies

          ```bash
          npm install
          # or
          pnpm install
          ```

          ### 3. Run Tests

          ```bash
          npm test
          ```
          """

        :ruby ->
          """
          ### 1. Fork and Clone

          ```bash
          git clone https://github.com/YOUR_USERNAME/#{project_name}.git
          cd #{project_name}
          ```

          ### 2. Install Dependencies

          ```bash
          bundle install
          ```

          ### 3. Run Tests

          ```bash
          bundle exec rake test
          # or
          bundle exec rspec
          ```
          """

        :python ->
          """
          ### 1. Fork and Clone

          ```bash
          git clone https://github.com/YOUR_USERNAME/#{project_name}.git
          cd #{project_name}
          ```

          ### 2. Create Virtual Environment

          ```bash
          python -m venv venv
          source venv/bin/activate
          ```

          ### 3. Install Dependencies

          ```bash
          pip install -e .[dev]
          ```

          ### 4. Run Tests

          ```bash
          pytest
          ```
          """

        :elixir ->
          """
          ### 1. Fork and Clone

          ```bash
          git clone https://github.com/YOUR_USERNAME/#{project_name}.git
          cd #{project_name}
          ```

          ### 2. Install Dependencies

          ```bash
          mix deps.get
          ```

          ### 3. Run Tests

          ```bash
          mix test
          ```
          """

        _ ->
          """
          ### 1. Fork and Clone

          ```bash
          git clone https://github.com/YOUR_USERNAME/#{project_name}.git
          cd #{project_name}
          ```

          ### 2. Install Dependencies

          Check the project's README for specific installation instructions.

          ### 3. Run Tests

          Check the project's README for testing instructions.
          """
      end

    """
    ## Development Setup

    #{steps}
    """
  end

  defp build_development_workflow(contributing, project_data) do
    has_docker =
      contributing[:has_docker_setup] || (project_data[:docker_config] && project_data[:docker_config][:has_dockerfile])

    sections = []

    sections =
      if has_docker do
        sections ++
          [
            """
            ### Docker Development

            This project supports Docker for development:

            ```bash
            docker-compose up -d
            ```
            """
          ]
      else
        sections
      end

    if length(sections) > 0 do
      """
      ## Development Workflow

      #{Enum.join(sections, "\n\n")}
      """
    else
      nil
    end
  end

  defp build_coding_guidelines(contributing, agents) do
    guidelines = contributing[:coding_guidelines] || []
    agents_style = if agents, do: agents[:code_style] || [], else: []

    all_guidelines = guidelines ++ agents_style

    if length(all_guidelines) > 0 do
      items =
        all_guidelines
        |> Enum.uniq_by(fn g -> g[:tool] end)
        |> Enum.map_join("\n", fn g ->
          tool = String.capitalize(to_string(g[:tool] || "General"))
          description = g[:description] || g[:guideline] || ""
          "- **#{tool}**: #{description}"
        end)

      """
      ## Coding Guidelines

      Please follow these coding standards:

      #{items}
      """
    else
      nil
    end
  end

  defp build_testing_section(_contributing, project_data) do
    testing_config = project_data[:testing_config] || %{}
    frameworks = testing_config[:frameworks] || []

    test_cmd =
      cond do
        project_data[:project_type] == :ruby -> "`bundle exec rake test` or `bundle exec rspec`"
        project_data[:project_type] == :python -> "`pytest`"
        project_data[:project_type] == :elixir -> "`mix test`"
        project_data[:project_type] == :node -> "`npm test` or `pnpm test`"
        true -> "the appropriate test command"
      end

    framework_list =
      if length(frameworks) > 0 do
        "This project uses #{Enum.join(frameworks, ", ")} for testing."
      else
        nil
      end

    """
    ## Testing

    Before submitting a pull request, please ensure all tests pass:

    ```bash
    #{String.replace(test_cmd, "`", "")}
    ```

    #{framework_list || ""}

    ### Writing Tests

    - Write tests for any new functionality
    - Ensure existing tests pass
    - Follow the existing test patterns in the codebase
    """
  end

  defp build_ways_to_contribute(contributing) do
    ways = contributing[:ways_to_contribute] || []

    if length(ways) > 0 do
      items = Enum.map_join(ways, "\n", &"- #{&1}")

      """
      ## Ways to Contribute

      There are many ways to contribute to this project:

      #{items}
      """
    else
      """
      ## Ways to Contribute

      There are many ways to contribute:

      - 🐛 **Report bugs** - Open an issue describing the bug
      - 💡 **Suggest features** - Open an issue with your idea
      - 📖 **Improve documentation** - Fix typos, add examples
      - 🔧 **Submit fixes** - Open a pull request with your fix
      - ✨ **Add features** - Implement new functionality
      - 🧪 **Write tests** - Improve test coverage
      - 👥 **Help others** - Answer questions in issues/discussions
      """
    end
  end

  defp build_issue_conventions(contributing) do
    conventions = contributing[:issue_conventions] || %{}

    if map_size(conventions) > 0 do
      items = []

      items =
        if conventions[:labels] && length(conventions[:labels]) > 0 do
          label_list = Enum.join(conventions[:labels], "`, `")
          items ++ ["- Use labels: `#{label_list}`"]
        else
          items
        end

      items =
        if conventions[:templates] do
          items ++ ["- Use the provided issue templates when available"]
        else
          items
        end

      items =
        if conventions[:prefix] do
          items ++ ["- Prefix issues with: `#{conventions[:prefix]}`"]
        else
          items
        end

      if length(items) > 0 do
        """
        ## Issue Guidelines

        When opening issues:

        #{Enum.join(items, "\n")}
        - Provide clear, reproducible steps for bugs
        - Include relevant version numbers and environment details
        """
      else
        nil
      end
    else
      nil
    end
  end

  defp build_pr_guidelines(contributing) do
    pr_conventions = contributing[:pr_conventions] || %{}

    """
    ## Pull Request Guidelines

    When submitting a pull request:

    1. **Fork the repository** and create your branch from `main` (or the default branch)
    2. **Make your changes** in a new branch
    3. **Write or update tests** as needed
    4. **Ensure all tests pass** locally
    5. **Follow the coding style** of the project
    6. **Write a clear PR description** explaining your changes
    7. **Reference any related issues** using `Fixes #123` or `Closes #123`

    #{if pr_conventions[:require_tests], do: "> ⚠️ All PRs must include tests\n", else: ""}
    #{if pr_conventions[:require_changelog], do: "> 📝 Please update the CHANGELOG\n", else: ""}
    """
  end

  defp build_code_of_conduct(code_of_conduct) do
    if code_of_conduct do
      """
      ## Code of Conduct

      This project has a Code of Conduct. Please read and follow it to ensure a welcoming environment for all contributors.

      See `CODE_OF_CONDUCT.md` for details.
      """
    else
      nil
    end
  end

  defp build_security_info(security) do
    if security do
      contact = security[:security_contact]
      email_line = if contact, do: "\n\n📧 Security contact: `#{contact}`", else: ""

      """
      ## Security

      If you discover a security vulnerability, please **do not** open a public issue.

      Instead, please follow the security policy in `SECURITY.md`.#{email_line}
      """
    else
      nil
    end
  end

  defp build_resources(project_data, _readme) do
    resources = []

    resources = resources ++ ["- 📖 **README** - Project overview and quick start"]

    resources =
      if Helpers.has_file?(project_data[:files] || [], :contributing) do
        resources ++ ["- 📝 **CONTRIBUTING.md** - Full contribution guidelines"]
      else
        resources
      end

    resources =
      if Helpers.has_file?(project_data[:files] || [], :security_md) do
        resources ++ ["- 🔒 **SECURITY.md** - Security policy"]
      else
        resources
      end

    resources =
      if Helpers.has_file?(project_data[:files] || [], :code_of_conduct) do
        resources ++ ["- 🤝 **CODE_OF_CONDUCT.md** - Community guidelines"]
      else
        resources
      end

    """
    ## Resources

    #{Enum.join(resources, "\n")}
    """
  end

  defp build_footer do
    """
    ---

    *Generated by [SuchConfig Workflow Wizard](https://suchconfig.io)*

    Thank you for contributing! 🙏
    """
  end

  defp build_no_contributing_guide(project_data) do
    project_name = project_data[:project_name] || "Project"
    _project_type = Helpers.format_project_type(project_data[:project_type]) || "this"

    """
    # Contributing to #{project_name}

    > Auto-generated contributing guide by SuchConfig Workflow Wizard

    ## Overview

    Thank you for your interest in contributing to #{project_name}!

    This project does not have a `CONTRIBUTING.md` file, but contributions are welcome.

    ## General Guidelines

    1. **Fork the repository** and clone it locally
    2. **Create a branch** for your changes
    3. **Make your changes** following the existing code style
    4. **Test your changes** thoroughly
    5. **Submit a pull request** with a clear description

    ## Getting Help

    If you have questions, please open an issue in the repository.

    ---

    *Generated by [SuchConfig Workflow Wizard](https://suchconfig.io)*
    """
  end
end
