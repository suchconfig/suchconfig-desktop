defmodule SuchConfigCore.Generators.AIContext.Ruby do
  @moduledoc """
  Ruby/Rails-specific AI context generation.

  Handles Ruby projects including:
  - Ruby on Rails, Sinatra, Hanami, Grape frameworks
  - Gemfile and Bundler dependency management
  - RSpec, Minitest, Cucumber testing
  - RuboCop, Standard linting
  - Rake task automation
  """

  alias SuchConfigCore.Generators.AIContext.{Helpers, FrameworkPractices}

  @web_frameworks ["sinatra", "hanami", "roda", "padrino", "cuba"]
  @rails_gems [
    "rails",
    "railties",
    "activerecord",
    "actionpack",
    "actionview",
    "activemodel",
    "actionmailer",
    "activejob",
    "actioncable",
    "activestorage",
    "actionmailbox",
    "actiontext",
    "activesupport",
    "sprockets-rails",
    "stimulus-rails",
    "turbo-rails",
    "jsbundling-rails",
    "cssbundling-rails",
    "importmap-rails",
    "tailwindcss-rails",
    "dartsass-rails",
    "propshaft"
  ]
  @database_gems [
    "sequel",
    "rom",
    "mongoid",
    "dynamoid",
    "redis",
    "pg",
    "mysql2",
    "sqlite3",
    "redis-namespace",
    "solid_cache",
    "solid_queue",
    "solid_cable"
  ]
  @background_jobs [
    "sidekiq",
    "resque",
    "delayed_job",
    "good_job",
    "que",
    "sneakers",
    "resque-scheduler",
    "queue_classic"
  ]
  @testing_gems [
    "rspec",
    "rspec-rails",
    "minitest",
    "cucumber",
    "capybara",
    "factory_bot",
    "faker",
    "minitest-bisect",
    "minitest-ci",
    "minitest-retry",
    "webmock",
    "vcr"
  ]
  @api_gems ["grape", "grape-swagger", "jsonapi-serializer", "active_model_serializers", "jbuilder"]
  @auth_gems ["devise", "authlogic", "clearance", "rodauth", "sorcery", "bcrypt", "argon2"]
  @linting_gems [
    "rubocop",
    "rubocop-rails",
    "rubocop-rspec",
    "rubocop-minitest",
    "rubocop-performance",
    "rubocop-packaging",
    "rubocop-md",
    "rubocop-rails-omakase",
    "standard",
    "mdl"
  ]
  @deployment_gems ["kamal", "capistrano", "mina", "thruster"]

  def build_tech_stack(project_data) do
    files = project_data[:files] || []
    gemfile = Helpers.find_file(files, :gemfile)
    gemspec = Helpers.find_file(files, :gemspec)
    rubocop = Helpers.find_file(files, :rubocop_config)
    application_rb = Helpers.find_file(files, :application_rb)

    items = []

    framework = detect_framework(gemfile, gemspec, files)
    items = if framework, do: items ++ ["- **Framework**: #{format_framework(framework)}"], else: items

    ruby_version = project_data[:ruby_version]
    items = if ruby_version, do: items ++ ["- **Ruby**: #{ruby_version}"], else: items

    rails_version = get_rails_version(gemfile, application_rb)
    items = if rails_version, do: items ++ ["- **Rails**: #{rails_version}"], else: items

    items =
      cond do
        rubocop != nil -> items ++ ["- **Linting**: RuboCop"]
        gemfile && gemfile[:has_standard] -> items ++ ["- **Linting**: Standard"]
        gemfile && gemfile[:has_rubocop] -> items ++ ["- **Linting**: RuboCop"]
        true -> items
      end

    testing_config = project_data[:testing_config] || %{}
    test_frameworks = build_testing_tools(testing_config, gemfile)
    items = if test_frameworks != "", do: items ++ ["- **Testing**: #{test_frameworks}"], else: items

    database_yml = Helpers.find_file(files, :database_yml)
    database_type = detect_database(database_yml, gemfile)
    items = if database_type, do: items ++ ["- **Database**: #{database_type}"], else: items

    server_config = Helpers.find_file(files, :server_config)
    server_type = if server_config, do: format_server(server_config[:server_type]), else: nil
    items = if server_type, do: items ++ ["- **Web Server**: #{server_type}"], else: items

    items
  end

  def build_quick_start(project_data) do
    files = project_data[:files] || []
    gemfile = Helpers.find_file(files, :gemfile)
    gemspec = Helpers.find_file(files, :gemspec)
    database_yml = Helpers.find_file(files, :database_yml)
    contributing = Helpers.find_file(files, :contributing)

    is_gem_source = gemspec != nil and gemfile != nil

    steps = []

    steps =
      steps ++
        [
          "1. **Clone the repository**\n   ```bash\n   git clone <repository-url>\n   cd #{project_data[:project_name] || "project"}\n   ```"
        ]

    ruby_version = project_data[:ruby_version]

    ruby_step =
      if ruby_version do
        "2. **Install Ruby #{ruby_version}**\n   ```bash\n   # Using rbenv\n   rbenv install #{ruby_version}\n   rbenv local #{ruby_version}\n   \n   # Or using asdf\n   asdf install ruby #{ruby_version}\n   asdf local ruby #{ruby_version}\n   ```"
      else
        nil
      end

    steps = if ruby_step, do: steps ++ [ruby_step], else: steps

    install_step = "#{length(steps) + 1}. **Install dependencies**\n   ```bash\n   bundle install\n   ```"
    steps = steps ++ [install_step]

    if is_gem_source do
      test_step =
        "#{length(steps) + 1}. **Run tests**\n   ```bash\n   bundle exec rake test\n   # Or for specific components:\n   cd activerecord && bundle exec rake test\n   ```"

      steps = steps ++ [test_step]

      lint_step =
        if gemfile[:has_rubocop] do
          "#{length(steps) + 1}. **Check code style**\n   ```bash\n   bundle exec rubocop\n   ```"
        else
          nil
        end

      steps = if lint_step, do: steps ++ [lint_step], else: steps

      contributing_setup =
        if contributing do
          "\n> 📖 This is framework source code. See `CONTRIBUTING.md` for development guidelines."
        else
          nil
        end

      content = Enum.join(steps, "\n\n")

      """
      ## Quick Start (Development)

      #{content}#{contributing_setup || ""}
      """
    else
      db_step =
        if database_yml && gemfile && gemfile[:has_rails] do
          "#{length(steps) + 1}. **Setup database**\n   ```bash\n   bin/rails db:setup\n   # Or for existing databases:\n   bin/rails db:migrate\n   ```"
        else
          nil
        end

      steps = if db_step, do: steps ++ [db_step], else: steps

      framework = detect_framework(gemfile, gemspec, files)

      run_cmd =
        case framework do
          "rails" -> "bin/rails server"
          "sinatra" -> "ruby app.rb"
          "hanami" -> "hanami server"
          "grape" -> "bundle exec rackup"
          _ -> "bundle exec rake"
        end

      run_step = "#{length(steps) + 1}. **Run the project**\n   ```bash\n   #{run_cmd}\n   ```"
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
  end

  def build_dependencies(project_data) do
    files = project_data[:files] || []
    gemfile = Helpers.find_file(files, :gemfile)
    gemspec = Helpers.find_file(files, :gemspec)

    gems =
      cond do
        gemfile != nil -> gemfile[:gems] || []
        gemspec != nil -> (gemspec[:dependencies] || []) ++ (gemspec[:dev_dependencies] || [])
        true -> []
      end

    if length(gems) > 0 do
      categorized = categorize_gems(gems)
      sections = []

      sections =
        if length(categorized[:rails] || []) > 0 do
          items = format_gem_list(categorized[:rails])
          sections ++ ["### Rails Components\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:web_frameworks] || []) > 0 do
          items = format_gem_list(categorized[:web_frameworks])
          sections ++ ["### Web Frameworks\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:database] || []) > 0 do
          items = format_gem_list(categorized[:database])
          sections ++ ["### Database\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:background_jobs] || []) > 0 do
          items = format_gem_list(categorized[:background_jobs])
          sections ++ ["### Background Jobs\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:api] || []) > 0 do
          items = format_gem_list(categorized[:api])
          sections ++ ["### API\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:auth] || []) > 0 do
          items = format_gem_list(categorized[:auth])
          sections ++ ["### Authentication\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:testing] || []) > 0 do
          items = format_gem_list(categorized[:testing])
          sections ++ ["### Testing\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:linting] || []) > 0 do
          items = format_gem_list(categorized[:linting])
          sections ++ ["### Linting & Code Quality\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:deployment] || []) > 0 do
          items = format_gem_list(categorized[:deployment])
          sections ++ ["### Deployment\n#{items}"]
        else
          sections
        end

      sections =
        if length(categorized[:other] || []) > 0 && length(categorized[:other]) <= 15 do
          items = format_gem_list(categorized[:other])
          sections ++ ["### Other Gems\n#{items}"]
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
    gemfile = Helpers.find_file(files, :gemfile)
    rakefile = Helpers.find_file(files, :rakefile)

    commands = []

    commands =
      if gemfile && gemfile[:has_rails] do
        commands ++
          [
            "| `bin/rails server` | Start development server |",
            "| `bin/rails console` | Start Rails console |",
            "| `bin/rails db:migrate` | Run database migrations |",
            "| `bin/rails db:seed` | Seed the database |",
            "| `bin/rails routes` | List all routes |",
            "| `bin/rails generate` | Run Rails generators |"
          ]
      else
        commands
      end

    testing_config = project_data[:testing_config] || %{}

    commands =
      if testing_config[:rspec] do
        commands ++
          [
            "| `bundle exec rspec` | Run RSpec tests |",
            "| `bundle exec rspec --format doc` | Run tests with documentation format |"
          ]
      else
        commands
      end

    commands =
      if testing_config[:minitest] do
        commands ++ ["| `bin/rails test` | Run Minitest tests |"]
      else
        commands
      end

    commands =
      if testing_config[:cucumber] do
        commands ++ ["| `bundle exec cucumber` | Run Cucumber features |"]
      else
        commands
      end

    code_quality = project_data[:code_quality] || %{}

    commands =
      if code_quality[:rubocop] do
        commands ++
          [
            "| `bundle exec rubocop` | Run RuboCop linter |",
            "| `bundle exec rubocop -a` | Auto-fix RuboCop offenses |"
          ]
      else
        commands
      end

    commands =
      if code_quality[:standard_rb] do
        commands ++
          [
            "| `bundle exec standardrb` | Run Standard linter |",
            "| `bundle exec standardrb --fix` | Auto-fix Standard offenses |"
          ]
      else
        commands
      end

    rake_tasks = rakefile[:tasks] || []
    common_tasks = ["spec", "test", "default", "db:migrate", "assets:precompile"]

    rake_commands =
      rake_tasks
      |> Enum.filter(fn task -> task in common_tasks end)
      |> Enum.take(5)
      |> Enum.map(fn task -> "| `rake #{task}` | #{describe_rake_task(task)} |" end)

    commands = commands ++ rake_commands

    commands
  end

  def build_framework_practices(project_data) do
    files = project_data[:files] || []
    gemfile = Helpers.find_file(files, :gemfile)
    gemspec = Helpers.find_file(files, :gemspec)
    framework = detect_framework(gemfile, gemspec, files)

    if framework do
      FrameworkPractices.get_best_practices(framework)
    else
      nil
    end
  end

  def build_restrictions do
    [
      "- `vendor/bundle/` - Bundled gems",
      "- `log/`, `tmp/` - Temporary files and logs",
      "- `coverage/` - Test coverage reports",
      "- `node_modules/` - JavaScript dependencies (if using)",
      "- `.git/` - Git internals"
    ]
  end

  def build_caution_items do
    [
      "- `.env*` - Environment configuration (contains secrets)",
      "- `config/credentials.yml.enc` - Encrypted credentials",
      "- `config/master.key` - Encryption key",
      "- `db/schema.rb` - Database schema (auto-generated)",
      "- `db/migrate/` - Database migrations (historical record)"
    ]
  end

  def detect_framework(gemfile, gemspec, files) do
    gems = if gemfile, do: gemfile[:gems] || [], else: []
    gem_names = Enum.map(gems, & &1.name)

    application_rb = Helpers.find_file(files, :application_rb)
    routes_rb = Helpers.find_file(files, :routes_rb)

    cond do
      (gemfile && gemfile[:has_rails]) or application_rb != nil or routes_rb != nil ->
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

      gemspec != nil and gemspec[:name] == "rails" ->
        "rails"

      true ->
        nil
    end
  end

  defp get_rails_version(gemfile, application_rb) do
    cond do
      gemfile && gemfile[:rails_version] -> gemfile[:rails_version]
      application_rb && application_rb[:rails_version] -> application_rb[:rails_version]
      true -> nil
    end
  end

  defp format_framework(framework) do
    case framework do
      "rails" -> "Ruby on Rails"
      "sinatra" -> "Sinatra"
      "hanami" -> "Hanami"
      "grape" -> "Grape"
      "roda" -> "Roda"
      "padrino" -> "Padrino"
      "cuba" -> "Cuba"
      _ -> String.capitalize(framework)
    end
  end

  defp format_server(server_type) do
    case server_type do
      :puma -> "Puma"
      :unicorn -> "Unicorn"
      _ -> to_string(server_type)
    end
  end

  defp build_testing_tools(testing_config, gemfile) do
    tools = []
    tools = if testing_config[:rspec], do: tools ++ ["RSpec"], else: tools
    tools = if testing_config[:minitest], do: tools ++ ["Minitest"], else: tools
    tools = if testing_config[:cucumber], do: tools ++ ["Cucumber"], else: tools

    tools =
      if gemfile do
        gems = gemfile[:gems] || []
        gem_names = Enum.map(gems, & &1.name)

        tools = if "capybara" in gem_names, do: tools ++ ["Capybara"], else: tools

        tools =
          if "factory_bot" in gem_names or "factory_bot_rails" in gem_names, do: tools ++ ["FactoryBot"], else: tools

        tools
      else
        tools
      end

    Enum.uniq(tools) |> Enum.join(", ")
  end

  defp detect_database(database_yml, gemfile) do
    cond do
      database_yml && database_yml[:has_postgresql] -> "PostgreSQL"
      database_yml && database_yml[:has_mysql] -> "MySQL"
      database_yml && database_yml[:has_sqlite] -> "SQLite"
      gemfile && Enum.any?(gemfile[:gems] || [], fn g -> g.name == "pg" end) -> "PostgreSQL"
      gemfile && Enum.any?(gemfile[:gems] || [], fn g -> g.name == "mysql2" end) -> "MySQL"
      gemfile && Enum.any?(gemfile[:gems] || [], fn g -> g.name == "sqlite3" end) -> "SQLite"
      true -> nil
    end
  end

  defp categorize_gems(gems) do
    all_known =
      @web_frameworks ++
        @rails_gems ++
        @database_gems ++
        @background_jobs ++
        @api_gems ++ @auth_gems ++ @testing_gems ++ @linting_gems ++ @deployment_gems

    %{
      web_frameworks: filter_gems_exact(gems, @web_frameworks),
      rails: filter_gems_exact(gems, @rails_gems),
      database: filter_gems_exact(gems, @database_gems),
      background_jobs: filter_gems_exact(gems, @background_jobs),
      api: filter_gems_exact(gems, @api_gems),
      auth: filter_gems_exact(gems, @auth_gems),
      testing: filter_gems_exact(gems, @testing_gems),
      linting: filter_gems_exact(gems, @linting_gems),
      deployment: filter_gems_exact(gems, @deployment_gems),
      other: reject_gems_exact(gems, all_known)
    }
  end

  defp filter_gems_exact(gems, names) do
    Enum.filter(gems, fn g ->
      name = String.downcase(g.name || "")
      Enum.any?(names, fn n -> name == n or String.starts_with?(name, n <> "-") end)
    end)
  end

  defp reject_gems_exact(gems, names) do
    Enum.reject(gems, fn g ->
      name = String.downcase(g.name || "")
      Enum.any?(names, fn n -> name == n or String.starts_with?(name, n <> "-") end)
    end)
  end

  defp format_gem_list(gems) do
    gems
    |> Enum.take(10)
    |> Enum.map_join("\n", fn g ->
      version_str = if g.version, do: " #{g.version}", else: ""
      "- `#{g.name}`#{version_str}"
    end)
  end

  defp describe_rake_task(task) do
    case task do
      "spec" -> "Run RSpec tests"
      "test" -> "Run tests"
      "default" -> "Run default task"
      "db:migrate" -> "Run database migrations"
      "assets:precompile" -> "Precompile assets"
      _ -> "Run #{task}"
    end
  end
end
