defmodule SuchConfigCore.Generators.AIContext.FrameworkPractices do
  @moduledoc """
  Framework-specific best practices for AI context generation.

  Provides coding guidelines, project structures, and patterns for various
  frameworks across different programming languages.

  ## Supported Frameworks

  ### Python
  - FastAPI
  - Django
  - Flask

  ### Node.js/TypeScript
  - Next.js
  - React
  - Vue.js (planned)
  - Express (planned)

  ### Ruby (planned)
  - Ruby on Rails
  - Sinatra

  ### Rust (planned)
  - Actix Web
  - Axum

  ### Go (planned)
  - Gin
  - Echo
  """

  def build_fastapi_best_practices do
    """
    ## FastAPI Best Practices

    ### Core Patterns

    - Use **Pydantic models** for request and response schemas
    - Implement **dependency injection** for shared resources (database sessions, auth, etc.)
    - Utilize **async/await** for non-blocking I/O operations
    - Use path operation decorators (`@app.get`, `@app.post`, `@app.put`, `@app.delete`)
    - Implement proper error handling with `HTTPException`
    - Leverage FastAPI's built-in **OpenAPI** and **JSON Schema** support

    ### Type Hints

    - Use type hints for **all** function parameters and return values
    - Use `Optional[T]` for nullable fields
    - Use `List[T]`, `Dict[K, V]` for collections
    - Use `Union[A, B]` for multiple types

    ### Project Structure

    ```
    app/
    ├── main.py           # Application entry point
    ├── models/           # SQLAlchemy/database models
    ├── schemas/          # Pydantic request/response schemas
    ├── routers/          # API route handlers (endpoints)
    ├── dependencies/     # Dependency injection functions
    ├── services/         # Business logic layer
    ├── core/             # Config, security, constants
    └── tests/            # Test files
    ```

    ### Coding Guidelines

    1. **Validation**: Use Pydantic for all input validation
    2. **Background Tasks**: Use `BackgroundTasks` for long-running operations
    3. **CORS**: Configure CORS middleware properly for frontend integration
    4. **Security**: Use FastAPI's security utilities (`OAuth2PasswordBearer`, `HTTPBearer`)
    5. **Style**: Follow PEP 8 and use type hints everywhere
    6. **Testing**: Write comprehensive unit and integration tests with `pytest`
    7. **Async**: Prefer async database drivers (`asyncpg`, `databases`)

    ### Common Patterns

    ```python
    # Dependency injection example
    async def get_db():
        async with AsyncSession() as session:
            yield session

    # Route with dependency
    @app.get("/items/{item_id}")
    async def read_item(item_id: int, db: AsyncSession = Depends(get_db)):
        ...
    ```
    """
  end

  def build_django_best_practices do
    """
    ## Django Best Practices

    ### Core Patterns

    - Follow the **MTV** (Model-Template-View) architecture
    - Use **class-based views** for complex logic, function-based for simple endpoints
    - Leverage Django's **ORM** for database operations
    - Use **Django REST Framework** for API development
    - Implement proper **middleware** for cross-cutting concerns

    ### Project Structure

    ```
    project/
    ├── manage.py
    ├── config/           # Project settings
    │   ├── settings/
    │   ├── urls.py
    │   └── wsgi.py
    ├── apps/             # Django applications
    │   └── app_name/
    │       ├── models.py
    │       ├── views.py
    │       ├── serializers.py
    │       ├── urls.py
    │       └── tests/
    └── templates/
    ```

    ### Coding Guidelines

    1. **Models**: Keep models thin, use managers for complex queries
    2. **Views**: Keep views thin, move business logic to services
    3. **Forms**: Use Django forms/serializers for validation
    4. **Security**: Use `@login_required`, CSRF protection, and proper permissions
    5. **Testing**: Use Django's test client and `pytest-django`
    6. **Migrations**: Always review auto-generated migrations
    """
  end

  def build_flask_best_practices do
    """
    ## Flask Best Practices

    ### Core Patterns

    - Use **Blueprints** for modular application structure
    - Implement **Flask-SQLAlchemy** for database operations
    - Use **Flask-Marshmallow** for serialization/validation
    - Leverage **application factory pattern** for configuration
    - Use **Flask-Login** or **Flask-JWT-Extended** for authentication

    ### Project Structure

    ```
    app/
    ├── __init__.py       # Application factory
    ├── models/           # Database models
    ├── views/            # Route handlers (blueprints)
    ├── schemas/          # Marshmallow schemas
    ├── services/         # Business logic
    ├── extensions.py     # Flask extensions initialization
    └── config.py         # Configuration classes
    ```

    ### Coding Guidelines

    1. **Factory Pattern**: Use `create_app()` for flexible configuration
    2. **Blueprints**: Organize routes into blueprints by feature
    3. **Context**: Understand application and request context
    4. **Error Handling**: Register custom error handlers
    5. **Testing**: Use Flask's test client with `pytest`
    """
  end

  def build_nextjs_best_practices do
    """
    ## Next.js Best Practices

    ### Core Patterns

    - Use the **App Router** (Next.js 13+) for new projects
    - Leverage **Server Components** by default, Client Components when needed
    - Use **Server Actions** for form handling and mutations
    - Implement proper **loading** and **error** boundaries
    - Use **Route Handlers** for API endpoints

    ### Project Structure (App Router)

    ```
    app/
    ├── layout.tsx        # Root layout
    ├── page.tsx          # Home page
    ├── globals.css
    ├── (routes)/         # Route groups
    │   └── dashboard/
    │       ├── page.tsx
    │       └── layout.tsx
    ├── api/              # API routes
    └── components/       # Shared components
    lib/                  # Utilities, helpers
    public/               # Static assets
    ```

    ### Coding Guidelines

    1. **Components**: Use Server Components for data fetching, Client for interactivity
    2. **Data Fetching**: Use `fetch` with caching in Server Components
    3. **State**: Use React Server Components + minimal client state
    4. **Styling**: Use CSS Modules, Tailwind CSS, or CSS-in-JS
    5. **SEO**: Use `metadata` export for SEO optimization
    6. **Images**: Always use `next/image` for optimization
    7. **Links**: Use `next/link` for client-side navigation
    """
  end

  def build_react_best_practices do
    """
    ## React Best Practices

    ### Core Patterns

    - Use **functional components** with hooks
    - Implement proper **state management** (useState, useReducer, or external)
    - Use **custom hooks** for reusable logic
    - Follow **component composition** over inheritance
    - Implement proper **error boundaries**

    ### Project Structure

    ```
    src/
    ├── components/       # Reusable UI components
    │   └── Button/
    │       ├── Button.tsx
    │       ├── Button.test.tsx
    │       └── index.ts
    ├── hooks/            # Custom hooks
    ├── pages/            # Page components
    ├── services/         # API calls
    ├── store/            # State management
    ├── utils/            # Helper functions
    └── types/            # TypeScript types
    ```

    ### Coding Guidelines

    1. **Components**: Keep components small and focused
    2. **Props**: Use TypeScript interfaces for prop types
    3. **State**: Lift state up only when necessary
    4. **Effects**: Clean up side effects in useEffect
    5. **Memoization**: Use `useMemo`/`useCallback` for expensive operations
    6. **Keys**: Always use stable, unique keys in lists
    7. **Testing**: Use React Testing Library for component tests
    """
  end

  def build_rails_best_practices do
    """
    ## Ruby on Rails Best Practices

    ### Core Patterns

    - Follow **MVC** (Model-View-Controller) architecture
    - Use **RESTful** routes and resource-based controllers
    - Leverage **ActiveRecord** for database operations
    - Use **concerns** for shared behavior (DRY principle)
    - Implement **service objects** for complex business logic
    - Use **form objects** for complex form handling
    - Implement **query objects** for complex database queries

    ### Project Structure

    ```
    app/
    ├── controllers/      # Handle HTTP requests
    │   └── concerns/     # Controller concerns
    ├── models/           # ActiveRecord models
    │   └── concerns/     # Model concerns
    ├── views/            # ERB/Haml templates
    │   └── layouts/      # Application layouts
    ├── helpers/          # View helpers
    ├── services/         # Service objects (PORO)
    ├── queries/          # Query objects
    ├── forms/            # Form objects
    ├── jobs/             # ActiveJob background jobs
    ├── mailers/          # ActionMailer email handlers
    ├── channels/         # ActionCable WebSocket channels
    └── serializers/      # JSON serializers (AMS, jbuilder)
    config/
    ├── routes.rb         # Route definitions
    ├── database.yml      # Database configuration
    └── application.rb    # Application configuration
    db/
    ├── migrate/          # Database migrations
    ├── schema.rb         # Current schema snapshot
    └── seeds.rb          # Seed data
    lib/
    └── tasks/            # Custom Rake tasks
    spec/ or test/        # Test files
    ```

    ### Coding Guidelines

    1. **Fat Models, Skinny Controllers**: Move business logic to models, services, or concerns
    2. **Convention over Configuration**: Follow Rails conventions for file naming and structure
    3. **Callbacks**: Use sparingly, prefer explicit method calls for clarity
    4. **Scopes**: Use named scopes for reusable query logic
    5. **Validations**: Model validations for data integrity, form objects for complex validation
    6. **Strong Parameters**: Always use strong params in controllers
    7. **Security**: Protect against CSRF, SQL injection, XSS
    8. **Testing**: RSpec or Minitest, FactoryBot for fixtures, Capybara for integration tests
    9. **Background Jobs**: Use ActiveJob with Sidekiq/GoodJob for async processing
    10. **Database**: Use transactions, avoid N+1 queries with `.includes()`

    ### ActiveRecord Patterns

    ```ruby
    # Named scopes for reusable queries
    scope :active, -> { where(active: true) }
    scope :recent, -> { order(created_at: :desc) }

    # Avoid N+1 with eager loading
    User.includes(:posts, :comments).where(active: true)

    # Use transactions for atomic operations
    ActiveRecord::Base.transaction do
      user.save!
      user.profile.save!
    end
    ```

    ### Service Object Pattern

    ```ruby
    # app/services/user_registration_service.rb
    class UserRegistrationService
      def initialize(params)
        @params = params
      end

      def call
        user = User.new(@params)
        if user.save
          send_welcome_email(user)
          Result.success(user)
        else
          Result.failure(user.errors)
        end
      end
    end
    ```
    """
  end

  def build_sinatra_best_practices do
    """
    ## Sinatra Best Practices

    ### Core Patterns

    - Use **modular style** for larger applications
    - Implement **helpers** for reusable logic
    - Leverage **middleware** for cross-cutting concerns
    - Use **Rack** ecosystem tools (authentication, sessions)
    - Keep routes thin, extract business logic

    ### Project Structure

    ```
    app/
    ├── app.rb            # Main application file
    ├── routes/           # Route modules
    │   ├── users.rb
    │   └── api.rb
    ├── models/           # Data models (Sequel, ROM)
    ├── views/            # ERB/Haml templates
    ├── helpers/          # Helper modules
    ├── services/         # Business logic
    └── config.ru         # Rack config
    public/               # Static assets
    spec/                 # RSpec tests
    ```

    ### Coding Guidelines

    1. **Modular App**: Use `Sinatra::Base` for better organization
    2. **Helpers**: Group related helper methods in modules
    3. **Settings**: Use `configure` blocks for environment-specific config
    4. **Sessions**: Enable and secure sessions properly
    5. **Testing**: Use `rack-test` gem with RSpec

    ### Common Patterns

    ```ruby
    # Modular Sinatra application
    class MyApp < Sinatra::Base
      helpers do
        def current_user
          @current_user ||= User.find(session[:user_id])
        end
      end

      before do
        content_type :json
      end

      get '/users/:id' do
        user = User.find(params[:id])
        user.to_json
      end
    end
    ```
    """
  end

  def build_express_best_practices do
    """
    ## Express.js Best Practices

    ### Core Patterns

    - Use **middleware** for cross-cutting concerns
    - Implement **router modules** for route organization
    - Use **async/await** with proper error handling
    - Leverage **validation libraries** (Joi, Zod, express-validator)
    - Implement proper **error handling middleware**

    ### Project Structure

    ```
    src/
    ├── routes/           # Route definitions
    ├── controllers/      # Request handlers
    ├── services/         # Business logic
    ├── models/           # Database models
    ├── middleware/       # Custom middleware
    ├── utils/            # Helper functions
    ├── config/           # Configuration
    └── app.js            # Express app setup
    ```

    ### Coding Guidelines

    1. **Error Handling**: Use async error handling middleware
    2. **Validation**: Validate all inputs before processing
    3. **Security**: Use helmet, cors, rate limiting
    4. **Logging**: Use structured logging (winston, pino)
    5. **Testing**: Use supertest for API testing
    """
  end

  def build_rust_actix_best_practices do
    """
    ## Actix Web Best Practices

    ### Core Patterns

    - Use **extractors** for request data parsing
    - Implement **middleware** with `wrap()` and `wrap_fn()`
    - Use **application state** for shared resources
    - Leverage **async handlers** for non-blocking operations
    - Implement proper **error types** with `ResponseError`

    ### Project Structure

    ```
    src/
    ├── main.rs           # Application entry point
    ├── routes/           # Route handlers
    ├── models/           # Data models
    ├── handlers/         # Request handlers
    ├── middleware/       # Custom middleware
    ├── errors.rs         # Error types
    ├── config.rs         # Configuration
    └── db.rs             # Database setup
    ```

    ### Coding Guidelines

    1. **Error Handling**: Use `Result` types with custom error types
    2. **Extractors**: Use `web::Path`, `web::Json`, `web::Query`
    3. **State**: Use `web::Data` for shared application state
    4. **Async**: All handlers should be async
    5. **Testing**: Use `actix_web::test` for integration tests
    """
  end

  def build_go_gin_best_practices do
    """
    ## Gin (Go) Best Practices

    ### Core Patterns

    - Use **handler groups** for route organization
    - Implement **middleware** for cross-cutting concerns
    - Use **binding** for request validation
    - Leverage **context** for request-scoped data
    - Implement proper **error handling** with custom responses

    ### Project Structure

    ```
    cmd/
    └── api/
        └── main.go       # Application entry point
    internal/
    ├── handlers/         # HTTP handlers
    ├── models/           # Data models
    ├── services/         # Business logic
    ├── middleware/       # Custom middleware
    ├── repository/       # Database access
    └── config/           # Configuration
    pkg/                  # Reusable packages
    ```

    ### Coding Guidelines

    1. **Error Handling**: Return appropriate HTTP status codes
    2. **Validation**: Use struct tags for binding validation
    3. **Context**: Use `c.Set()` and `c.Get()` for request data
    4. **Middleware**: Use `gin.HandlerFunc` for reusable logic
    5. **Testing**: Use `httptest` and `testify` for testing
    """
  end

  def get_best_practices(framework) when is_binary(framework) do
    case String.downcase(framework) do
      "fastapi" -> build_fastapi_best_practices()
      "django" -> build_django_best_practices()
      "flask" -> build_flask_best_practices()
      "next.js" -> build_nextjs_best_practices()
      "nextjs" -> build_nextjs_best_practices()
      "next" -> build_nextjs_best_practices()
      "react" -> build_react_best_practices()
      "rails" -> build_rails_best_practices()
      "ruby on rails" -> build_rails_best_practices()
      "sinatra" -> build_sinatra_best_practices()
      "express" -> build_express_best_practices()
      "express.js" -> build_express_best_practices()
      "actix" -> build_rust_actix_best_practices()
      "actix-web" -> build_rust_actix_best_practices()
      "gin" -> build_go_gin_best_practices()
      "huma" -> build_go_huma_best_practices()
      "echo" -> build_go_echo_best_practices()
      "chi" -> build_go_chi_best_practices()
      "fiber" -> build_go_fiber_best_practices()
      "go" -> build_go_general_best_practices()
      _ -> nil
    end
  end

  def get_best_practices(_), do: nil

  def get_practices(framework) when is_binary(framework) do
    get_best_practices(framework)
  end

  def get_practices(_), do: nil

  def build_go_huma_best_practices do
    """
    ## Huma Best Practices

    ### Core Patterns

    - Use **OpenAPI-first** design with automatic schema generation
    - Define **operations** with typed input/output structs
    - Leverage **automatic validation** from struct tags
    - Use **middleware** for cross-cutting concerns
    - Implement proper **error handling** with typed errors

    ### Operation Definitions

    ```go
    // Define typed input/output structs
    type GetItemInput struct {
        ID string `path:"id"`
    }

    type GetItemOutput struct {
        Body struct {
            ID   string `json:"id"`
            Name string `json:"name"`
        }
    }

    // Register operation
    huma.Register(api, huma.Operation{
        OperationID: "get-item",
        Method:      http.MethodGet,
        Path:        "/items/{id}",
    }, func(ctx context.Context, input *GetItemInput) (*GetItemOutput, error) {
        // Implementation
    })
    ```

    ### Project Structure

    ```
    cmd/
    └── api/
        └── main.go           # Application entry point
    internal/
    ├── api/              # API operation definitions
    ├── models/           # Data models
    ├── services/         # Business logic
    ├── middleware/       # Custom middleware
    └── repository/       # Database access
    ```

    ### Coding Guidelines

    1. **Validation**: Use struct tags for automatic validation
    2. **Documentation**: Add descriptions to operations for OpenAPI docs
    3. **Error Handling**: Return typed errors for consistent error responses
    4. **Testing**: Use Huma's testing utilities for operation testing
    5. **Middleware**: Use adapters (Chi, Echo, Fiber, Gin) as needed
    """
  end

  def build_go_echo_best_practices do
    """
    ## Echo Best Practices

    ### Core Patterns

    - Use **middleware** for logging, auth, CORS, etc.
    - Implement **custom context** for request-scoped data
    - Use **route groups** for API versioning
    - Leverage **data binding** and **validation**
    - Implement proper **error handling** with HTTPError

    ### Project Structure

    ```
    cmd/
    └── api/
        └── main.go           # Application entry point
    internal/
    ├── handlers/         # HTTP handlers
    ├── models/           # Data models
    ├── services/         # Business logic
    ├── middleware/       # Custom middleware
    └── repository/       # Database access
    ```

    ### Coding Guidelines

    1. **Context**: Use `echo.Context` for request handling
    2. **Binding**: Use `c.Bind()` for request body binding
    3. **Validation**: Use `github.com/go-playground/validator`
    4. **Error Handling**: Use `echo.NewHTTPError()` for error responses
    5. **Testing**: Use `httptest` with Echo's testing utilities
    """
  end

  def build_go_chi_best_practices do
    """
    ## Chi Best Practices

    ### Core Patterns

    - Use **lightweight routing** with Chi's multiplexer
    - Implement **middleware** for cross-cutting concerns
    - Use **URL parameters** with `chi.URLParam()`
    - Leverage **route groups** for API organization
    - Implement proper **context** usage for request data

    ### Project Structure

    ```
    cmd/
    └── api/
        └── main.go           # Application entry point
    internal/
    ├── handlers/         # HTTP handlers
    ├── models/           # Data models
    ├── services/         # Business logic
    ├── middleware/       # Custom middleware
    └── repository/       # Database access
    ```

    ### Coding Guidelines

    1. **Routing**: Use `r.Route()` for route grouping
    2. **Middleware**: Use `r.Use()` for middleware
    3. **Params**: Use `chi.URLParam(r, "id")` for URL parameters
    4. **Response**: Use `render` package for JSON responses
    5. **Testing**: Use `httptest.NewRecorder()` for testing
    """
  end

  def build_go_fiber_best_practices do
    """
    ## Fiber Best Practices

    ### Core Patterns

    - Use **Express-style** routing with Fiber's API
    - Implement **middleware** for logging, auth, CORS, etc.
    - Use **route groups** for API organization
    - Leverage **data binding** with `c.BodyParser()`
    - Implement **error handling** with custom error handlers

    ### Project Structure

    ```
    cmd/
    └── api/
        └── main.go           # Application entry point
    internal/
    ├── handlers/         # HTTP handlers
    ├── models/           # Data models
    ├── services/         # Business logic
    ├── middleware/       # Custom middleware
    └── repository/       # Database access
    ```

    ### Coding Guidelines

    1. **Context**: Use `*fiber.Ctx` for request/response handling
    2. **Binding**: Use `c.BodyParser()` for request body parsing
    3. **Response**: Use `c.JSON()` for JSON responses
    4. **Error Handling**: Use `fiber.NewError()` for error responses
    5. **Performance**: Fiber is optimized for speed - use it for high-performance APIs
    """
  end

  def build_go_general_best_practices do
    """
    ## Go Best Practices

    ### Core Patterns

    - Follow **standard project layout** conventions
    - Use **interfaces** for dependency injection
    - Implement **error handling** with explicit error returns
    - Use **context** for cancellation and timeouts
    - Leverage **goroutines** and **channels** for concurrency

    ### Project Structure

    ```
    cmd/
    └── myapp/
        └── main.go           # Application entry point
    internal/              # Private application code
    ├── handlers/         # HTTP handlers
    ├── models/           # Data models
    ├── services/         # Business logic
    └── repository/       # Database access
    pkg/                   # Public library code
    api/                   # OpenAPI/Swagger specs
    configs/               # Configuration files
    scripts/               # Build and deploy scripts
    ```

    ### Coding Guidelines

    1. **Error Handling**: Always check errors, use `errors.Is()` and `errors.As()`
    2. **Naming**: Use MixedCaps, short variable names for local scope
    3. **Interfaces**: Define small interfaces at the point of use
    4. **Testing**: Use table-driven tests, `*_test.go` files
    5. **Context**: Pass `context.Context` as first parameter
    6. **Documentation**: Use godoc-style comments for public APIs
    7. **Formatting**: Use `gofmt` or `goimports` for code formatting

    ### Common Patterns

    ```go
    // Dependency injection with interfaces
    type Repository interface {
        GetByID(ctx context.Context, id string) (*Entity, error)
    }

    type Service struct {
        repo Repository
    }

    func NewService(repo Repository) *Service {
        return &Service{repo: repo}
    }

    // Error handling
    if err != nil {
        return fmt.Errorf("failed to do something: %w", err)
    }
    ```
    """
  end
end
