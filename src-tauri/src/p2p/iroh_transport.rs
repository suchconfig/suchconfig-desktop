use base64::engine::general_purpose;
use base64::Engine as _;
use std::net::SocketAddr;

use iroh::{
    endpoint::{presets, Connection, PortmapperConfig},
    protocol::{AcceptError, ProtocolHandler, Router},
    Endpoint, EndpointAddr, EndpointId, PublicKey, RelayMode, SecretKey, TransportAddr,
};
use iroh_mdns_address_lookup::MdnsAddressLookup;
use parking_lot::Mutex;
use tauri::AppHandle;
use thiserror::Error;

use super::device::DeviceIdentity;
use super::iroh_sync::{
    connect_handoff as sync_connect_handoff, handle_inbound_connection, run_spike_echo,
    IrohHandoffSession, SPIKE_ECHO_MESSAGE,
};
use super::protocol::SYNC_ALPN;
use super::store::PeerStore;

pub use super::iroh_sync::IrohSpikeEchoResult;

#[derive(Debug, Error)]
pub enum IrohTransportError {
    #[error("{0}")]
    Message(String),
}

struct IrohRuntime {
    _runtime: tokio::runtime::Runtime,
    router: Router,
    endpoint: Endpoint,
}

pub struct IrohTransport {
    inner: Mutex<Option<IrohRuntime>>,
    endpoint_id_b64: Mutex<String>,
    handoff_session: Mutex<Option<IrohHandoffSession>>,
}

impl Default for IrohTransport {
    fn default() -> Self {
        Self {
            inner: Mutex::new(None),
            endpoint_id_b64: Mutex::new(String::new()),
            handoff_session: Mutex::new(None),
        }
    }
}

impl IrohTransport {
    pub fn is_running(&self) -> bool {
        self.inner.lock().is_some()
    }

    pub fn endpoint_id_b64(&self) -> String {
        self.endpoint_id_b64.lock().clone()
    }

    pub fn direct_ipv4_dial_addrs(&self) -> Vec<SocketAddr> {
        let guard = self.inner.lock();
        let Some(runtime) = guard.as_ref() else {
            return Vec::new();
        };
        let handle = runtime._runtime.handle().clone();
        let endpoint = runtime.endpoint.clone();
        drop(guard);

        handle.block_on(async move {
            endpoint
                .addr()
                .addrs
                .into_iter()
                .filter_map(|addr| match addr {
                    TransportAddr::Ip(socket) if socket.ip().is_ipv4() => Some(socket),
                    _ => None,
                })
                .collect()
        })
    }

    pub fn start(&self, app: &AppHandle) -> Result<String, IrohTransportError> {
        if self.is_running() {
            return Ok(self.endpoint_id_b64());
        }

        let identity = DeviceIdentity::load_or_create(app)
            .map_err(|e| IrohTransportError::Message(e.to_string()))?;
        let secret_key = secret_key_from_identity(&identity)?;
        let endpoint_id_b64 = identity.record.public_key_b64.clone();

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| IrohTransportError::Message(e.to_string()))?;

        let app_handle = app.clone();
        let (router, endpoint) = runtime
            .block_on(start_endpoint(secret_key, app_handle))
            .map_err(|e| IrohTransportError::Message(e.to_string()))?;

        eprintln!(
            "[suchconfig-p2p] iroh endpoint online id={endpoint_id_b64} alpn={}",
            String::from_utf8_lossy(SYNC_ALPN)
        );

        *self.endpoint_id_b64.lock() = endpoint_id_b64.clone();
        *self.handoff_session.lock() = None;
        *self.inner.lock() = Some(IrohRuntime {
            _runtime: runtime,
            router,
            endpoint,
        });

        Ok(endpoint_id_b64)
    }

    pub fn stop(&self) {
        *self.handoff_session.lock() = None;
        let runtime = self.inner.lock().take();
        if let Some(runtime) = runtime {
            let _ = runtime._runtime.block_on(async {
                if let Err(err) = runtime.router.shutdown().await {
                    eprintln!("[suchconfig-p2p] iroh router shutdown: {err}");
                }
                runtime.endpoint.close().await;
            });
            eprintln!("[suchconfig-p2p] iroh transport stopped");
        }
        *self.endpoint_id_b64.lock() = String::new();
    }

    pub fn spike_echo(
        &self,
        app: &AppHandle,
        device_id: &str,
        dial_addrs: Vec<SocketAddr>,
    ) -> Result<IrohSpikeEchoResult, IrohTransportError> {
        let guard = self.inner.lock();
        let runtime = guard.as_ref().ok_or_else(|| {
            IrohTransportError::Message("iroh transport is not running; enable LAN sync".into())
        })?;
        let endpoint = runtime.endpoint.clone();
        let handle = runtime._runtime.handle().clone();
        drop(guard);

        let peer_id = peer_endpoint_id(app, device_id)?;
        let remote_endpoint_id = general_purpose::STANDARD.encode(peer_id.as_bytes());
        let device_id = device_id.to_string();

        handle.block_on(async move {
            eprintln!(
                "[suchconfig-p2p] iroh spike connect -> {remote_endpoint_id} for peer {device_id}"
            );
            if dial_addrs.is_empty() {
                eprintln!(
                    "[suchconfig-p2p] iroh spike dial: no direct addrs from SuchConfig mDNS; using irohv1 lookup"
                );
            } else {
                eprintln!("[suchconfig-p2p] iroh spike dial addrs: {dial_addrs:?}");
            }
            let conn = connect_peer(
                &endpoint,
                peer_id,
                &dial_addrs,
                "iroh spike",
            )
            .await
            .map_err(IrohTransportError::Message)?;
            let echoed = run_spike_echo(&conn)
                .await
                .map_err(IrohTransportError::Message)?;
            eprintln!(
                "[suchconfig-p2p] iroh spike ok with {device_id}: echoed {} byte(s)",
                echoed.len()
            );
            Ok(IrohSpikeEchoResult {
                device_id,
                remote_endpoint_id,
                sent: String::from_utf8_lossy(SPIKE_ECHO_MESSAGE).into_owned(),
                echoed: String::from_utf8_lossy(&echoed).into_owned(),
                bytes_sent: SPIKE_ECHO_MESSAGE.len(),
                bytes_received: echoed.len(),
            })
        })
    }

    pub fn clear_handoff_session(&self) {
        *self.handoff_session.lock() = None;
    }

    pub fn connect_handoff(
        &self,
        app: &AppHandle,
        device_id: &str,
        dial_addrs: Vec<SocketAddr>,
    ) -> Result<(), IrohTransportError> {
        let guard = self.inner.lock();
        let runtime = guard.as_ref().ok_or_else(|| {
            IrohTransportError::Message("iroh transport is not running; enable LAN sync".into())
        })?;
        let endpoint = runtime.endpoint.clone();
        let handle = runtime._runtime.handle().clone();
        drop(guard);

        let peer_id = peer_endpoint_id(app, device_id)?;
        let remote_endpoint_id = general_purpose::STANDARD.encode(peer_id.as_bytes());
        let expected_device_id = device_id.to_string();
        let app = app.clone();

        let session = handle
            .block_on(async move {
                eprintln!(
                    "[suchconfig-p2p] iroh handoff connect -> {remote_endpoint_id} for peer {expected_device_id}"
                );
                if dial_addrs.is_empty() {
                    eprintln!(
                        "[suchconfig-p2p] iroh handoff dial: no direct addrs from SuchConfig mDNS; using irohv1 lookup"
                    );
                } else {
                    eprintln!("[suchconfig-p2p] iroh handoff dial addrs: {dial_addrs:?}");
                }
                let conn = connect_peer(
                    &endpoint,
                    peer_id,
                    &dial_addrs,
                    "iroh handoff",
                )
                .await?;
                sync_connect_handoff(&app, conn, &expected_device_id).await
            })
            .map_err(IrohTransportError::Message)?;

        *self.handoff_session.lock() = Some(session);
        Ok(())
    }

    pub fn send_handoff_bundles(
        &self,
        app: &AppHandle,
        bundles: Vec<(String, String)>,
    ) -> Result<(), IrohTransportError> {
        let guard = self.inner.lock();
        let runtime = guard.as_ref().ok_or_else(|| {
            IrohTransportError::Message("iroh transport is not running; enable LAN sync".into())
        })?;
        let handle = runtime._runtime.handle().clone();
        drop(guard);

        let mut session = self
            .handoff_session
            .lock()
            .take()
            .ok_or_else(|| IrohTransportError::Message("No active LAN handoff session.".into()))?;

        let app = app.clone();
        handle
            .block_on(async move { session.send_handoff_bundles(&app, &bundles).await })
            .map_err(IrohTransportError::Message)
    }
}

async fn connect_peer(
    endpoint: &Endpoint,
    peer_id: EndpointId,
    dial_addrs: &[SocketAddr],
    label: &str,
) -> Result<Connection, String> {
    if dial_addrs.is_empty() {
        return endpoint
            .connect(peer_id, SYNC_ALPN)
            .await
            .map_err(|e| format!("iroh connect failed: {e}"));
    }

    let direct_addr = EndpointAddr::from_parts(
        peer_id,
        dial_addrs.iter().copied().map(TransportAddr::Ip),
    );
    match endpoint.connect(direct_addr, SYNC_ALPN).await {
        Ok(conn) => Ok(conn),
        Err(direct_err) => {
            eprintln!(
                "[suchconfig-p2p] {label} direct dial failed ({direct_err}); retrying with irohv1 lookup"
            );
            endpoint
                .connect(peer_id, SYNC_ALPN)
                .await
                .map_err(|e| format!("iroh connect failed: {e}"))
        }
    }
}

async fn start_endpoint(secret_key: SecretKey, app: AppHandle) -> Result<(Router, Endpoint), String> {
    let endpoint = Endpoint::builder(presets::Minimal)
        .secret_key(secret_key)
        .relay_mode(RelayMode::Disabled)
        .portmapper_config(PortmapperConfig::Disabled)
        .address_lookup(MdnsAddressLookup::builder())
        .bind()
        .await
        .map_err(|e| e.to_string())?;

    if let Ok(exe) = std::env::current_exe() {
        eprintln!(
            "[suchconfig-p2p] iroh inbound UDP listener active — macOS Firewall: allow incoming for {}",
            exe.display()
        );
    }

    let router = Router::builder(endpoint.clone())
        .accept(SYNC_ALPN, SyncProtocolHandler { app })
        .spawn();

    Ok((router, endpoint))
}

#[derive(Debug, Clone)]
struct SyncProtocolHandler {
    app: AppHandle,
}

impl ProtocolHandler for SyncProtocolHandler {
    async fn accept(&self, connection: Connection) -> Result<(), AcceptError> {
        let app = self.app.clone();
        tokio::spawn(async move {
            if let Err(err) = handle_inbound_connection(app.clone(), connection).await {
                if !err.contains("connection closed") {
                    super::iroh_sync::emit_sync_error(&app, &err);
                }
            }
        });
        Ok(())
    }
}

fn secret_key_from_identity(identity: &DeviceIdentity) -> Result<SecretKey, IrohTransportError> {
    let secret_bytes = general_purpose::STANDARD
        .decode(identity.record.secret_key_b64.trim())
        .map_err(|_| IrohTransportError::Message("invalid device secret key".into()))?;
    let key_array: [u8; 32] = secret_bytes
        .try_into()
        .map_err(|_| IrohTransportError::Message("invalid device secret key length".into()))?;
    Ok(SecretKey::from_bytes(&key_array))
}

pub fn endpoint_id_from_public_key_b64(public_key_b64: &str) -> Result<EndpointId, IrohTransportError> {
    let pk_bytes = general_purpose::STANDARD
        .decode(public_key_b64.trim())
        .map_err(|_| IrohTransportError::Message("invalid peer public key".into()))?;
    let pk_array: [u8; 32] = pk_bytes
        .try_into()
        .map_err(|_| IrohTransportError::Message("invalid peer public key length".into()))?;
    PublicKey::from_bytes(&pk_array).map_err(|_| {
        IrohTransportError::Message("peer public key is not a valid iroh endpoint id".into())
    })
}

fn peer_endpoint_id(app: &AppHandle, device_id: &str) -> Result<EndpointId, IrohTransportError> {
    let peers = PeerStore::list(app).map_err(|e| IrohTransportError::Message(e.to_string()))?;
    let peer = peers
        .into_iter()
        .find(|p| p.device_id == device_id)
        .ok_or_else(|| {
            IrohTransportError::Message(format!("peer {device_id} is not paired locally"))
        })?;
    endpoint_id_from_public_key_b64(&peer.public_key_b64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;

    #[test]
    fn maps_ed25519_public_key_to_endpoint_id() {
        let signing_key = SigningKey::generate(&mut OsRng);
        let public_key_b64 = general_purpose::STANDARD.encode(signing_key.verifying_key().as_bytes());
        let endpoint_id = endpoint_id_from_public_key_b64(&public_key_b64).expect("endpoint id");
        assert_eq!(
            endpoint_id.as_bytes(),
            signing_key.verifying_key().as_bytes()
        );
    }
}
