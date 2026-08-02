defmodule SuchConfigDesktopWeb.Sc.P2pPairingModalTest do
  use SuchConfigDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SuchConfigDesktopWeb.Sc.P2pPairingModal

  @offer_json ~s({"kind":"pairing_offer","short_code":"ABC234"})
  @response_json ~s({"kind":"pairing_response"})

  describe "p2p_pairing_modal/1" do
    test "renders nothing when show is false" do
      html =
        render_component(&P2pPairingModal.p2p_pairing_modal/1,
          show: false,
          step: :choose
        )

      refute html =~ "p2p-pairing-modal"
    end

    test "renders choose step with desktop copy/paste hint" do
      html =
        render_component(&P2pPairingModal.p2p_pairing_modal/1,
          show: true,
          step: :choose,
          busy: false
        )

      assert html =~ ~s(id="p2p-pairing-modal")
      assert html =~ ~s(id="p2p-choose-host-btn")
      assert html =~ ~s(id="p2p-choose-guest-btn")
      assert html =~ "copy/paste pairing codes"
      assert html =~ "p2p_choose_host"
    end

    test "renders host step with copy pairing code button" do
      html =
        render_component(&P2pPairingModal.p2p_pairing_modal/1,
          show: true,
          step: :host,
          short_code: "ABC234",
          qr_png_base64: "abc123",
          offer_json: @offer_json,
          response_paste: ""
        )

      assert html =~ ~s(id="p2p-host-qr")
      assert html =~ ~s(id="p2p-copy-offer-btn")
      assert html =~ ~s(id="p2p-offer-json-source")
      assert html =~ ~s(data-copy-target="p2p-offer-json-source")
      assert html =~ "Copy pairing code"
      assert html =~ ~s(id="p2p-complete-initiator-btn")
    end

    test "renders guest paste instructions" do
      html =
        render_component(&P2pPairingModal.p2p_pairing_modal/1,
          show: true,
          step: :guest_paste
        )

      assert html =~ ~s(id="p2p-offer-paste-form")
      assert html =~ ~s(id="p2p-offer-paste")
      assert html =~ "Copy pairing code"
      assert html =~ "starting on this computer"
      assert html =~ ~s(phx-submit="p2p_submit_offer_paste")
    end

    test "renders guest share response step with copy button" do
      html =
        render_component(&P2pPairingModal.p2p_pairing_modal/1,
          show: true,
          step: :guest_share_response,
          response_json: @response_json,
          remote_device_name: "studio-mac"
        )

      assert html =~ ~s(id="p2p-copy-response-btn")
      assert html =~ ~s(id="p2p-response-json-source")
      assert html =~ ~s(data-copy-target="p2p-response-json-source")
      assert html =~ "Copy response for other device"
      assert html =~ "studio-mac"
    end

    test "renders error state" do
      html =
        render_component(&P2pPairingModal.p2p_pairing_modal/1,
          show: true,
          step: :guest_paste,
          error: "Invalid pairing code."
        )

      assert html =~ "Invalid pairing code."
    end
  end
end
