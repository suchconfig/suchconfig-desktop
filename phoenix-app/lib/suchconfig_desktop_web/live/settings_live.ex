defmodule SuchConfigDesktopWeb.SettingsLive do
  use SuchConfigDesktopWeb, :live_view

  @shortcuts [
    {"Open command palette", "⌘K"},
    {"Open Settings", "G ,"},
    {"Lock vault", "⌃⇧L"},
    {"New login", "N L"},
    {"New API key", "N A"},
    {"Copy username", "⌘⇧C"},
    {"Reveal secret", "⌘R"}
  ]

  alias SuchConfigDesktop.TrustedFolder
  alias SuchConfigDesktop.VaultStorage
  alias SuchConfigDesktopWeb.P2pLanSyncEvents
  alias SuchConfigDesktopWeb.P2pPairingEvents
  alias SuchConfigDesktopWeb.TrustedFolderEvents

  @storage_topic "settings:storage"

  def mount(_params, session, socket) do
    vault_unlocked = session["vault_unlocked"] == true
    vault_session_id = session["vault_session_id"]

    if vault_session_id do
      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "vault:#{vault_session_id}")
    end

    Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "trusted_folder:status")
    Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, @storage_topic)

    socket =
      assign(socket,
        page_title: "Settings - SuchConfig",
        vault_unlocked: vault_unlocked,
        vault_session_id: vault_session_id,
        shortcuts: @shortcuts,
        trusted_folder_path: nil,
        trusted_folder_display_path: nil,
        trusted_folder_synced: false,
        trusted_folder_watcher_running: false,
        trusted_folder_sync_busy: false,
        trusted_folder_last_error: nil,
        trusted_folder_integrity_message: nil,
        storage: VaultStorage.summary()
      )
      |> assign(P2pPairingEvents.default_assigns())
      |> assign(P2pLanSyncEvents.default_assigns())
      |> P2pPairingEvents.on_mount_connected()
      |> P2pLanSyncEvents.on_mount_connected()

    {:ok, socket}
  end

  def handle_event("trusted_folder_sync_now", _params, socket) do
    if socket.assigns[:vault_session_id] do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :trusted_folder_sync_now
      )
    end

    {:noreply, assign(socket, trusted_folder_sync_busy: true, trusted_folder_last_error: nil)}
  end

  def handle_event("trusted_folder_verify_integrity", _params, socket) do
    if socket.assigns[:vault_session_id] do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :trusted_folder_verify_integrity
      )
    end

    {:noreply, socket}
  end

  def handle_event("open_trusted_folder_setup", _params, socket) do
    if socket.assigns[:vault_session_id] do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :open_trusted_folder_setup
      )
    end

    {:noreply, socket}
  end

  def handle_event("open_trusted_folder_change", _params, socket) do
    if socket.assigns[:vault_session_id] do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :open_trusted_folder_change
      )
    end

    {:noreply, socket}
  end

  def handle_event("open_p2p_pairing", _params, socket) do
    {:noreply, P2pPairingEvents.open_modal(socket)}
  end

  def handle_event("dismiss_p2p_pairing_modal", _params, socket) do
    {:noreply, P2pPairingEvents.close_modal(socket)}
  end

  def handle_event("p2p_choose_host", _params, socket) do
    {:noreply, P2pPairingEvents.choose_host(socket)}
  end

  def handle_event("p2p_choose_guest", _params, socket) do
    {:noreply, P2pPairingEvents.choose_guest(socket)}
  end

  def handle_event("p2p_update_offer_paste", %{"offer_paste" => value}, socket) do
    {:noreply, P2pPairingEvents.update_offer_paste(socket, value)}
  end

  def handle_event("p2p_update_offer_paste", _params, socket), do: {:noreply, socket}

  def handle_event("p2p_update_response_paste", %{"response_paste" => value}, socket) do
    {:noreply, P2pPairingEvents.update_response_paste(socket, value)}
  end

  def handle_event("p2p_update_response_paste", _params, socket), do: {:noreply, socket}

  def handle_event("p2p_submit_offer_paste", %{"offer_paste" => value}, socket) do
    {:noreply, P2pPairingEvents.submit_offer_paste(socket, value)}
  end

  def handle_event("p2p_submit_offer_paste", _params, socket) do
    {:noreply, P2pPairingEvents.submit_offer_paste(socket)}
  end

  def handle_event("p2p_confirm_responder", _params, socket) do
    {:noreply, P2pPairingEvents.confirm_responder(socket)}
  end

  def handle_event("p2p_complete_initiator", %{"response_paste" => value}, socket) do
    {:noreply, P2pPairingEvents.complete_initiator(socket, value)}
  end

  def handle_event("p2p_complete_initiator", _params, socket) do
    {:noreply, P2pPairingEvents.complete_initiator(socket)}
  end

  def handle_event("p2p_remove_peer", %{"device_id" => device_id}, socket) do
    {:noreply, P2pPairingEvents.request_remove_peer(socket, device_id)}
  end

  def handle_event("p2p_pairing_copied", %{"which" => which}, socket) do
    {:noreply, P2pPairingEvents.acknowledge_copy(socket, which)}
  end

  def handle_event("p2p_pairing_copied", _params, socket), do: {:noreply, socket}

  def handle_event("p2p_status", params, socket) do
    {:noreply, P2pPairingEvents.apply_status(socket, params)}
  end

  def handle_event("p2p_host_started", params, socket) do
    {:noreply, P2pPairingEvents.handle_host_started(socket, params)}
  end

  def handle_event("p2p_offer_submitted", params, socket) do
    {:noreply, P2pPairingEvents.handle_offer_submitted(socket, params)}
  end

  def handle_event("p2p_responder_confirmed", params, socket) do
    {:noreply, P2pPairingEvents.handle_responder_confirmed(socket, params)}
  end

  def handle_event("p2p_initiator_completed", params, socket) do
    {:noreply, P2pPairingEvents.handle_initiator_completed(socket, params)}
  end

  def handle_event("p2p_failed", params, socket) do
    {:noreply, P2pPairingEvents.handle_failed(socket, params)}
  end

  def handle_event("p2p_peer_removed", params, socket) do
    {:noreply, P2pPairingEvents.handle_peer_removed(socket, params)}
  end

  def handle_event("p2p_toggle_lan_sync", %{"enabled" => enabled}, socket) do
    {:noreply, P2pLanSyncEvents.toggle_lan_sync(socket, enabled in [true, "true", "1"])}
  end

  def handle_event("p2p_request_lan_handoff", %{"device_id" => device_id}, socket) do
    {:noreply, P2pLanSyncEvents.request_handoff(socket, device_id)}
  end

  def handle_event("p2p_handoff_ready_for_bundles", params, socket) do
    {:noreply,
     P2pLanSyncEvents.handle_settings_forward(socket, {:p2p_handoff_ready_for_bundles, params})}
  end

  def handle_event("p2p_lan_status", params, socket) do
    {:noreply, P2pLanSyncEvents.apply_lan_status(socket, params)}
  end

  def handle_event("p2p_lan_discovery_update", params, socket) do
    {:noreply, P2pLanSyncEvents.apply_discovery_update(socket, params)}
  end

  def handle_event("p2p_lan_handoff_complete", params, socket) do
    {:noreply, P2pLanSyncEvents.handle_handoff_complete(socket, params)}
  end

  def handle_event("p2p_lan_sync_error", params, socket) do
    {:noreply, P2pLanSyncEvents.handle_sync_error(socket, params)}
  end

  def handle_event("lock_global_passkey_from_settings", _params, socket) do
    socket =
      if socket.assigns[:vault_session_id] do
        Phoenix.PubSub.broadcast(
          SuchConfigDesktop.PubSub,
          "vault:#{socket.assigns.vault_session_id}",
          :do_lock_global_passkey
        )

        assign(socket, vault_unlocked: false)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("unlock_global_passkey", _params, socket) do
    if socket.assigns[:vault_session_id] do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :request_unlock
      )
    end

    {:noreply, socket}
  end

  def handle_info(:do_lock_global_passkey, socket) do
    {:noreply, assign(socket, vault_unlocked: false)}
  end

  def handle_info(:vault_locked_no_overlay, socket) do
    {:noreply, assign(socket, vault_unlocked: false)}
  end

  def handle_info(:vault_locked, socket) do
    {:noreply, assign(socket, vault_unlocked: false)}
  end

  def handle_info(:vault_unlocked, socket) do
    {:noreply, assign(socket, vault_unlocked: true) |> assign_storage()}
  end

  def handle_info(:refresh_storage_stats, socket) do
    {:noreply, assign_storage(socket)}
  end

  def handle_info(:open_trusted_folder_setup, socket), do: {:noreply, socket}

  def handle_info(:open_trusted_folder_change, socket), do: {:noreply, socket}

  def handle_info(:trusted_folder_sync_now, socket), do: {:noreply, socket}

  def handle_info(:trusted_folder_verify_integrity, socket), do: {:noreply, socket}

  def handle_info(:request_unlock, socket), do: {:noreply, socket}

  def handle_info({:trusted_folder_status, params}, socket) do
    {:noreply,
     socket
     |> TrustedFolderEvents.apply_status_to_settings(params)
     |> assign_storage()}
  end

  def handle_info({:trusted_folder_sync, _vault}, socket), do: {:noreply, socket}
  def handle_info({:p2p_lan_sync, _vault}, socket), do: {:noreply, socket}

  def handle_info({:p2p_lan_discovery_update, _} = message, socket) do
    {:noreply, P2pLanSyncEvents.handle_settings_forward(socket, message)}
  end

  def handle_info({:p2p_lan_sync_error, _} = message, socket) do
    {:noreply, P2pLanSyncEvents.handle_settings_forward(socket, message)}
  end

  def handle_info({:p2p_handoff_ready_for_bundles, _} = message, socket) do
    {:noreply, P2pLanSyncEvents.handle_settings_forward(socket, message)}
  end

  def handle_info({:p2p_lan_handoff_complete, _} = message, socket) do
    {:noreply, P2pLanSyncEvents.handle_settings_forward(socket, message)}
  end

  def render(assigns) do
    ~H"""
    <div id="settings-live-root">
      <div id="settings-p2p-hook" phx-hook="P2pPairingSync" class="hidden" aria-hidden="true"></div>
      <.p2p_pairing_modal
        show={@show_p2p_pairing_modal}
        step={@p2p_step}
        busy={@p2p_busy}
        error={@p2p_error}
        short_code={@p2p_short_code}
        qr_png_base64={@p2p_qr_png_base64}
        offer_json={@p2p_offer_json}
        response_json={@p2p_response_json}
        remote_device_name={@p2p_remote_device_name}
        local_device_name={local_device_name(@p2p_local_device)}
        offer_paste={@p2p_offer_paste}
        response_paste={@p2p_response_paste}
        copy_hint={@p2p_copy_hint}
      />
      <section class="page-head">
        <div>
          <div class="eyebrow">Settings</div>
          <h1>preferences,<br /><em>kept local.</em></h1>
          <div class="lede">
            Nothing here phones home. Configure encryption, sync devices, and shortcuts.
          </div>
        </div>
      </section>
      <div class="split">
        <div class="card">
          <h4>Encryption</h4>
          <div class="col" style="gap: 14px">
            <div class="row" style="justify-content: space-between">
              <span>Global passkey</span>
              <button
                :if={@vault_unlocked}
                type="button"
                id="settings-lock-passkey-btn"
                phx-click="lock_global_passkey_from_settings"
                phx-throttle="300"
                class="btn sm"
              >
                Lock
              </button>
              <button
                :if={!@vault_unlocked}
                type="button"
                id="settings-unlock-passkey-btn"
                phx-click="unlock_global_passkey"
                phx-throttle="300"
                class="btn sm primary"
              >
                Unlock
              </button>
            </div>
            <div class="row" style="justify-content: space-between">
              <span>Master passphrase</span>
              <button type="button" class="btn sm">Rotate</button>
            </div>
            <div class="row" style="justify-content: space-between">
              <span>Auto-lock after</span>
              <span class="mono faint">10 minutes</span>
            </div>
            <div class="row" style="justify-content: space-between">
              <span>Algorithm</span>
              <span class="mono faint">XChaCha20-Poly1305</span>
            </div>
            <div class="row" style="justify-content: space-between">
              <span>KDF</span>
              <span class="mono faint">Argon2id · t=4 · m=64M</span>
            </div>
          </div>
        </div>
        <div class="card" id="settings-trusted-folder-card">
          <h4>Sync health</h4>
          <p class="muted" style="margin-bottom: 14px">
            Encrypted vault snapshots sync to a folder you control — Dropbox, iCloud, Drive, or local disk.
            SuchConfig never hosts your vault. Imports mirror the backup snapshot: items and folders missing from a backup are removed locally after merge.
          </p>
          <.trusted_folder_badge
            id="trusted-folder-settings-badge"
            display_path={@trusted_folder_display_path}
            synced={@trusted_folder_synced}
            watcher_running={@trusted_folder_watcher_running}
          />
          <div
            :if={trusted_folder_configured?(assigns)}
            class="row"
            style="gap: 10px; margin-top: 14px; flex-wrap: wrap"
          >
            <button
              type="button"
              id="settings-trusted-folder-sync-btn"
              phx-click="trusted_folder_sync_now"
              phx-throttle="1000"
              class="btn sm primary"
              disabled={@trusted_folder_sync_busy or !@vault_unlocked}
            >
              {if @trusted_folder_sync_busy, do: "Syncing…", else: "Sync now"}
            </button>
            <button
              type="button"
              id="settings-trusted-folder-verify-btn"
              phx-click="trusted_folder_verify_integrity"
              phx-throttle="1000"
              class="btn sm"
            >
              Verify archive integrity
            </button>
            <button
              type="button"
              id="settings-trusted-folder-change-btn"
              phx-click="open_trusted_folder_change"
              phx-throttle="1000"
              class="btn sm ghost"
            >
              Change folder
            </button>
          </div>
          <p
            :if={!@vault_unlocked and trusted_folder_configured?(assigns)}
            class="muted"
            style="margin-top: 10px; font-size: 13px"
          >
            Unlock your vault to push encrypted backups.
          </p>
          <p
            :if={is_binary(@trusted_folder_last_error) and @trusted_folder_last_error != ""}
            id="settings-trusted-folder-error"
            class="vault-flash err"
            style="margin-top: 12px"
          >
            {@trusted_folder_last_error}
          </p>
          <p
            :if={
              is_binary(@trusted_folder_integrity_message) and @trusted_folder_integrity_message != "" and
                (is_nil(@trusted_folder_last_error) or @trusted_folder_last_error == "")
            }
            id="settings-trusted-folder-integrity"
            class="muted"
            style="margin-top: 12px; font-size: 13px"
          >
            {@trusted_folder_integrity_message}
          </p>
          <p
            :if={trusted_folder_configured?(assigns)}
            class="muted"
            style="margin-top: 12px; font-size: 13px"
          >
            Backups live in a hidden <span class="mono">.suchconfig</span>
            subfolder as encrypted <span class="mono">projects.loro.enc</span>
            and <span class="mono">secrets.loro.enc</span>
            with SHA-256 sidecars. In Finder, press <span class="kbd">⌘⇧.</span>
            to show hidden folders.
          </p>
          <p
            :if={!trusted_folder_configured?(assigns)}
            class="muted"
            style="margin-top: 12px"
          >
            No Trusted Folder configured yet.
          </p>
          <button
            :if={!trusted_folder_configured?(assigns)}
            type="button"
            id="settings-trusted-folder-setup-btn"
            phx-click="open_trusted_folder_setup"
            class="btn sm"
            style="margin-top: 12px"
          >
            Choose Trusted Folder
          </button>
        </div>
        <div class="card" id="settings-p2p-devices-card">
          <h4>WiFi / LAN devices</h4>
          <p class="muted" style="margin-bottom: 12px" id="settings-p2p-lan-intro">
            Sync vaults directly between your paired SuchConfig desktops on the same Wi‑Fi or LAN.
            Traffic stays on your local network — nothing is uploaded to SuchConfig or the internet for this feature.
          </p>
          <ol
            class="muted"
            id="settings-p2p-lan-steps"
            style="margin: 0 0 14px 18px; padding: 0; font-size: 13px; line-height: 1.5"
          >
            <li style="margin-bottom: 6px">
              <strong>Pair</strong> each computer once (establishes trust — no vault data moves yet).
            </li>
            <li style="margin-bottom: 6px">
              <strong>Enable LAN sync</strong> on both devices on the same trusted network.
            </li>
            <li>
              <strong>Handoff</strong>
              copies Project + Secrets snapshots to the other device, or keep both unlocked for live updates while you edit.
            </li>
          </ol>
          <p
            :if={@p2p_peers == []}
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-pair-first-hint"
          >
            Start by pairing your other computer below. Handoff and LAN sync are unavailable until at least one device is paired.
          </p>
          <p
            :if={@p2p_peers != [] and !@p2p_lan_sync_enabled}
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-enable-lan-hint"
          >
            You have paired devices, but LAN sync is off. Turn it on here and on each paired computer — both must be on the same Wi‑Fi with the vault unlocked for Handoff.
          </p>
          <div
            class="row"
            style="justify-content: space-between; margin-bottom: 14px"
            id="settings-p2p-lan-toggle-row"
          >
            <span>Enable LAN sync</span>
            <button
              type="button"
              id="settings-p2p-lan-sync-toggle"
              phx-click="p2p_toggle_lan_sync"
              phx-value-enabled={if @p2p_lan_sync_enabled, do: "false", else: "true"}
              class={["btn sm", @p2p_lan_sync_enabled && "primary"]}
              disabled={@p2p_lan_sync_busy}
            >
              {if @p2p_lan_sync_enabled, do: "On", else: "Off"}
            </button>
          </div>
          <p
            :if={!@p2p_lan_sync_enabled}
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-lan-off-hint"
          >
            LAN sync is off by default. Enable only on networks you trust. This does not replace Trusted Folder backup — use both for backup plus fast local sync.
          </p>
          <p
            :if={@p2p_lan_sync_enabled and is_binary(@p2p_lan_iroh_endpoint_id)}
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-lan-listen-port"
          >
            LAN sync is active via iroh/QUIC on this network. Paired devices are discovered over mDNS; use Handoff when a peer is online.
          </p>
          <p
            :if={@p2p_lan_sync_enabled}
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-lan-firewall-hint"
          >
            Receiver Mac: keep Firewall ON and allow incoming connections for this exact app build (SuchConfig Dev vs SuchConfig.app are separate), plus Local Network permission. If Handoff times out with no inbound connection on the other Mac, the firewall is usually blocking UDP.
          </p>
          <p
            :if={@p2p_lan_sync_enabled and !@vault_unlocked}
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-unlock-for-handoff-hint"
          >
            Unlock your vault to send or receive a Handoff.
          </p>
          <p
            :if={
              @p2p_lan_sync_enabled and @p2p_peers != [] and
                lan_peers_online_awaiting_handoff?(@p2p_lan_peers, assigns)
            }
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-handoff-wait-hint"
          >
            A paired device is visible on the network. Wait until the <strong>Handoff</strong>
            button appears — that means its address is confirmed and a transfer can start.
          </p>
          <p
            :if={
              @p2p_lan_sync_enabled and @p2p_peers != [] and
                lan_peers_any_handoff_ready?(@p2p_lan_peers, assigns)
            }
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-handoff-ready-hint"
          >
            Handoff is ready for at least one online peer. Click Handoff on the computer that should
            <em>send</em>
            its vault to the other. Keep both vaults unlocked until the transfer finishes.
          </p>
          <p
            :if={
              @p2p_lan_sync_enabled and @p2p_peers != [] and lan_peers_all_offline?(@p2p_lan_peers)
            }
            class="muted"
            style="margin-bottom: 14px; font-size: 13px"
            id="settings-p2p-lan-unavailable"
          >
            No paired devices visible on this network. Confirm LAN sync is on and the vault is unlocked on both computers, on the same Wi‑Fi. VPN, guest Wi‑Fi, or firewall rules may block discovery — use Trusted Folder or archive import as a fallback.
          </p>
          <p
            :if={is_binary(@p2p_lan_sync_error) and @p2p_lan_sync_error != ""}
            id="settings-p2p-lan-error"
            class="vault-flash err"
            style="margin-bottom: 12px"
          >
            {@p2p_lan_sync_error}
          </p>
          <div class="col" style="gap: 12px">
            <div :if={is_map(@p2p_local_device)} class="row" id="settings-p2p-this-device">
              <span style="flex: 1">
                {local_device_name(@p2p_local_device)}
                <span style="margin-left: 8px">
                  <.kbd>this device</.kbd>
                </span>
              </span>
              <.pill tone="ok">ready</.pill>
            </div>
            <div :if={@p2p_peers == []} class="muted" id="settings-p2p-empty">
              No paired devices yet. Use Pair a new device below — you need two computers on the same network before Handoff can work.
            </div>
            <div
              :for={peer <- @p2p_lan_peers}
              class="row"
              id={"settings-p2p-lan-peer-#{peer.device_id}"}
            >
              <span style="flex: 1">
                {peer.device_name}
                <span
                  :if={peer.online and peer.port}
                  class="muted"
                  style="font-size: 11px; margin-left: 6px"
                >
                  {peer.host}:{peer.port}
                </span>
              </span>
              <.pill tone={if peer.online, do: "ok", else: "muted"}>
                {if peer.online, do: "online", else: "offline"}
              </.pill>
              <button
                :if={P2pLanSyncEvents.handoff_button_visible?(peer, assigns)}
                type="button"
                id={"settings-p2p-handoff-#{peer.device_id}"}
                phx-click="p2p_request_lan_handoff"
                phx-value-device_id={peer.device_id}
                class="btn sm"
                disabled={@p2p_lan_sync_busy and @p2p_lan_handoff_device_id == peer.device_id}
              >
                {if @p2p_lan_handoff_device_id == peer.device_id and @p2p_lan_sync_busy,
                  do: "Handoff…",
                  else: "Handoff"}
              </button>
              <button
                type="button"
                phx-click="p2p_remove_peer"
                phx-value-device_id={peer.device_id}
                class="btn sm ghost"
                aria-label={"Remove #{peer.device_name}"}
              >
                Remove
              </button>
            </div>
            <div :if={@p2p_lan_peers == [] and @p2p_peers != []} class="col" style="gap: 12px">
              <p class="muted" style="font-size: 13px" id="settings-p2p-paired-not-advertising">
                Paired devices are listed below. When LAN sync is on, they appear here with online status once discovered on this network.
              </p>
              <div :for={peer <- @p2p_peers} class="row" id={"settings-p2p-peer-#{peer.device_id}"}>
                <span style="flex: 1">{peer.device_name}</span>
                <.pill tone="ok">paired</.pill>
                <button
                  type="button"
                  phx-click="p2p_remove_peer"
                  phx-value-device_id={peer.device_id}
                  class="btn sm ghost"
                  aria-label={"Remove #{peer.device_name}"}
                >
                  Remove
                </button>
              </div>
            </div>
            <button
              type="button"
              id="settings-p2p-pair-btn"
              phx-click="open_p2p_pairing"
              class="btn sm"
              style="align-self: flex-start; margin-top: 6px"
            >
              <.sc_icon name="plus" size={12} /> Pair a new device
            </button>
          </div>
        </div>
        <div class="card">
          <h4>Shortcuts</h4>
          <div class="col" style="gap: 10px">
            <div :for={{label, keys} <- @shortcuts} class="row" style="justify-content: space-between">
              <span class="muted">{label}</span>
              <.kbd>{keys}</.kbd>
            </div>
          </div>
        </div>
        <div class="card" id="settings-storage-card">
          <h4>Storage</h4>
          <div class="big" id="settings-storage-size">
            {@storage.size_value}<sup>{@storage.size_unit} on disk</sup>
          </div>
          <div class="muted" style="margin-top: 18px; font-size: 13px" id="settings-storage-breakdown">
            {@storage.breakdown_label}. CRDT history is stored with each item.
          </div>
          <button type="button" class="btn sm" style="margin-top: 18px" disabled title="Coming soon">
            <.sc_icon name="archive" size={12} /> Compact history
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp sc_icon(assigns), do: SuchConfigDesktopWeb.Sc.Icon.icon(assigns)

  defp assign_storage(socket), do: assign(socket, storage: VaultStorage.summary())

  defp trusted_folder_configured?(assigns) do
    TrustedFolder.configured?(assigns[:trusted_folder_path]) or
      (is_binary(assigns[:trusted_folder_display_path]) and
         assigns[:trusted_folder_display_path] != "")
  end

  defp local_device_name(%{"device_name" => name}) when is_binary(name) and name != "", do: name
  defp local_device_name(%{"deviceName" => name}) when is_binary(name) and name != "", do: name
  defp local_device_name(%{device_name: name}) when is_binary(name) and name != "", do: name
  defp local_device_name(_), do: "This device"

  defp lan_peers_all_offline?(peers) when is_list(peers) do
    peers != [] and Enum.all?(peers, fn p -> p.online != true end)
  end

  defp lan_peers_all_offline?(_), do: false

  defp lan_peers_any_handoff_ready?(peers, assigns) when is_list(peers) do
    Enum.any?(peers, fn peer -> P2pLanSyncEvents.handoff_button_visible?(peer, assigns) end)
  end

  defp lan_peers_any_handoff_ready?(_, _), do: false

  defp lan_peers_online_awaiting_handoff?(peers, assigns) when is_list(peers) do
    Enum.any?(peers, &(&1.online == true)) and not lan_peers_any_handoff_ready?(peers, assigns)
  end

  defp lan_peers_online_awaiting_handoff?(_, _), do: false
end
