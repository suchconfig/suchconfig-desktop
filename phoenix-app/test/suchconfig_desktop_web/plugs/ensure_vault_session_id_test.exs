defmodule SuchConfigDesktopWeb.Plugs.EnsureVaultSessionIdTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  describe "call/2" do
    test "puts vault_session_id in session when missing" do
      conn =
        build_conn()
        |> get("/")

      assert get_session(conn, "vault_session_id") != nil
      assert is_binary(get_session(conn, "vault_session_id"))
    end

    test "does not restore vault_skipped from legacy cookie" do
      conn =
        build_conn()
        |> put_req_header("cookie", "suchconfig_vault_skipped=1")
        |> get("/")

      assert get_session(conn, "vault_skipped") != true
    end
  end
end
