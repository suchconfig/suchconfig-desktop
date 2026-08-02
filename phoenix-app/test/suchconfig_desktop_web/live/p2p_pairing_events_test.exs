defmodule SuchConfigDesktopWeb.P2pPairingEventsTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktopWeb.P2pPairingEvents

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)
    }
  end

  describe "open_modal/1" do
    test "opens at choose step" do
      socket =
        socket(Map.new(P2pPairingEvents.default_assigns()))
        |> P2pPairingEvents.open_modal()

      assert socket.assigns.show_p2p_pairing_modal
      assert socket.assigns.p2p_step == :choose
    end
  end

  describe "apply_status/2" do
    test "normalizes peers list" do
      socket =
        socket(Map.new(P2pPairingEvents.default_assigns()))
        |> P2pPairingEvents.apply_status(%{
          "local_device" => %{"device_name" => "studio"},
          "peers" => [
            %{
              "device_id" => "peer-1",
              "device_name" => "laptop",
              "paired_at" => "2026-01-01T00:00:00Z",
              "pinned" => true
            }
          ]
        })

      assert socket.assigns.p2p_local_device["device_name"] == "studio"
      assert [%{device_id: "peer-1", device_name: "laptop"}] = socket.assigns.p2p_peers
    end
  end

  describe "submit_offer_paste/2" do
    test "reads pasted offer from form params" do
      offer = ~s({"kind":"pairing_offer","short_code":"ABC234"})

      socket =
        socket(Map.new(P2pPairingEvents.default_assigns()))
        |> P2pPairingEvents.submit_offer_paste(offer)

      assert socket.assigns.p2p_busy
      assert socket.assigns.p2p_offer_paste == offer

      push_events = get_in(socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(push_events, fn
               ["p2p_submit_pairing_offer", payload] -> payload[:offer_json] == offer
               _ -> false
             end)
    end

    test "shows error when offer is empty" do
      socket =
        socket(Map.new(P2pPairingEvents.default_assigns()))
        |> P2pPairingEvents.submit_offer_paste("")

      assert socket.assigns.p2p_error =~ "Paste the pairing code"
    end

    test "extracts JSON object from wrapped paste" do
      offer = ~s({"kind":"pairing_offer","short_code":"ABC234"})
      wrapped = "Pairing code:\n#{offer}\n"

      socket =
        socket(Map.new(P2pPairingEvents.default_assigns()))
        |> P2pPairingEvents.submit_offer_paste(wrapped)

      assert socket.assigns.p2p_offer_paste == offer
    end
  end

  describe "handle_host_started/2" do
    test "stores session and qr fields" do
      socket =
        socket(Map.new(P2pPairingEvents.default_assigns()))
        |> P2pPairingEvents.handle_host_started(%{
          "session_id" => "sess-1",
          "short_code" => "ABC234",
          "qr_png_base64" => "png",
          "offer_json" => "{}"
        })

      assert socket.assigns.p2p_session_id == "sess-1"
      assert socket.assigns.p2p_short_code == "ABC234"
      assert socket.assigns.p2p_step == :host
    end
  end
end
