defmodule SuchConfigDesktopWeb.RouterTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  describe "browser pipeline" do
    test "GET / returns 200 and renders app root", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert response(conn, 200)
      assert conn.resp_body =~ "app-live-root"
    end

    test "GET /about returns 200 and about LiveView root", %{conn: conn} do
      conn = get(conn, ~p"/about")

      assert response(conn, 200)
      assert conn.resp_body =~ "about-live-root"
    end

    test "GET /docs returns 200 and docs LiveView root", %{conn: conn} do
      conn = get(conn, ~p"/docs")

      assert response(conn, 200)
      assert conn.resp_body =~ "docs-live-root"
    end

    test "GET /welcome returns 200", %{conn: conn} do
      conn = get(conn, ~p"/welcome")

      assert response(conn, 200)
    end

    test "GET /project-manager returns 200", %{conn: conn} do
      conn = get(conn, ~p"/project-manager")

      assert response(conn, 200)
    end

    test "GET /project-vault returns 200", %{conn: conn} do
      conn = get(conn, ~p"/project-vault")

      assert response(conn, 200)
      assert conn.resp_body =~ "project-vault-root"
    end
  end
end
