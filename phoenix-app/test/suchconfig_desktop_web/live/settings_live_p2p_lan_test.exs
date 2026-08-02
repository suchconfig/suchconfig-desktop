defmodule SuchConfigDesktopWeb.SettingsLiveP2pLanTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @live_opts [on_error: :warn]

  defp live_on_settings(conn) do
    conn = get(conn, ~p"/")
    {:ok, view, _html} = live(conn, "/", @live_opts)
    view |> element("button", "Proceed without unlocking") |> render_click()
    view |> element("#rail-settings-btn") |> render_click()
    view
  end

  test "settings p2p card exposes LAN sync toggle and peer list ids", %{conn: conn} do
    view = live_on_settings(conn)
    html = render(view)

    assert html =~ ~s(id="settings-p2p-devices-card")
    assert html =~ ~s(id="settings-p2p-lan-sync-toggle")
    assert html =~ ~s(id="settings-p2p-lan-toggle-row")
    assert html =~ ~s(phx-click="p2p_toggle_lan_sync")
  end

  test "settings storage card shows live sqlite summary", %{conn: conn} do
    view = live_on_settings(conn)

    assert has_element?(view, "#settings-storage-card")
    assert has_element?(view, "#settings-storage-size")
    assert has_element?(view, "#settings-storage-breakdown")

    html = render(view)
    refute html =~ "90 days"
    assert html =~ "on disk"
    assert html =~ "secure note"
  end
end
