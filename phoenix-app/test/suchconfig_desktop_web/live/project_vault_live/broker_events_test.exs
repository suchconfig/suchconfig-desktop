defmodule SuchConfigDesktopWeb.ProjectVaultLive.BrokerEventsTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktopWeb.ProjectVaultLive.BrokerEvents

  defp base_socket(overrides \\ %{}) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          flash: %{},
          selected_folder_id: nil,
          folders: [],
          broker_project_enabled: false,
          broker_scope_id: "",
          broker_allowed_domains: "",
          broker_services: [],
          broker_cli_snippet: "",
          broker_snippet_copied: false,
          local_broker_license_enabled?: false,
          show_local_broker_modal: false,
          info: nil,
          error: nil
        },
        overrides
      )

    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.ProjectVaultLive,
      assigns: assigns
    }
  end

  defp with_license(enabled?) do
    previous = Application.get_env(:suchconfig_desktop, :local_broker_license_enabled)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:suchconfig_desktop, :local_broker_license_enabled)
      else
        Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, previous)
      end
    end)

    Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, enabled?)
  end

  describe "assign_broker_state/1" do
    test "loads folder broker fields when licensed" do
      with_license(true)
      folder = project_folder_fixture()

      assert {:ok, _} =
               ProjectVault.update_project_broker(folder, %{
                 broker_enabled: true,
                 broker_scope_id: "demo-scope",
                 broker_allowed_domains: "localhost"
               })

      socket =
        base_socket(%{selected_folder_id: folder.id})
        |> BrokerEvents.assign_broker_state()

      assert socket.assigns.local_broker_license_enabled?
      assert socket.assigns.broker_project_enabled
      assert socket.assigns.broker_scope_id == "demo-scope"
      assert socket.assigns.broker_allowed_domains == "localhost"
      assert socket.assigns.broker_cli_snippet =~ "demo-scope"
      refute socket.assigns.broker_snippet_copied
    end

    test "clears broker assigns when no folder selected" do
      with_license(true)

      socket = BrokerEvents.assign_broker_state(base_socket())

      assert socket.assigns.local_broker_license_enabled?
      refute socket.assigns.broker_project_enabled
      assert socket.assigns.broker_scope_id == ""
      assert socket.assigns.broker_cli_snippet == ""
    end
  end

  describe "open_local_broker_modal/2" do
    test "opens modal when a folder is selected" do
      folder = project_folder_fixture()
      socket = base_socket(%{selected_folder_id: folder.id})

      assert {:noreply, opened} = BrokerEvents.open_local_broker_modal(%{}, socket)
      assert opened.assigns.show_local_broker_modal
    end

    test "reloads broker settings for the selected project" do
      with_license(true)

      {:ok, folder} =
        ProjectVault.update_project_broker(project_folder_fixture().id, %{
          broker_enabled: true,
          broker_scope_id: "project-a-scope",
          broker_allowed_domains: "api.example.com"
        })

      socket =
        base_socket(%{
          selected_folder_id: folder.id,
          broker_project_enabled: false,
          broker_scope_id: "",
          broker_allowed_domains: ""
        })

      assert {:noreply, opened} = BrokerEvents.open_local_broker_modal(%{}, socket)
      assert opened.assigns.show_local_broker_modal
      assert opened.assigns.broker_project_enabled
      assert opened.assigns.broker_scope_id == "project-a-scope"
      assert opened.assigns.broker_allowed_domains == "api.example.com"
    end

    test "requires a selected folder" do
      assert {:noreply, socket} = BrokerEvents.open_local_broker_modal(%{}, base_socket())
      refute socket.assigns.show_local_broker_modal
      assert socket.assigns.error =~ "Select a project folder"
    end
  end

  describe "close_local_broker_modal/2" do
    test "closes the modal" do
      socket = base_socket(%{show_local_broker_modal: true})

      assert {:noreply, closed} = BrokerEvents.close_local_broker_modal(%{}, socket)
      refute closed.assigns.show_local_broker_modal
    end
  end

  describe "toggle_project_broker/2" do
    test "enables and disables broker on the selected folder" do
      with_license(true)
      folder = project_folder_fixture()

      socket = base_socket(%{selected_folder_id: folder.id, broker_project_enabled: false})

      assert {:noreply, enabled_socket} = BrokerEvents.toggle_project_broker(%{}, socket)
      assert enabled_socket.assigns.broker_project_enabled
      assert enabled_socket.assigns.info =~ "enabled"
      assert ProjectVault.project_broker_enabled?(folder.id)

      assert {:noreply, disabled_socket} =
               BrokerEvents.toggle_project_broker(%{}, enabled_socket)

      refute disabled_socket.assigns.broker_project_enabled
      assert disabled_socket.assigns.info =~ "disabled"
      refute ProjectVault.project_broker_enabled?(folder.id)
    end

    test "refuses when license is off" do
      with_license(false)
      folder = project_folder_fixture()
      socket = base_socket(%{selected_folder_id: folder.id})

      assert {:noreply, socket} = BrokerEvents.toggle_project_broker(%{}, socket)
      assert socket.assigns.error =~ "Personal Pro"
    end

    test "refuses when no folder selected" do
      with_license(true)
      socket = base_socket()

      assert {:noreply, socket} = BrokerEvents.toggle_project_broker(%{}, socket)
      assert socket.assigns.error =~ "Select a project folder"
    end
  end

  describe "broker_form_change/2" do
    test "updates assigns and regenerates CLI snippet" do
      socket = base_socket()

      assert {:noreply, socket} =
               BrokerEvents.broker_form_change(
                 %{
                   "broker_scope_id" => "suchconfig-api",
                   "broker_allowed_domains" => "127.0.0.1, localhost"
                 },
                 socket
               )

      assert socket.assigns.broker_scope_id == "suchconfig-api"
      assert socket.assigns.broker_allowed_domains == "127.0.0.1, localhost"
      assert socket.assigns.broker_cli_snippet =~ "suchconfig-api"
      refute socket.assigns.broker_snippet_copied
    end
  end

  describe "save_broker_scope/2" do
    test "persists scope fields and keeps enablement from checkbox" do
      with_license(true)
      folder = project_folder_fixture()
      socket = base_socket(%{selected_folder_id: folder.id, broker_project_enabled: false})

      assert {:noreply, socket} =
               BrokerEvents.save_broker_scope(
                 %{
                   "broker_scope_id" => " suchconfig-api ",
                   "broker_allowed_domains" => " api.github.com ",
                   "broker_enabled" => "true"
                 },
                 socket
               )

      assert socket.assigns.info =~ "saved"
      assert socket.assigns.broker_project_enabled
      assert socket.assigns.broker_scope_id == "suchconfig-api"
      assert socket.assigns.broker_allowed_domains == "api.github.com"
      assert socket.assigns.broker_cli_snippet =~ "suchconfig-api"

      assert {:ok, scope} = ProjectVault.broker_scope_for_folder(folder.id)
      assert scope.enabled
      assert scope.scope_id == "suchconfig-api"
      assert scope.allowed_domains == "api.github.com"
    end

    test "refuses when license is off" do
      with_license(false)
      folder = project_folder_fixture()
      socket = base_socket(%{selected_folder_id: folder.id})

      assert {:noreply, socket} =
               BrokerEvents.save_broker_scope(%{"broker_scope_id" => "x"}, socket)

      assert socket.assigns.error =~ "Personal Pro"
    end

    test "persists service rules into folder and Mode B manifest" do
      with_license(true)
      folder = project_folder_fixture()
      socket = base_socket(%{selected_folder_id: folder.id, broker_project_enabled: true})

      assert {:noreply, socket} =
               BrokerEvents.save_broker_scope(
                 %{
                   "broker_scope_id" => "svc-scope",
                   "broker_allowed_domains" => "httpbin.org",
                   "broker_enabled" => "true",
                   "services" => %{
                     "0" => %{
                       "name" => "httpbin",
                       "host" => "httpbin.org",
                       "placeholder" => "__HTTPBIN_TOKEN__",
                       "inject_as" => "bearer"
                     }
                   }
                 },
                 socket
               )

      assert length(socket.assigns.broker_services) == 1
      assert hd(socket.assigns.broker_services)["name"] == "httpbin"

      assert {:ok, scope} = ProjectVault.broker_scope_for_folder(folder.id)

      assert scope.services == [
               %{
                 "name" => "httpbin",
                 "host" => "httpbin.org",
                 "placeholder" => "__HTTPBIN_TOKEN__",
                 "inject_as" => "bearer"
               }
             ]

      assert {:ok, manifest} = ProjectVault.broker_scope_manifest_for_folder(folder.id)
      payload = ProjectVault.manifest_to_json_map(manifest)
      assert payload["services"] == scope.services
      refute Jason.encode!(payload) =~ "secret"
    end
  end

  describe "add_broker_service/2 and remove_broker_service/2" do
    test "adds and removes draft service rows" do
      socket = base_socket(%{broker_services: []})

      assert {:noreply, added} = BrokerEvents.add_broker_service(%{}, socket)
      assert length(added.assigns.broker_services) == 1

      assert {:noreply, removed} =
               BrokerEvents.remove_broker_service(%{"index" => "0"}, added)

      assert removed.assigns.broker_services == []
    end
  end

  describe "copy_broker_cli_snippet/2" do
    test "errors when scope snippet is empty" do
      socket = base_socket(%{broker_cli_snippet: ""})

      assert {:noreply, socket} = BrokerEvents.copy_broker_cli_snippet(%{}, socket)
      assert socket.assigns.error =~ "scope id"
      refute socket.assigns.broker_snippet_copied
    end
  end

  describe "start_project_broker/2" do
    test "pushes invoke_broker_start when manifest export succeeds" do
      with_license(true)
      folder = project_folder_fixture()

      assert {:ok, _} =
               ProjectVault.update_project_broker(folder, %{
                 broker_enabled: true,
                 broker_scope_id: "desktop-scope",
                 broker_allowed_domains: "httpbin.org"
               })

      socket =
        base_socket(%{
          selected_folder_id: folder.id,
          vault_password: "broker-events-test-password"
        })

      assert {:noreply, socket} = BrokerEvents.start_project_broker(%{}, socket)
      assert socket.assigns.broker_starting

      assert [["invoke_broker_start", payload]] = pushed_events(socket)
      assert payload.scope_id == "desktop-scope"
      assert payload.manifest["scope_id"] == "desktop-scope"
      assert payload.manifest["enabled"] == true
      assert payload.manifest["allowed_domains"] == ["httpbin.org"]
      assert payload.manifest["services"] == []
      assert payload.enable_proxy == false
    end

    test "errors when broker is disabled on folder" do
      with_license(true)
      folder = project_folder_fixture()
      socket = base_socket(%{selected_folder_id: folder.id})

      assert {:noreply, socket} = BrokerEvents.start_project_broker(%{}, socket)
      assert socket.assigns.error =~ "Enable Local Broker"
    end
  end

  describe "toggle_broker_proxy/2" do
    test "enables proxy while broker is stopped" do
      assert {:noreply, socket} =
               BrokerEvents.toggle_broker_proxy(
                 %{"value" => "true"},
                 base_socket(%{broker_running: false, broker_proxy_enabled: false})
               )

      assert socket.assigns.broker_proxy_enabled
    end

    test "refuses mode changes while broker is running" do
      assert {:noreply, socket} =
               BrokerEvents.toggle_broker_proxy(
                 %{"value" => "true"},
                 base_socket(%{broker_running: true, broker_proxy_enabled: false})
               )

      refute socket.assigns.broker_proxy_enabled
      assert socket.assigns.error =~ "Stop the Broker"
    end
  end

  describe "stop_project_broker/2" do
    test "pushes invoke_broker_stop when licensed" do
      with_license(true)

      assert {:noreply, socket} =
               BrokerEvents.stop_project_broker(%{}, base_socket(%{broker_running: true}))

      assert socket.assigns.broker_stopping

      assert [["invoke_broker_stop", _payload]] = pushed_events(socket)
    end
  end

  describe "broker_stop_result/2" do
    test "marks broker stopped from sidecar payload" do
      assert {:noreply, socket} =
               BrokerEvents.broker_stop_result(
                 %{
                   "running" => false,
                   "scope_id" => "",
                   "socket_path" => "/tmp/broker.sock"
                 },
                 base_socket(%{broker_running: true, broker_stopping: true})
               )

      refute socket.assigns.broker_stopping
      refute socket.assigns.broker_running
      assert socket.assigns.broker_socket_path == "/tmp/broker.sock"
    end
  end

  describe "broker_start_result/2" do
    test "marks broker running from sidecar payload" do
      assert {:noreply, socket} =
               BrokerEvents.broker_start_result(
                 %{
                   "running" => true,
                   "scope_id" => "desktop-scope",
                   "socket_path" => "/tmp/broker.sock"
                 },
                 base_socket(%{broker_starting: true})
               )

      refute socket.assigns.broker_starting
      assert socket.assigns.broker_running
      assert socket.assigns.broker_runtime_scope_id == "desktop-scope"
      assert socket.assigns.broker_socket_path == "/tmp/broker.sock"
    end
  end

  defp pushed_events(socket) do
    get_in(socket.private, [:live_temp, :push_events]) || []
  end
end
