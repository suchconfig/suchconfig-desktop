defmodule SuchConfigDesktopWeb.Router do
  use SuchConfigDesktopWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_cookies)
    plug(SuchConfigDesktopWeb.Plugs.EnsureVaultSessionId)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SuchConfigDesktopWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", SuchConfigDesktopWeb do
    pipe_through(:browser)

    # Main desktop app with navigation (root route)
    live("/", AppLive, :index)
    live("/about", AboutLive, :index)
    live("/docs", DocsLive, :index)
    live("/docs/:article", DocsLive, :show)

    # Welcome page (for testing)
    get("/welcome", PageController, :home)

    get("/wizard", PageController, :redirect_wizard)
    live("/project-vault", ProjectVaultLive, :index)
    live("/project-manager", ProjectVaultLive, :index)
    live("/secrets-vault", SecretsVaultLive, :index)
  end

  # Other scopes may use custom stacks.
  # scope "/api", SuchConfigDesktopWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:suchconfig_desktop, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: SuchConfigDesktopWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
