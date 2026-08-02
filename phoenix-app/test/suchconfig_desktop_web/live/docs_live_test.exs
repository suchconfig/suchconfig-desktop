defmodule SuchConfigDesktopWeb.DocsLiveTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Docs.Catalog

  @live_opts [on_error: :warn]

  describe "GET /docs" do
    test "renders docs shell with default vision article", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/docs", @live_opts)

      assert html =~ ~s(id="docs-live-root")
      assert html =~ "Why SuchConfig exists"
      assert html =~ ~s(id="docs-nav-vision")
      assert html =~ ~s(id="docs-nav-trusted-folder")
    end

    test "renders wifi p2p article from route param", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/wifi-p2p-sync", @live_opts)

      html = render(view)
      assert html =~ "WiFi P2P sync"
      assert html =~ "Trusted Folder vs WiFi P2P"
    end

    test "select_doc switches articles", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs", @live_opts)

      html =
        view
        |> element("#docs-nav-wifi-p2p-sync")
        |> render_click()

      assert html =~ "Pair a second computer"
    end

    test "unknown article param falls back to vision", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/not-a-guide", @live_opts)

      assert render(view) =~ "Why SuchConfig exists"
    end
  end

  describe "Catalog" do
    test "lists vision, vault, tools, and sync articles" do
      ids = Catalog.article_ids()
      assert "vision" in ids
      assert "generator" in ids
      assert "project-vault" in ids
      assert "secrets-vault" in ids
      assert "trusted-folder" in ids
      assert "wifi-p2p-sync" in ids
    end
  end

  describe "vision guide" do
    test "renders vision article from route", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/vision", @live_opts)

      html = render(view)
      assert html =~ "local-first"
      assert html =~ "AI-augmented"
      assert html =~ "Data sovereignty"
    end
  end

  describe "vault guides" do
    test "renders project vault article", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/project-vault", @live_opts)

      html = render(view)
      assert html =~ "Project Vault"
      assert html =~ "New project"
      assert html =~ "Secure Archive"
    end

    test "renders secrets vault article", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/secrets-vault", @live_opts)

      html = render(view)
      assert html =~ "Secrets Vault"
      assert html =~ "Login"
      assert html =~ "API key"
    end

    test "nav switches to secrets vault", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs", @live_opts)

      html =
        view
        |> element("#docs-nav-secrets-vault")
        |> render_click()

      assert html =~ "password manager"
    end
  end

  describe "generator guide" do
    test "renders generator article", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs/generator", @live_opts)

      html = render(view)
      assert html =~ "Generator"
      assert html =~ "suchconfig_core"
      assert html =~ "strong_rand_bytes"
      assert html =~ "Gmail"
    end

    test "nav switches to generator", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/docs", @live_opts)

      html =
        view
        |> element("#docs-nav-generator")
        |> render_click()

      assert html =~ "never leaves the device"
      assert html =~ "rejection sampling"
    end
  end
end
