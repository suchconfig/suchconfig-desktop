use std::sync::Arc;
use std::thread::JoinHandle;

use parking_lot::Mutex;
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};
use thiserror::Error;

use super::discovery::{DiscoveryManager, LanPeerStatus};
use super::iroh_transport::{IrohSpikeEchoResult, IrohTransport};
use super::protocol::DeltaUpdate;
use super::settings;

const HANDOFF_CONNECT_RETRY_MS: u64 = 20_000;
const HANDOFF_CONNECT_RETRY_INTERVAL_MS: u64 = 600;
const IROH_MDNS_REFRESH_SECS: u64 = 5;

const IROH_MIGRATION_MESSAGE: &str =
    "LAN sync is migrating from raw TCP to iroh/QUIC. Use the iroh spike command to verify connectivity until delta sync is ported.";

#[derive(Debug, Error)]
pub enum SyncError {
    #[error("{0}")]
    Message(String),
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LanSyncStatus {
    pub enabled: bool,
    pub advertising: bool,
    pub transport: String,
    pub listen_port: u16,
    pub iroh_endpoint_id: Option<String>,
    pub peers: Vec<LanPeerStatus>,
    pub last_error: Option<String>,
}

pub struct SyncManager {
    discovery: DiscoveryManager,
    iroh: IrohTransport,
    last_error: Mutex<Option<String>>,
    handoff_connect_lock: Mutex<()>,
    mdns_refresh_stop: Mutex<Option<Arc<std::sync::atomic::AtomicBool>>>,
    mdns_refresh_thread: Mutex<Option<JoinHandle<()>>>,
}

impl Default for SyncManager {
    fn default() -> Self {
        Self {
            discovery: DiscoveryManager::default(),
            iroh: IrohTransport::default(),
            last_error: Mutex::new(None),
            handoff_connect_lock: Mutex::new(()),
            mdns_refresh_stop: Mutex::new(None),
            mdns_refresh_thread: Mutex::new(None),
        }
    }
}

impl SyncManager {
    pub fn status(&self, app: &AppHandle) -> Result<LanSyncStatus, SyncError> {
        let settings = settings::load(app).map_err(|e| SyncError::Message(e.to_string()))?;
        let peers = self
            .discovery
            .peer_statuses(app)
            .map_err(|e| SyncError::Message(e.to_string()))?;
        let iroh_endpoint_id = if self.iroh.is_running() {
            Some(self.iroh.endpoint_id_b64())
        } else {
            None
        };
        Ok(LanSyncStatus {
            enabled: settings.enabled,
            advertising: settings.enabled && self.iroh.is_running(),
            transport: "iroh".into(),
            listen_port: 0,
            iroh_endpoint_id,
            peers,
            last_error: self.last_error.lock().clone(),
        })
    }

    pub fn set_enabled(&self, app: &AppHandle, enabled: bool) -> Result<LanSyncStatus, SyncError> {
        settings::set_enabled(app, enabled).map_err(|e| SyncError::Message(e.to_string()))?;
        if enabled {
            self.start(app)?;
        } else {
            self.stop();
        }
        self.status(app)
    }

    pub fn start(&self, app: &AppHandle) -> Result<(), SyncError> {
        if !self.iroh.is_running() {
            self.iroh
                .start(app)
                .map_err(|e| SyncError::Message(e.to_string()))?;
        }
        let iroh_dial_addrs = self.iroh.direct_ipv4_dial_addrs();
        if iroh_dial_addrs.is_empty() {
            eprintln!("[suchconfig-p2p] iroh endpoint has no IPv4 dial addrs yet for mDNS TXT");
        } else {
            eprintln!("[suchconfig-p2p] iroh local dial addrs for mDNS: {iroh_dial_addrs:?}");
        }
        self.discovery
            .start(app, 0, &iroh_dial_addrs)
            .map_err(|e| SyncError::Message(e.to_string()))?;
        self.spawn_iroh_mdns_refresh(app);
        *self.last_error.lock() = None;
        Ok(())
    }

    fn refresh_iroh_mdns_advertise(&self, app: &AppHandle) {
        if !self.iroh.is_running() || !self.discovery.is_running() {
            return;
        }
        let addrs = self.iroh.direct_ipv4_dial_addrs();
        if addrs.is_empty() {
            return;
        }
        if let Err(err) = self.discovery.refresh_local_iroh_advertise(app, &addrs) {
            eprintln!("[suchconfig-p2p] iroh mDNS refresh failed: {err}");
        }
    }

    fn spawn_iroh_mdns_refresh(&self, app: &AppHandle) {
        if let Some(handle) = self.mdns_refresh_thread.lock().take() {
            if let Some(stop) = self.mdns_refresh_stop.lock().take() {
                stop.store(true, std::sync::atomic::Ordering::Relaxed);
            }
            let _ = handle.join();
        }

        let stop = Arc::new(std::sync::atomic::AtomicBool::new(false));
        *self.mdns_refresh_stop.lock() = Some(Arc::clone(&stop));
        let app = app.clone();

        let handle = std::thread::spawn(move || {
            while !stop.load(std::sync::atomic::Ordering::Relaxed) {
                std::thread::sleep(std::time::Duration::from_secs(IROH_MDNS_REFRESH_SECS));
                if stop.load(std::sync::atomic::Ordering::Relaxed) {
                    break;
                }
                let state = app.state::<crate::p2p::P2pAppState>();
                state.sync.refresh_iroh_mdns_advertise(&app);
            }
        });
        *self.mdns_refresh_thread.lock() = Some(handle);
    }

    fn stop_iroh_mdns_refresh(&self) {
        if let Some(stop) = self.mdns_refresh_stop.lock().take() {
            stop.store(true, std::sync::atomic::Ordering::Relaxed);
        }
        if let Some(handle) = self.mdns_refresh_thread.lock().take() {
            let _ = handle.join();
        }
    }

    pub fn stop(&self) {
        self.stop_iroh_mdns_refresh();
        self.discovery.stop();
        self.iroh.stop();
    }

    pub fn ensure_started_if_enabled(&self, app: &AppHandle) -> Result<(), SyncError> {
        let settings = settings::load(app).map_err(|e| SyncError::Message(e.to_string()))?;
        if settings.enabled {
            self.start(app)?;
        }
        Ok(())
    }

    pub fn iroh_spike_echo(
        &self,
        app: &AppHandle,
        device_id: &str,
    ) -> Result<IrohSpikeEchoResult, SyncError> {
        self.discovery.drain_browse_events();
        self.refresh_iroh_mdns_advertise(app);
        let dial_addrs = self.discovery.peer_iroh_dial_addrs(device_id);
        self.iroh
            .spike_echo(app, device_id, dial_addrs)
            .map_err(|e| SyncError::Message(e.to_string()))
    }

    pub fn connect_handoff(&self, app: &AppHandle, device_id: &str) -> Result<(), SyncError> {
        let _handoff_guard = self.handoff_connect_lock.lock();
        self.connect_handoff_inner(app, device_id)
    }

    fn connect_handoff_inner(&self, app: &AppHandle, device_id: &str) -> Result<(), SyncError> {
        let deadline = std::time::Instant::now()
            + std::time::Duration::from_millis(HANDOFF_CONNECT_RETRY_MS);

        loop {
            if std::time::Instant::now() >= deadline {
                return Err(SyncError::Message(
                    "Handoff timed out waiting for the peer on the LAN. Keep LAN sync enabled on both Macs and retry.".into(),
                ));
            }

            if !peer_is_online(&self.discovery, app, device_id)? {
                eprintln!("[suchconfig-p2p] handoff waiting for peer {device_id} to appear online");
                self.discovery.drain_browse_events();
                std::thread::sleep(std::time::Duration::from_millis(1500));
                continue;
            }

            let _ = app.emit(
                "p2p:handoff-progress",
                serde_json::json!({
                    "deviceId": device_id,
                    "phase": "connecting",
                    "transport": "iroh",
                }),
            );

            self.discovery.drain_browse_events();
            self.refresh_iroh_mdns_advertise(app);

            let dial_addrs = self.discovery.peer_iroh_dial_addrs(device_id);
            if dial_addrs.is_empty() {
                eprintln!(
                    "[suchconfig-p2p] handoff waiting for peer {device_id} iroh_addrs from mDNS (toggle LAN sync on both Macs once if stuck)"
                );
                std::thread::sleep(std::time::Duration::from_millis(1500));
                continue;
            }

            match self.iroh.connect_handoff(app, device_id, dial_addrs) {
                Ok(()) => {
                    eprintln!("[suchconfig-p2p] iroh handoff handshake ok with {device_id}");
                    let _ = app.emit(
                        "p2p:handoff-progress",
                        serde_json::json!({ "deviceId": device_id, "phase": "connected" }),
                    );
                    return Ok(());
                }
                Err(err) if handoff_connect_retryable(&err.to_string())
                    && std::time::Instant::now() < deadline =>
                {
                    eprintln!("[suchconfig-p2p] iroh handoff connect failed (retrying): {err}");
                    self.iroh.clear_handoff_session();
                    std::thread::sleep(std::time::Duration::from_millis(
                        HANDOFF_CONNECT_RETRY_INTERVAL_MS,
                    ));
                }
                Err(err) => {
                    self.iroh.clear_handoff_session();
                    return Err(SyncError::Message(handoff_error_message(
                        &err.to_string(),
                        device_id,
                    )));
                }
            }
        }
    }

    pub fn send_handoff_bundles(
        &self,
        app: &AppHandle,
        bundles: Vec<(String, String)>,
    ) -> Result<(), SyncError> {
        self.iroh
            .send_handoff_bundles(app, bundles)
            .map_err(|e| SyncError::Message(e.to_string()))
    }

    pub fn request_handoff(
        &self,
        app: &AppHandle,
        device_id: &str,
        bundles: Vec<(String, String)>,
    ) -> Result<(), SyncError> {
        let _handoff_guard = self.handoff_connect_lock.lock();
        self.connect_handoff_inner(app, device_id)?;
        self.send_handoff_bundles(app, bundles)
    }

    pub fn push_deltas(
        &self,
        _app: &AppHandle,
        _device_id: &str,
        updates: Vec<DeltaUpdate>,
    ) -> Result<(), SyncError> {
        if updates.is_empty() {
            return Ok(());
        }
        Err(SyncError::Message(IROH_MIGRATION_MESSAGE.into()))
    }

    pub fn list_lan_peers(&self, app: &AppHandle) -> Result<Vec<LanPeerStatus>, SyncError> {
        self.discovery
            .peer_statuses(app)
            .map_err(|e| SyncError::Message(e.to_string()))
    }

    pub fn push_deltas_to_online_peers(
        &self,
        app: &AppHandle,
        updates: Vec<DeltaUpdate>,
    ) -> Result<(), SyncError> {
        if updates.is_empty() {
            return Ok(());
        }

        let settings = settings::load(app).map_err(|e| SyncError::Message(e.to_string()))?;
        if !settings.enabled {
            return Ok(());
        }

        let peers = self
            .discovery
            .peer_statuses(app)
            .map_err(|e| SyncError::Message(e.to_string()))?;

        if peers.iter().any(|p| p.online) {
            return Err(SyncError::Message(IROH_MIGRATION_MESSAGE.into()));
        }
        Ok(())
    }
}

fn peer_is_online(
    discovery: &DiscoveryManager,
    app: &AppHandle,
    device_id: &str,
) -> Result<bool, SyncError> {
    discovery.drain_browse_events();
    let peers = discovery
        .peer_statuses(app)
        .map_err(|e| SyncError::Message(e.to_string()))?;
    Ok(peers
        .iter()
        .find(|p| p.device_id == device_id)
        .map(|p| p.online && p.handoff_ready)
        .unwrap_or(false))
}

fn handoff_connect_retryable(msg: &str) -> bool {
    if msg.contains("Peer rejected LAN handshake") {
        return false;
    }
    if msg.contains("Peer signature verification failed") {
        return false;
    }
    if msg.contains("Rejected connection from unpaired peer") {
        return false;
    }
    msg.contains("iroh connect failed")
        || msg.contains("open bi stream")
        || msg.contains("read stream header")
        || msg.contains("connection closed")
        || msg.contains("timed out")
}

fn handoff_error_message(msg: &str, device_id: &str) -> String {
    if msg.contains("Peer rejected LAN handshake") {
        format!(
            "Peer {device_id} rejected the LAN handshake ({msg}). Confirm both devices are still paired and the vault is unlocked on the receiver."
        )
    } else if msg.contains("Peer signature verification failed") {
        format!("{msg} Handoff to {device_id} was rejected during authentication.")
    } else if msg.contains("iroh connect failed") {
        format!(
            "Could not reach peer {device_id} over iroh/QUIC ({msg}). On the receiver Mac with Firewall ON: System Settings → Network → Firewall → Options → allow incoming for this exact build (SuchConfig Dev for tauri:dev, SuchConfig.app for DMG). QUIC uses inbound UDP. Also allow Local Network for the app. Keep LAN sync on both Macs, same Wi‑Fi, toggle LAN sync once on both, then retry."
        )
    } else {
        msg.to_string()
    }
}
