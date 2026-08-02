defmodule SuchConfigDesktopWeb.P2pPairingEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3, push_event: 3]

  def default_assigns do
    [
      show_p2p_pairing_modal: false,
      p2p_step: :choose,
      p2p_busy: false,
      p2p_error: nil,
      p2p_session_id: nil,
      p2p_short_code: nil,
      p2p_qr_png_base64: nil,
      p2p_offer_json: nil,
      p2p_response_json: nil,
      p2p_offer_paste: "",
      p2p_response_paste: "",
      p2p_remote_device_name: nil,
      p2p_remote_device_id: nil,
      p2p_local_device: nil,
      p2p_peers: [],
      p2p_copy_hint: nil,
      p2p_success_role: nil
    ]
  end

  def on_mount_connected(socket) do
    if connected?(socket) do
      push_event(socket, "fetch_p2p_status", %{})
    else
      socket
    end
  end

  def open_modal(socket) do
    socket
    |> assign(
      show_p2p_pairing_modal: true,
      p2p_step: :choose,
      p2p_busy: false,
      p2p_error: nil,
      p2p_offer_paste: "",
      p2p_response_paste: "",
      p2p_copy_hint: nil
    )
    |> push_event("fetch_p2p_status", %{})
  end

  def close_modal(socket) do
    session_id = socket.assigns[:p2p_session_id]

    socket =
      assign(socket,
        show_p2p_pairing_modal: false,
        p2p_step: :choose,
        p2p_busy: false,
        p2p_error: nil,
        p2p_session_id: nil,
        p2p_short_code: nil,
        p2p_qr_png_base64: nil,
        p2p_offer_json: nil,
        p2p_response_json: nil,
        p2p_offer_paste: "",
        p2p_response_paste: "",
        p2p_remote_device_name: nil,
        p2p_remote_device_id: nil,
        p2p_copy_hint: nil,
        p2p_success_role: nil
      )

    if is_binary(session_id) and session_id != "" do
      push_event(socket, "p2p_cancel_pairing", %{session_id: session_id})
    else
      socket
    end
  end

  def choose_host(socket) do
    socket
    |> assign(p2p_step: :host, p2p_busy: true, p2p_error: nil)
    |> push_event("p2p_start_pairing_host", %{})
  end

  def choose_guest(socket) do
    assign(socket, p2p_step: :guest_paste, p2p_error: nil, p2p_offer_paste: "")
  end

  def update_offer_paste(socket, value) when is_binary(value) do
    assign(socket, p2p_offer_paste: value)
  end

  def update_response_paste(socket, value) when is_binary(value) do
    assign(socket, p2p_response_paste: value)
  end

  def submit_offer_paste(socket, offer \\ nil) do
    offer =
      (offer || socket.assigns[:p2p_offer_paste] || "")
      |> paste_value()
      |> extract_json_object()
      |> String.trim()

    if offer == "" do
      assign(socket,
        p2p_error:
          "Paste the pairing code from the other computer (Copy pairing code on that device)."
      )
    else
      socket
      |> assign(p2p_busy: true, p2p_error: nil, p2p_offer_paste: offer)
      |> push_event("p2p_submit_pairing_offer", %{offer_json: offer})
    end
  end

  def confirm_responder(socket) do
    session_id = socket.assigns[:p2p_session_id]

    if is_binary(session_id) and session_id != "" do
      socket
      |> assign(p2p_busy: true, p2p_error: nil)
      |> push_event("p2p_confirm_pairing_responder", %{session_id: session_id})
    else
      assign(socket,
        p2p_error: "Pairing session missing. Paste the pairing code again from the other device."
      )
    end
  end

  def complete_initiator(socket, response \\ nil) do
    response =
      (response || socket.assigns[:p2p_response_paste] || "")
      |> paste_value()
      |> extract_json_object()
      |> String.trim()

    if response == "" do
      assign(socket,
        p2p_error:
          "Paste the response code from the joining computer (Copy response for other device)."
      )
    else
      socket
      |> assign(p2p_busy: true, p2p_error: nil, p2p_response_paste: response)
      |> push_event("p2p_complete_pairing_initiator", %{response_json: response})
    end
  end

  def acknowledge_copy(socket, which) when which in ["offer", "response"] do
    assign(socket, p2p_copy_hint: which, p2p_error: nil)
  end

  def acknowledge_copy(socket, _), do: socket

  def apply_status(socket, params) when is_map(params) do
    local = Map.get(params, "local_device") || Map.get(params, "localDevice")
    peers = Map.get(params, "peers") || []

    assign(socket,
      p2p_local_device: local,
      p2p_peers: normalize_peers(peers)
    )
  end

  def apply_status(socket, _), do: socket

  def handle_host_started(socket, params) when is_map(params) do
    socket
    |> assign(
      p2p_busy: false,
      p2p_step: :host,
      p2p_error: nil,
      p2p_session_id: param(params, "session_id", "sessionId"),
      p2p_short_code: param(params, "short_code", "shortCode"),
      p2p_qr_png_base64: param(params, "qr_png_base64", "qrPngBase64"),
      p2p_offer_json: param(params, "offer_json", "offerJson")
    )
  end

  def handle_host_started(socket, _), do: socket

  def handle_offer_submitted(socket, params) when is_map(params) do
    socket
    |> assign(
      p2p_busy: false,
      p2p_step: :guest_confirm,
      p2p_error: nil,
      p2p_session_id: param(params, "session_id", "sessionId"),
      p2p_short_code: param(params, "short_code", "shortCode"),
      p2p_remote_device_name: param(params, "remote_device_name", "remoteDeviceName"),
      p2p_remote_device_id: param(params, "remote_device_id", "remoteDeviceId")
    )
  end

  def handle_offer_submitted(socket, _), do: socket

  def handle_responder_confirmed(socket, params) when is_map(params) do
    peer_name = param(params, "peer_device_name", "peerDeviceName")

    socket
    |> assign(
      p2p_busy: false,
      p2p_step: :guest_share_response,
      p2p_error: nil,
      p2p_copy_hint: nil,
      p2p_response_json: param(params, "response_json", "responseJson"),
      p2p_qr_png_base64: param(params, "qr_png_base64", "qrPngBase64"),
      p2p_remote_device_name: peer_name
    )
    |> put_flash(
      :info,
      "Trusted this device — copy the response code to the other computer to finish."
    )
    |> push_event("fetch_p2p_status", %{})
  end

  def handle_responder_confirmed(socket, _), do: socket

  def handle_initiator_completed(socket, params) when is_map(params) do
    peer_name = param(params, "peer_device_name", "peerDeviceName")

    socket
    |> assign(
      p2p_busy: false,
      p2p_step: :success,
      p2p_error: nil,
      p2p_session_id: nil,
      p2p_remote_device_name: peer_name,
      p2p_success_role: :host,
      p2p_copy_hint: nil
    )
    |> put_flash(:info, "Paired with #{peer_name}. WiFi sync will use this trust on your LAN.")
    |> push_event("fetch_p2p_status", %{})
  end

  def handle_initiator_completed(socket, _), do: socket

  def handle_failed(socket, %{"message" => message}) when is_binary(message) do
    trimmed = String.trim(message)
    error = if trimmed == "", do: "Pairing failed.", else: trimmed

    socket
    |> assign(p2p_busy: false, p2p_error: error)
    |> put_flash(:error, error)
  end

  def handle_failed(socket, _params) do
    handle_failed(socket, %{"message" => "Pairing failed."})
  end

  def request_remove_peer(socket, device_id) when is_binary(device_id) do
    push_event(socket, "p2p_remove_peer", %{device_id: device_id})
  end

  def handle_peer_removed(socket, params) when is_map(params) do
    socket
    |> put_flash(:info, "Device removed from paired list.")
    |> push_event("fetch_p2p_status", %{})
    |> assign(p2p_busy: false)
  end

  def handle_peer_removed(socket, _), do: socket

  defp normalize_peers(peers) when is_list(peers) do
    Enum.map(peers, fn peer ->
      %{
        device_id: param(peer, "device_id", "deviceId"),
        device_name: param(peer, "device_name", "deviceName") || "Unknown device",
        paired_at: param(peer, "paired_at", "pairedAt"),
        pinned: truthy?(Map.get(peer, "pinned"))
      }
    end)
  end

  defp normalize_peers(_), do: []

  defp param(params, snake, camel) when is_map(params) do
    Map.get(params, snake) || Map.get(params, camel)
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp paste_value(value) when is_binary(value), do: value
  defp paste_value(_), do: ""

  defp extract_json_object(value) when is_binary(value) do
    trimmed = String.trim(value)

    case {String.first(trimmed), String.last(trimmed)} do
      {"{", "}"} ->
        trimmed

      _ ->
        case :binary.match(trimmed, "{") do
          {start, _} ->
            case :binary.match(trimmed, "}") do
              {finish, len} ->
                String.slice(trimmed, start, finish + len - start)

              :nomatch ->
                trimmed
            end

          :nomatch ->
            trimmed
        end
    end
  end
end
