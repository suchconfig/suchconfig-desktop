defmodule SuchConfigDesktopWeb.P2pLanSyncEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3, push_event: 3]

  alias SuchConfigDesktop.LanSync
  alias SuchConfigDesktop.TrustedFolder

  @settings_topic "p2p:lan_settings"

  def default_assigns do
    %{
      p2p_lan_sync_enabled: false,
      p2p_lan_peers: [],
      p2p_lan_sync_busy: false,
      p2p_lan_sync_error: nil,
      p2p_lan_handoff_device_id: nil,
      p2p_lan_last_sync_at: nil,
      p2p_lan_listen_port: nil,
      p2p_lan_transport: nil,
      p2p_lan_iroh_endpoint_id: nil
    }
  end

  def on_mount_connected(socket) do
    if connected?(socket) do
      socket
      |> subscribe_settings()
      |> push_event("fetch_p2p_lan_status", %{})
    else
      socket
    end
  end

  def subscribe_settings(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, @settings_topic)
    end

    socket
  end

  def forward_to_settings(message) do
    Phoenix.PubSub.broadcast(SuchConfigDesktop.PubSub, @settings_topic, message)
  end

  def handle_settings_forward(socket, {:p2p_lan_discovery_update, params}) do
    apply_discovery_update(socket, params)
  end

  def handle_settings_forward(socket, {:p2p_lan_sync_error, params}) do
    handle_sync_error(socket, params)
  end

  def handle_settings_forward(socket, {:p2p_handoff_ready_for_bundles, _params}) do
    send_handoff_bundles(socket)
  end

  def handle_settings_forward(socket, {:p2p_lan_handoff_complete, params}) do
    handle_handoff_complete(socket, params)
  end

  def handle_settings_forward(socket, _), do: socket

  def toggle_lan_sync(socket, enabled) when enabled in [true, false] do
    socket
    |> assign(p2p_lan_sync_busy: true, p2p_lan_sync_error: nil)
    |> push_event("p2p_set_lan_sync_enabled", %{enabled: enabled})
  end

  def request_handoff(socket, device_id) when is_binary(device_id) do
    peer =
      (socket.assigns[:p2p_lan_peers] || [])
      |> Enum.find(fn p -> p.device_id == device_id end)

    cond do
      !ready_for_sync?(socket) ->
        assign(socket, p2p_lan_sync_error: sync_blocked_message(socket))

      !handoff_peer_ready?(peer) ->
        assign(socket,
          p2p_lan_sync_error:
            "Peer is not ready for LAN handoff yet. Wait until Handoff appears in Settings, then retry."
        )

      true ->
        case session_password(socket) do
          password when is_binary(password) and password != "" ->
            bundles = LanSync.export_handoff_bundles(password)

            socket
            |> assign(
              p2p_lan_sync_busy: true,
              p2p_lan_sync_error: nil,
              p2p_lan_handoff_device_id: device_id
            )
            |> push_event("p2p_request_handoff", %{device_id: device_id, bundles: bundles})

          _ ->
            assign(socket, p2p_lan_sync_error: sync_blocked_message(socket))
        end
    end
  end

  def send_handoff_bundles(socket) do
    case session_password(socket) do
      password when is_binary(password) and password != "" ->
        bundles = LanSync.export_handoff_bundles(password)

        socket
        |> push_event("p2p_send_handoff_bundles", %{bundles: bundles})

      _ ->
        assign(socket, p2p_lan_sync_error: sync_blocked_message(socket))
    end
  end

  def apply_lan_status(socket, params) when is_map(params) do
    enabled = truthy?(params["enabled"] || params[:enabled])
    peers = normalize_lan_peers(params["peers"] || params[:peers] || [])

    assign(socket,
      p2p_lan_sync_enabled: enabled,
      p2p_lan_peers: peers,
      p2p_lan_sync_busy: false,
      p2p_lan_sync_error: blank_to_nil(params["last_error"] || params[:last_error]),
      p2p_lan_listen_port: params["listenPort"] || params[:listen_port],
      p2p_lan_transport: params["transport"] || params[:transport],
      p2p_lan_iroh_endpoint_id:
        blank_to_nil(params["irohEndpointId"] || params[:iroh_endpoint_id])
    )
  end

  def apply_lan_status(socket, _), do: socket

  def apply_discovery_update(socket, params) when is_map(params) do
    peers = normalize_lan_peers(params["peers"] || params[:peers] || [])
    assign(socket, p2p_lan_peers: peers)
  end

  def apply_discovery_update(socket, _), do: socket

  def handle_handoff_bundle(socket, params) when is_map(params) do
    vault = params["vault"] || params[:vault]
    snapshot = params["snapshot_base64"] || params["snapshotBase64"]
    password = session_password(socket)

    if is_binary(password) and password != "" do
      try do
        case LanSync.import_handoff_bundle(vault, snapshot, password) do
          {:ok, stats} ->
            socket
            |> refresh_handoff_vault_assigns(vault)
            |> assign(
              p2p_lan_sync_error: handoff_import_warning(stats),
              p2p_lan_last_sync_at: DateTime.utc_now()
            )
            |> put_flash(:info, handoff_flash_message(vault, stats))

          {:error, reason} ->
            assign(socket, p2p_lan_sync_error: handoff_import_error(reason))
        end
      rescue
        _ ->
          assign(socket, p2p_lan_sync_error: "Could not merge LAN handoff snapshot.")
      end
    else
      assign(socket, p2p_lan_sync_error: sync_blocked_message(socket))
    end
  end

  def handle_handoff_bundle(socket, _), do: socket

  def handle_handoff_complete(socket, _params) do
    assign(socket,
      p2p_lan_sync_busy: false,
      p2p_lan_handoff_device_id: nil,
      p2p_lan_last_sync_at: DateTime.utc_now()
    )
    |> put_flash(:info, "LAN vault handoff completed.")
  end

  def handle_delta_received(socket, params) when is_map(params) do
    peer_id = params["peer_device_id"] || params["peerDeviceId"]
    updates = params["updates"] || []

    password = session_password(socket)

    if is_binary(password) and password != "" do
      case LanSync.sync_apply(peer_id, updates, password) do
        {:ok, result} ->
          socket
          |> maybe_refresh_after_delta(updates)
          |> push_frontier_updates(peer_id, result)
          |> assign(p2p_lan_last_sync_at: DateTime.utc_now(), p2p_lan_sync_error: nil)

        {:error, _} ->
          assign(socket, p2p_lan_sync_error: "Could not apply LAN sync update.")
      end
    else
      assign(socket, p2p_lan_sync_error: "Unlock your vault to apply LAN sync updates.")
    end
  end

  def handle_delta_received(socket, _), do: socket

  def handle_sync_error(socket, params) when is_map(params) do
    message = params["message"] || params[:message] || "LAN sync failed."
    assign(socket, p2p_lan_sync_busy: false, p2p_lan_sync_error: message)
  end

  def handle_sync_error(socket, _), do: socket

  def broadcast_sync(vault_session_id, vault) when is_binary(vault_session_id) do
    Phoenix.PubSub.broadcast(
      SuchConfigDesktop.PubSub,
      "vault:#{vault_session_id}",
      {:p2p_lan_sync, vault}
    )
  end

  def broadcast_sync(_, _), do: :ok

  def push_vault_deltas(socket, vault) when vault in ["projects", "secrets"] do
    if socket.assigns[:vault_unlocked] == true and connected?(socket) do
      password = session_password(socket)
      peer_frontiers = %{}

      case LanSync.export_deltas_for_vault(vault, password, peer_frontiers) do
        {:ok, []} ->
          socket

        {:ok, updates} ->
          push_event(socket, "p2p_push_deltas", %{vault: vault, updates: updates})

        _ ->
          socket
      end
    else
      broadcast_sync(socket.assigns[:vault_session_id], vault)
      socket
    end
  end

  defp maybe_refresh_after_delta(socket, updates) do
    vaults =
      updates
      |> Enum.map(fn u -> Map.get(u, "vault") || Map.get(u, :vault) end)
      |> Enum.uniq()

    if "projects" in vaults do
      assign(socket, folders: SuchConfigDesktop.ProjectVault.list_project_folders())
    else
      socket
    end
  end

  defp push_frontier_updates(socket, peer_id, %{frontier: frontier}) when is_map(frontier) do
    push_event(socket, "p2p_set_item_frontier", %{
      peer_device_id: peer_id,
      item_key: frontier.item_key,
      snapshot_base64: frontier.snapshot_base64,
      snapshot_hash: frontier.snapshot_hash
    })
  end

  defp push_frontier_updates(socket, _, _), do: socket

  defp ready_for_sync?(socket) do
    socket.assigns[:p2p_lan_sync_enabled] == true and socket.assigns[:vault_unlocked] == true
  end

  def handoff_button_visible?(peer, assigns) when is_map(peer) do
    assigns.p2p_lan_sync_enabled == true &&
      assigns.vault_unlocked == true &&
      handoff_peer_ready?(peer) &&
      handoff_action_available?(assigns, peer.device_id)
  end

  def handoff_button_visible?(_, _), do: false

  def handoff_peer_ready?(peer) when is_map(peer) do
    peer.handoff_ready && peer.online
  end

  def handoff_peer_ready?(_), do: false

  defp handoff_action_available?(assigns, device_id) do
    assigns.p2p_lan_sync_busy != true || assigns.p2p_lan_handoff_device_id == device_id
  end

  defp sync_blocked_message(socket) do
    cond do
      socket.assigns[:p2p_lan_sync_enabled] != true ->
        "Enable LAN sync before transferring vault data."

      socket.assigns[:vault_unlocked] != true ->
        "Unlock your vault to sync over the LAN."

      true ->
        "LAN sync is not ready."
    end
  end

  defp session_password(socket) do
    session_id = socket.assigns[:vault_session_id]

    key =
      cond do
        is_binary(session_id) ->
          SuchConfigDesktop.VaultSessionRegistry.get(session_id) ||
            SuchConfigDesktop.VaultKeyStore.get("suchconfig.project_manager.vault")

        true ->
          SuchConfigDesktop.VaultKeyStore.get("suchconfig.project_manager.vault")
      end

    if is_binary(key) and String.trim(key) != "", do: key, else: nil
  end

  defp normalize_lan_peers(peers) when is_list(peers) do
    Enum.map(peers, &normalize_lan_peer/1)
  end

  defp normalize_lan_peers(_), do: []

  defp normalize_lan_peer(peer) when is_map(peer) do
    %{
      device_id: param(peer, "device_id", "deviceId"),
      device_name: param(peer, "device_name", "deviceName") || "Paired device",
      online: truthy?(peer["online"] || peer[:online]),
      handoff_ready: truthy?(peer["handoff_ready"] || peer["handoffReady"]),
      host: param(peer, "host", "host"),
      port: peer["port"] || peer[:port],
      last_seen: peer["last_seen"] || peer["lastSeen"],
      pinned: truthy?(peer["pinned"] || peer[:pinned])
    }
  end

  defp normalize_lan_peer(_), do: %{device_id: nil, device_name: "Paired device", online: false}

  defp handoff_flash_message("projects", %{skipped: skipped}) when skipped > 0,
    do: "Project Vault merged from LAN handoff (#{skipped} item(s) skipped)."

  defp handoff_flash_message("secrets", %{skipped: skipped}) when skipped > 0,
    do: "Secrets Vault merged from LAN handoff (#{skipped} item(s) skipped)."

  defp handoff_flash_message("projects", _stats), do: "Project Vault merged from LAN handoff."
  defp handoff_flash_message("secrets", _stats), do: "Secrets Vault merged from LAN handoff."
  defp handoff_flash_message(_, _stats), do: "Vault merged from LAN handoff."

  defp handoff_import_warning(%{skipped: skipped}) when skipped > 0,
    do:
      "LAN handoff merged #{skipped} item(s) could not be imported — check vault folders and try again."

  defp handoff_import_warning(_stats), do: nil

  defp handoff_import_error(:invalid_bundle),
    do: "Could not merge LAN handoff snapshot (invalid bundle)."

  defp handoff_import_error(_), do: "Could not merge LAN handoff snapshot."

  defp refresh_handoff_vault_assigns(socket, vault) do
    case TrustedFolder.vault_atom(vault) do
      :projects ->
        assign(socket, folders: SuchConfigDesktop.ProjectVault.list_project_folders())

      _ ->
        socket
    end
  end

  defp param(map, snake, camel) do
    Map.get(map, snake) || Map.get(map, camel)
  end

  defp truthy?(v) when v in [true, "true", 1, "1"], do: true
  defp truthy?(_), do: false

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: String.trim(s)
  defp blank_to_nil(s), do: s
end
