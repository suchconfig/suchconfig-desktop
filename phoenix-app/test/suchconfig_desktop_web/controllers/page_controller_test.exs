defmodule SuchConfigDesktopWeb.PageControllerTest do
  use SuchConfigDesktopWeb.ConnCase

  test "GET /welcome", %{conn: conn} do
    conn = get(conn, ~p"/welcome")
    assert html_response(conn, 200) =~ "SuchConfig - Parse Faster!"
  end
end
