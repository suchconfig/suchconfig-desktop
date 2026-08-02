defmodule SuchConfigDesktopWeb.ProjectVaultLive.FolderEventsTest do
  use SuchConfigDesktop.DataCase, async: false

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktopWeb.ProjectVaultLive.FolderEvents

  defp base_socket(overrides) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          flash: %{},
          folders: [],
          selected_folder_id: nil,
          notes: [],
          vault_items: [],
          vault_item_ui_enabled?: true,
          security_mode: "global_passkey",
          folder_name: "",
          folder_description: "",
          folder_tags: "",
          new_folder_link_path: nil,
          new_folder_link_stage: :idle,
          new_folder_link_error: nil,
          new_folder_run_sentinel: false,
          show_new_folder_modal: true,
          folder_sidebar_expanded: false,
          info: nil,
          error: nil,
          new_note_form_highlight: false
        },
        overrides
      )

    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.ProjectVaultLive,
      assigns: assigns
    }
  end

  describe "create/2 with optional project link" do
    setup do
      previous_broker = Application.get_env(:suchconfig_desktop, :local_broker_license_enabled)

      previous_sentinel =
        Application.get_env(:suchconfig_desktop, :security_sentinel_license_enabled)

      on_exit(fn ->
        restore_env(:local_broker_license_enabled, previous_broker)
        restore_env(:security_sentinel_license_enabled, previous_sentinel)
      end)

      :ok
    end

    defp restore_env(key, previous) do
      if is_nil(previous) do
        Application.delete_env(:suchconfig_desktop, key)
      else
        Application.put_env(:suchconfig_desktop, key, previous)
      end
    end

    test "links project path when provided and does not require sentinel" do
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, true)
      path = "/tmp/suchconfig-new-project-link-#{System.unique_integer([:positive])}"
      name = "Linked Create #{System.unique_integer([:positive])}"

      socket =
        base_socket(%{
          new_folder_link_path: path,
          new_folder_link_stage: :ready,
          new_folder_run_sentinel: false
        })

      assert {:noreply, next} =
               FolderEvents.create(
                 %{
                   "folder_name" => name,
                   "folder_description" => "",
                   "folder_tags" => ""
                 },
                 socket
               )

      folder = Enum.find(next.assigns.folders, &(&1.name == name))
      assert folder
      assert folder.linked_project_path == path
      assert next.assigns.info =~ "linked"
      refute next.assigns[:sentinel_scanning]
    end

    test "does not run sentinel for free plan even when checkbox is set" do
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, false)
      path = "/tmp/suchconfig-free-sentinel-#{System.unique_integer([:positive])}"
      name = "Free Create #{System.unique_integer([:positive])}"

      socket =
        base_socket(%{
          new_folder_link_path: path,
          new_folder_link_stage: :ready,
          new_folder_run_sentinel: true
        })

      assert {:noreply, next} =
               FolderEvents.create(
                 %{
                   "folder_name" => name,
                   "folder_description" => "",
                   "folder_tags" => "",
                   "run_sentinel_scan" => "true"
                 },
                 socket
               )

      folder = ProjectVault.get_project_folder!(next.assigns.selected_folder_id)
      assert folder.linked_project_path == path
      refute next.assigns[:sentinel_scanning]
    end

    test "does not run sentinel when Broker is licensed but Sentinel is not" do
      Application.put_env(:suchconfig_desktop, :local_broker_license_enabled, true)
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, false)
      path = "/tmp/suchconfig-broker-only-sentinel-#{System.unique_integer([:positive])}"
      name = "Broker Only #{System.unique_integer([:positive])}"

      socket =
        base_socket(%{
          new_folder_link_path: path,
          new_folder_link_stage: :ready,
          new_folder_run_sentinel: true
        })

      assert {:noreply, next} =
               FolderEvents.create(
                 %{
                   "folder_name" => name,
                   "folder_description" => "",
                   "folder_tags" => "",
                   "run_sentinel_scan" => "true"
                 },
                 socket
               )

      refute next.assigns[:sentinel_scanning]
      refute next.assigns[:show_sentinel_report_modal]
    end

    test "starts sentinel onboard scan for Pro when checkbox is checked" do
      Application.put_env(:suchconfig_desktop, :security_sentinel_license_enabled, true)
      path = "/tmp/suchconfig-pro-sentinel-#{System.unique_integer([:positive])}"
      name = "Pro Sentinel Create #{System.unique_integer([:positive])}"

      socket =
        base_socket(%{
          new_folder_link_path: path,
          new_folder_link_stage: :ready,
          new_folder_run_sentinel: true
        })

      assert {:noreply, next} =
               FolderEvents.create(
                 %{
                   "folder_name" => name,
                   "folder_description" => "",
                   "folder_tags" => "",
                   "run_sentinel_scan" => "true"
                 },
                 socket
               )

      assert next.assigns.sentinel_scanning == true
      assert next.assigns.sentinel_pending_path == path
      assert next.assigns.sentinel_pending_folder_id == next.assigns.selected_folder_id
    end
  end
end
