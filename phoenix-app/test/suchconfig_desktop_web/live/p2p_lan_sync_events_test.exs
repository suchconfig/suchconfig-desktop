defmodule SuchConfigDesktopWeb.P2pLanSyncEventsTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktopWeb.P2pLanSyncEvents

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  describe "default_assigns/0" do
    test "includes LAN sync defaults" do
      assigns = P2pLanSyncEvents.default_assigns()
      assert assigns.p2p_lan_sync_enabled == false
      assert assigns.p2p_lan_peers == []
    end
  end

  describe "apply_lan_status/2" do
    test "normalizes peer online state" do
      socket =
        socket(Map.new(P2pLanSyncEvents.default_assigns()))
        |> P2pLanSyncEvents.apply_lan_status(%{
          "enabled" => true,
          "peers" => [
            %{
              "deviceId" => "peer-1",
              "deviceName" => "Studio",
              "online" => true,
              "pinned" => true
            }
          ]
        })

      assert socket.assigns.p2p_lan_sync_enabled
      assert [%{device_id: "peer-1", online: true}] = socket.assigns.p2p_lan_peers
    end
  end

  describe "settings forwarding" do
    test "apply_discovery_update updates peer list" do
      socket = socket(Map.new(P2pLanSyncEvents.default_assigns()))

      socket =
        P2pLanSyncEvents.apply_discovery_update(socket, %{
          "peers" => [
            %{
              "deviceId" => "peer-1",
              "deviceName" => "Studio",
              "online" => true,
              "host" => "192.168.9.100",
              "port" => 63_593,
              "pinned" => true
            }
          ]
        })

      assert [%{device_id: "peer-1", online: true, host: "192.168.9.100", port: 63_593}] =
               socket.assigns.p2p_lan_peers
    end

    test "handle_settings_forward routes discovery updates" do
      socket = socket(Map.new(P2pLanSyncEvents.default_assigns()))

      socket =
        P2pLanSyncEvents.handle_settings_forward(
          socket,
          {:p2p_lan_discovery_update,
           %{
             "peers" => [
               %{
                 "deviceId" => "peer-1",
                 "deviceName" => "Studio",
                 "online" => true,
                 "pinned" => true
               }
             ]
           }}
        )

      assert [%{device_id: "peer-1", online: true}] = socket.assigns.p2p_lan_peers
    end
  end

  describe "handoff_button_visible?/2" do
    test "shows only when LAN sync, vault, peer endpoint, and handoff_ready align" do
      peer = %{
        device_id: "peer-1",
        device_name: "Studio",
        online: true,
        handoff_ready: true,
        host: "192.168.9.188",
        port: 50_528,
        pinned: true
      }

      assigns = %{
        p2p_lan_sync_enabled: true,
        vault_unlocked: true,
        p2p_lan_sync_busy: false,
        p2p_lan_handoff_device_id: nil
      }

      assert P2pLanSyncEvents.handoff_button_visible?(peer, assigns)
      refute P2pLanSyncEvents.handoff_button_visible?(peer, %{assigns | vault_unlocked: false})

      refute P2pLanSyncEvents.handoff_button_visible?(peer, %{
               assigns
               | p2p_lan_sync_enabled: false
             })

      refute P2pLanSyncEvents.handoff_button_visible?(
               Map.put(peer, :handoff_ready, false),
               assigns
             )

      assert P2pLanSyncEvents.handoff_button_visible?(
               Map.merge(peer, %{host: nil, port: nil}),
               assigns
             )

      refute P2pLanSyncEvents.handoff_button_visible?(
               Map.put(peer, :online, false),
               assigns
             )

      refute P2pLanSyncEvents.handoff_button_visible?(
               peer,
               %{assigns | p2p_lan_sync_busy: true, p2p_lan_handoff_device_id: "peer-2"}
             )

      assert P2pLanSyncEvents.handoff_button_visible?(
               peer,
               %{assigns | p2p_lan_sync_busy: true, p2p_lan_handoff_device_id: "peer-1"}
             )
    end
  end

  describe "request_handoff/2" do
    test "rejects when peer is not handoff ready" do
      socket =
        socket(
          Map.merge(P2pLanSyncEvents.default_assigns(), %{
            p2p_lan_sync_enabled: true,
            vault_unlocked: true,
            p2p_lan_peers: [
              %{
                device_id: "peer-1",
                online: true,
                handoff_ready: false,
                host: "192.168.9.188",
                port: 50_528
              }
            ]
          })
        )

      socket = P2pLanSyncEvents.request_handoff(socket, "peer-1")

      assert String.contains?(socket.assigns.p2p_lan_sync_error, "not ready")
      refute socket.assigns.p2p_lan_sync_busy
    end
  end
end
