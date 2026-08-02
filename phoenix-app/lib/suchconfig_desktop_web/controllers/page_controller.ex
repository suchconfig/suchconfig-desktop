defmodule SuchConfigDesktopWeb.PageController do
  use SuchConfigDesktopWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def redirect_wizard(conn, _params) do
    Phoenix.Controller.redirect(conn, to: ~p"/project-vault")
  end
end
