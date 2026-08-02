defmodule SuchConfigDesktopWeb.Sc.P2pPairingModal do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  attr :show, :boolean, required: true
  attr :step, :atom, required: true
  attr :busy, :boolean, default: false
  attr :error, :string, default: nil
  attr :short_code, :string, default: nil
  attr :qr_png_base64, :string, default: nil
  attr :offer_json, :string, default: nil
  attr :response_json, :string, default: nil
  attr :remote_device_name, :string, default: nil
  attr :local_device_name, :string, default: nil
  attr :offer_paste, :string, default: ""
  attr :response_paste, :string, default: ""
  attr :copy_hint, :string, default: nil

  def p2p_pairing_modal(assigns) do
    ~H"""
    <.modal_shell
      :if={@show}
      id="p2p-pairing-modal"
      show={@show}
      on_cancel="dismiss_p2p_pairing_modal"
      size="md"
    >
      <.modal_head title="Pair a device" on_close="dismiss_p2p_pairing_modal" />
      <.modal_body>
        <div :if={@step == :choose} class="col" style="gap: 14px">
          <p class="muted" style="margin: 0">
            Link two SuchConfig desktops on the same Wi‑Fi. No cloud relay — pairing only trusts the other
            computer before any vault sync.
          </p>
          <p class="muted" style="margin: 0; font-size: 13px">
            Use a QR code <span class="strong">or</span>
            copy/paste pairing codes (best when both machines are laptops without a camera).
          </p>
          <button
            type="button"
            id="p2p-choose-host-btn"
            phx-click="p2p_choose_host"
            class="btn sm primary"
            disabled={@busy}
          >
            I’m starting on this computer
          </button>
          <button
            type="button"
            id="p2p-choose-guest-btn"
            phx-click="p2p_choose_guest"
            class="btn sm"
            disabled={@busy}
          >
            I’m joining from this computer
          </button>
        </div>

        <div :if={@step == :host} class="col" style="gap: 14px">
          <p class="muted" style="margin: 0">
            On your <span class="strong">other</span>
            computer, choose <span class="strong">I’m joining from this computer</span>
            and paste the pairing code you copy below (or scan this QR if you can).
          </p>
          <ol class="muted" style="margin: 0; padding-left: 20px; font-size: 13px">
            <li>Copy the pairing code (button below).</li>
            <li>
              Send it to the other machine — Messages, AirDrop, email, or any channel you trust.
            </li>
            <li>
              When the other device confirms, copy its <span class="strong">response code</span>
              back here.
            </li>
          </ol>
          <div :if={@busy and is_nil(@qr_png_base64)} class="muted">Generating pairing code…</div>
          <div :if={is_binary(@qr_png_base64) and @qr_png_base64 != ""} style="text-align: center">
            <img
              id="p2p-host-qr"
              src={"data:image/png;base64,#{@qr_png_base64}"}
              alt="Pairing QR code"
              width="240"
              height="240"
              style="border-radius: 8px; border: 1px solid var(--border)"
            />
            <p class="muted" style="margin: 8px 0 0; font-size: 12px">
              Optional — same data as Copy pairing code
            </p>
          </div>
          <div
            :if={is_binary(@short_code) and @short_code != ""}
            class="row"
            style="justify-content: center; gap: 8px"
          >
            <span class="muted">Verify on other device</span>
            <span class="mono strong" id="p2p-short-code">{@short_code}</span>
          </div>
          <textarea
            :if={is_binary(@offer_json) and @offer_json != ""}
            id="p2p-offer-json-source"
            class="sr-only"
            readonly
            aria-hidden="true"
            tabindex="-1"
          >{@offer_json}</textarea>
          <div class="row" style="gap: 10px; flex-wrap: wrap">
            <button
              :if={is_binary(@offer_json) and @offer_json != ""}
              type="button"
              id="p2p-copy-offer-btn"
              class="btn sm primary"
              phx-hook="CopyButton"
              data-copy-target="p2p-offer-json-source"
              data-copy-event="p2p_pairing_copied"
              data-copy-payload={Jason.encode!(%{which: "offer"})}
            >
              <.icon name={if(@copy_hint == "offer", do: "check", else: "copy")} size={13} />
              {if @copy_hint == "offer", do: "Copied pairing code", else: "Copy pairing code"}
            </button>
          </div>
          <p
            :if={@copy_hint == "offer"}
            id="p2p-copy-offer-status"
            class="muted"
            style="font-size: 13px"
            role="status"
          >
            Pairing code copied — paste it on the other computer.
          </p>
          <form
            id="p2p-response-paste-form"
            phx-submit="p2p_complete_initiator"
            class="col"
            style="gap: 14px"
          >
            <label class="col" style="gap: 6px">
              <span class="muted">Response from other device</span>
              <p class="muted" style="margin: 0; font-size: 12px">
                After the other computer confirms, use
                <span class="strong">Copy response for other device</span>
                there and paste below.
              </p>
              <textarea
                id="p2p-response-paste"
                name="response_paste"
                phx-change="p2p_update_response_paste"
                phx-debounce="200"
                rows="4"
                class="input"
                placeholder="Paste the response code from the joining computer"
              >{@response_paste}</textarea>
            </label>
            <button
              type="submit"
              id="p2p-complete-initiator-btn"
              class="btn sm primary"
              disabled={@busy}
            >
              {if @busy, do: "Completing…", else: "Complete pairing"}
            </button>
          </form>
        </div>

        <div :if={@step == :guest_paste} class="col" style="gap: 14px">
          <p class="muted" style="margin: 0">
            Paste the pairing code from your <span class="strong">other</span> computer.
          </p>
          <ol class="muted" style="margin: 0; padding-left: 20px; font-size: 13px">
            <li>
              On the other machine: Settings → Pair a device → <span class="strong">I’m starting on this computer</span>.
            </li>
            <li>Tap <span class="strong">Copy pairing code</span> (or scan its QR).</li>
            <li>Paste here and continue.</li>
          </ol>
          <form
            id="p2p-offer-paste-form"
            phx-submit="p2p_submit_offer_paste"
            class="col"
            style="gap: 14px"
          >
            <label class="col" style="gap: 6px">
              <span class="muted">Pairing code from other device</span>
              <textarea
                id="p2p-offer-paste"
                name="offer_paste"
                phx-change="p2p_update_offer_paste"
                phx-debounce="200"
                rows="6"
                class="input"
                placeholder="Paste the full pairing code — one block of text from Copy pairing code"
              >{@offer_paste}</textarea>
            </label>
            <button
              type="submit"
              id="p2p-submit-offer-btn"
              class="btn sm primary"
              disabled={@busy}
            >
              {if @busy, do: "Checking…", else: "Continue"}
            </button>
          </form>
        </div>

        <div :if={@step == :guest_confirm} class="col" style="gap: 14px">
          <div class="archive-callout">
            <.icon name="lock" size={16} style="color: var(--plum)" />
            <p class="muted" style="margin: 0">
              Pair with <span class="strong">{@remote_device_name || "another device"}</span>?
              Only confirm if you started this on a computer you trust on your Wi‑Fi.
            </p>
          </div>
          <div :if={is_binary(@short_code) and @short_code != ""} class="row" style="gap: 8px">
            <span class="muted">Their verify code</span>
            <span class="mono strong">{@short_code}</span>
            <span class="muted" style="font-size: 12px">
              — should match the code shown on the other device
            </span>
          </div>
          <button
            type="button"
            id="p2p-confirm-responder-btn"
            phx-click="p2p_confirm_responder"
            class="btn sm primary"
            disabled={@busy}
          >
            {if @busy, do: "Pairing…", else: "Confirm pairing"}
          </button>
        </div>

        <div :if={@step == :guest_share_response} class="col" style="gap: 14px">
          <div class="archive-callout">
            <.icon name="check" size={16} style="color: var(--ok)" />
            <p class="muted" style="margin: 0">
              This device is paired locally. Send the <span class="strong">response code</span>
              below to <span class="strong">{@remote_device_name || "the other computer"}</span>
              so it can finish pairing too.
            </p>
          </div>
          <ol class="muted" style="margin: 0; padding-left: 20px; font-size: 13px">
            <li>Copy the response code (button below).</li>
            <li>Send it to the starting computer (Messages, AirDrop, email, etc.).</li>
            <li>
              There: paste into <span class="strong">Response from other device</span>
              → Complete pairing.
            </li>
          </ol>
          <div :if={is_binary(@qr_png_base64) and @qr_png_base64 != ""} style="text-align: center">
            <img
              id="p2p-guest-response-qr"
              src={"data:image/png;base64,#{@qr_png_base64}"}
              alt="Pairing response QR code"
              width="240"
              height="240"
              style="border-radius: 8px; border: 1px solid var(--border)"
            />
            <p class="muted" style="margin: 8px 0 0; font-size: 12px">
              Optional — same data as Copy response code
            </p>
          </div>
          <textarea
            :if={is_binary(@response_json) and @response_json != ""}
            id="p2p-response-json-source"
            class="sr-only"
            readonly
            aria-hidden="true"
            tabindex="-1"
          >{@response_json}</textarea>
          <div class="row" style="gap: 10px; flex-wrap: wrap">
            <button
              :if={is_binary(@response_json) and @response_json != ""}
              type="button"
              id="p2p-copy-response-btn"
              class="btn sm primary"
              phx-hook="CopyButton"
              data-copy-target="p2p-response-json-source"
              data-copy-event="p2p_pairing_copied"
              data-copy-payload={Jason.encode!(%{which: "response"})}
            >
              <.icon name={if(@copy_hint == "response", do: "check", else: "copy")} size={13} />
              {if @copy_hint == "response",
                do: "Copied response code",
                else: "Copy response for other device"}
            </button>
          </div>
          <p
            :if={@copy_hint == "response"}
            id="p2p-copy-response-status"
            class="muted"
            style="font-size: 13px"
            role="status"
          >
            Response code copied — paste it on the starting computer.
          </p>
          <button type="button" phx-click="dismiss_p2p_pairing_modal" class="btn sm">
            Done — I sent the response code
          </button>
        </div>

        <div :if={@step == :success} class="col" style="gap: 14px">
          <div class="archive-callout">
            <.icon name="check" size={16} style="color: var(--ok)" />
            <p class="muted" style="margin: 0">
              Paired with <span class="strong">{@remote_device_name || "your other device"}</span>.
              Both computers can use this trust for Wi‑Fi sync once discovery ships.
            </p>
          </div>
          <button type="button" phx-click="dismiss_p2p_pairing_modal" class="btn sm primary">
            Done
          </button>
        </div>

        <div :if={is_binary(@error) and @error != ""} class="vault-flash err" style="margin-top: 12px">
          {@error}
        </div>
      </.modal_body>
    </.modal_shell>
    """
  end
end
