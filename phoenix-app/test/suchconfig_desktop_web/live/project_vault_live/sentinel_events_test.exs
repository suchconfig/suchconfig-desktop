defmodule SuchConfigDesktopWeb.ProjectVaultLive.SentinelEventsTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktopWeb.ProjectVaultLive.SentinelEvents

  defp base_socket(overrides \\ %{}) do
    folder = Map.get(overrides, :folder) || project_folder_fixture()

    path =
      Map.get(overrides, :path) ||
        "/tmp/suchconfig-sentinel-#{System.unique_integer([:positive])}"

    assigns =
      Map.merge(
        %{
          __changed__: %{},
          flash: %{},
          selected_folder_id: folder.id,
          folders: [%{id: folder.id, linked_project_path: path}],
          sentinel_pending_path: path,
          sentinel_pending_folder_id: folder.id,
          sentinel_scanning: false,
          show_sentinel_report_modal: false,
          sentinel_report_card: nil,
          sentinel_error: nil,
          info: nil
        },
        Map.drop(overrides, [:folder, :path])
      )

    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.ProjectVaultLive,
      assigns: assigns
    }
  end

  defp with_sentinel_license(enabled?) do
    previous = Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:suchconfig_desktop, :security_sentinel_license_enabled)
      else
        Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, previous)
      end
    end)

    Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, enabled?)
  end

  defp pushed_events(socket) do
    get_in(socket.private, [:live_temp, :push_events]) || []
  end

  defp pushed?(socket, event) do
    Enum.any?(pushed_events(socket), fn
      [^event, _payload] -> true
      _ -> false
    end)
  end

  describe "start_onboard_scan/3" do
    test "shows upgrade modal and does not scan when license disabled" do
      with_sentinel_license(false)
      folder = project_folder_fixture()
      path = "/tmp/suchconfig-sentinel-upgrade-#{System.unique_integer([:positive])}"
      socket = base_socket(%{folder: folder, path: path})

      next = SentinelEvents.start_onboard_scan(socket, path, folder.id)

      assert next.assigns.show_sentinel_report_modal == true
      refute next.assigns.sentinel_scanning
      assert next.assigns.sentinel_report_card == nil
      refute pushed?(next, "invoke_sentinel_onboard")
    end

    test "starts scan assigns and pushes event when licensed" do
      with_sentinel_license(true)
      folder = project_folder_fixture()
      path = "/tmp/suchconfig-sentinel-ok-#{System.unique_integer([:positive])}"
      socket = base_socket(%{folder: folder, path: path})

      next = SentinelEvents.start_onboard_scan(socket, path, folder.id)

      assert next.assigns.sentinel_scanning == true
      assert next.assigns.sentinel_pending_path == path
      assert next.assigns.sentinel_pending_folder_id == folder.id
      assert pushed?(next, "invoke_sentinel_onboard")
    end
  end

  describe "start_rescan/1" do
    test "shows upgrade modal and does not scan when license disabled" do
      with_sentinel_license(false)
      socket = base_socket()

      next = SentinelEvents.start_rescan(socket)

      assert next.assigns.show_sentinel_report_modal == true
      refute next.assigns.sentinel_scanning
      refute pushed?(next, "invoke_sentinel_rescan")
    end

    test "pushes rescan event when licensed" do
      with_sentinel_license(true)
      folder = project_folder_fixture()
      path = "/tmp/suchconfig-sentinel-rescan-#{System.unique_integer([:positive])}"
      socket = base_socket(%{folder: folder, path: path})

      next = SentinelEvents.start_rescan(socket)

      assert next.assigns.sentinel_scanning == true
      assert pushed?(next, "invoke_sentinel_rescan")
    end
  end
end
