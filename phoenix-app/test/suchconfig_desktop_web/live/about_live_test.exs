defmodule SuchConfigDesktopWeb.AboutLiveTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @live_opts [on_error: :warn]

  describe "GET /about" do
    test "renders about content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/about", @live_opts)

      html = render(view)

      assert has_element?(view, "#about-live-root")
      assert html =~ "such config"
      assert html =~ "local-first vault"
      assert html =~ "Our vision"
      assert html =~ "One source of truth"
      assert html =~ "Data sovereignty"
      assert html =~ "Local-first"
      assert html =~ "AI-augmented"
      assert has_element?(view, "#about-vision-source-of-truth")
    end
  end
end
