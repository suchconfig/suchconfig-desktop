#![allow(dead_code)]
//! Legacy raw TCP LAN transport from Phase I. Superseded by `iroh_transport` (iroh/QUIC).
//! Scheduled for removal after Handoff and delta streaming are ported to `SYNC_ALPN` streams.

use base64::engine::general_purpose;
use base64::Engine as _;
use parking_lot::Mutex;
use std::io::{ErrorKind, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use thiserror::Error;

use super::device::{verify_signature, DeviceIdentity};
use super::protocol::{
    decrypt_message, derive_session_key, encode_frame, encrypt_message,
    handshake_message, handshake_signing_bytes, deserialize_message, serialize_message,
    DeltaAckBody, DeltaBatchBody, HandshakeChallengeBody, HandshakeRejectBody,
    HandshakeResponseBody, MessageKind, ProtocolError, SessionCipher, SnapshotBundleBody,
    SnapshotRequestBody, WireMessage, PROTOCOL_VERSION,
};
use super::store::{PairedPeer, PeerStore};

const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;
const INBOUND_READ_TIMEOUT: Duration = Duration::from_secs(15);
const OUTBOUND_CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
const HANDSHAKE_WRITE_SETTLE: Duration = Duration::from_millis(100);

#[derive(Debug, Error)]
pub enum TransportError {
    #[error("io error: {0}")]
    Io(String),
    #[error("{0}")]
    Message(String),
}

impl From<ProtocolError> for TransportError {
    fn from(value: ProtocolError) -> Self {
        TransportError::Message(value.to_string())
    }
}

pub struct TransportServer {
    listen_port: Mutex<u16>,
    running: Arc<Mutex<bool>>,
    session_id: Arc<AtomicU64>,
    listener: Arc<Mutex<Option<Arc<TcpListener>>>>,
    identity: Arc<Mutex<Option<DeviceIdentity>>>,
    peers_path: Arc<Mutex<Option<PathBuf>>>,
}

impl Default for TransportServer {
    fn default() -> Self {
        Self {
            listen_port: Mutex::new(0),
            running: Arc::new(Mutex::new(false)),
            session_id: Arc::new(AtomicU64::new(0)),
            listener: Arc::new(Mutex::new(None)),
            identity: Arc::new(Mutex::new(None)),
            peers_path: Arc::new(Mutex::new(None)),
        }
    }
}

impl TransportServer {
    pub fn start(&self, app: &AppHandle) -> Result<u16, TransportError> {
        if *self.running.lock() {
            return Ok(self.listen_port());
        }

        let listener = bind_lan_listener()?;
        let port = listener
            .local_addr()
            .map_err(|e| TransportError::Io(e.to_string()))?
            .port();
        let listener = Arc::new(listener);
        let session_id = self.session_id.fetch_add(1, Ordering::SeqCst) + 1;
        *self.listen_port.lock() = port;
        *self.running.lock() = true;
        *self.listener.lock() = Some(Arc::clone(&listener));
        {
            let identity = DeviceIdentity::load_or_create(app)
                .map_err(|e| TransportError::Message(e.to_string()))?;
            *self.identity.lock() = Some(identity);
        }
        {
            let peers_path = peers_file_path(app).map_err(|e| TransportError::Message(e.to_string()))?;
            *self.peers_path.lock() = Some(peers_path);
        }

        let app_handle = app.clone();
        let running = Arc::clone(&self.running);
        let session = Arc::clone(&self.session_id);
        let identity = Arc::clone(&self.identity);
        let peers_path = Arc::clone(&self.peers_path);
        p2p_log(&format!("LAN transport listening on 0.0.0.0:{port} (session {session_id})"));
        thread::spawn(move || {
            accept_loop(
                app_handle,
                listener,
                running,
                session,
                session_id,
                identity,
                peers_path,
            )
        });
        Ok(port)
    }

    pub fn stop(&self) {
        *self.running.lock() = false;
        self.session_id.fetch_add(1, Ordering::SeqCst);
        let port = if let Some(listener) = self.listener.lock().take() {
            use socket2::SockRef;
            let port = listener
                .local_addr()
                .ok()
                .map(|a| a.port())
                .unwrap_or_else(|| *self.listen_port.lock());
            let _ = SockRef::from(&*listener).shutdown(Shutdown::Both);
            port
        } else {
            *self.listen_port.lock()
        };
        *self.listen_port.lock() = 0;
        p2p_log(&format!("LAN transport stopped (was port {port})"));
        thread::sleep(Duration::from_millis(350));
    }

    pub fn is_running(&self) -> bool {
        *self.running.lock()
    }

    pub fn listen_port(&self) -> u16 {
        *self.listen_port.lock()
    }
}

fn bind_lan_listener() -> Result<TcpListener, TransportError> {
    TcpListener::bind(("0.0.0.0", 0)).map_err(|e| TransportError::Io(e.to_string()))
}

fn accept_loop(
    app: AppHandle,
    listener: Arc<TcpListener>,
    running: Arc<Mutex<bool>>,
    session_id: Arc<AtomicU64>,
    local_session: u64,
    identity: Arc<Mutex<Option<DeviceIdentity>>>,
    peers_path: Arc<Mutex<Option<PathBuf>>>,
) {
    while *running.lock() && session_id.load(Ordering::SeqCst) == local_session {
        match listener.accept() {
            Ok((mut stream, addr)) => {
                if !*running.lock() || session_id.load(Ordering::SeqCst) != local_session {
                    p2p_log(&format!(
                        "inbound dropped from {addr}: stale LAN transport session {local_session}"
                    ));
                    continue;
                }
                let local_addr = stream.local_addr().ok();
                let Some(identity_snap) = identity.lock().clone() else {
                    p2p_log(&format!(
                        "inbound dropped from {addr}: LAN identity unavailable (transport restarting?)"
                    ));
                    continue;
                };
                let Some(peers_path_snap) = peers_path.lock().clone() else {
                    p2p_log(&format!(
                        "inbound dropped from {addr}: LAN peer store unavailable (transport restarting?)"
                    ));
                    continue;
                };
                p2p_log(&format!(
                    "inbound LAN connection from {addr} on local {} (session {local_session})",
                    local_addr
                        .map(|a| a.to_string())
                        .unwrap_or_else(|| "?".into())
                ));
                p2p_log(&format!("inbound waiting for initiator challenge from {addr}"));
                let remote_challenge = match read_raw_message_inbound(
                    &mut stream,
                    addr,
                    "inbound read peer challenge",
                ) {
                    Ok(msg) => msg,
                    Err(e) => {
                        p2p_log(&format!(
                            "inbound handshake read challenge failed from {addr}: {e}"
                        ));
                        emit_inbound_error(&app, &e);
                        continue;
                    }
                };
                let app_clone = app.clone();
                thread::spawn(move || {
                    match complete_inbound_handshake(
                        stream,
                        addr,
                        remote_challenge,
                        identity_snap,
                        peers_path_snap,
                    ) {
                        Ok(session) => {
                            if let Err(e) = run_inbound_session(app_clone.clone(), session) {
                                emit_inbound_error(&app_clone, &e);
                            }
                        }
                        Err(e) => emit_inbound_error(&app_clone, &e),
                    }
                });
            }
            Err(ref e) if e.kind() == ErrorKind::Interrupted => {}
            Err(e) => {
                if !*running.lock() || session_id.load(Ordering::SeqCst) != local_session {
                    break;
                }
                p2p_log(&format!("LAN accept error: {e}"));
            }
        }
    }
    p2p_log(&format!("LAN transport accept loop exited (session {local_session})"));
}

struct P2pSession {
    stream: TcpStream,
    cipher: SessionCipher,
}

pub struct HandoffSession {
    inner: P2pSession,
}

impl P2pSession {
    fn connect(
        app: &AppHandle,
        host: &str,
        port: u16,
        expected_device_id: &str,
    ) -> Result<Self, TransportError> {
        let addr = format!("{host}:{port}");
        p2p_log(&format!("outbound LAN connect to {addr}"));

        let identity =
            DeviceIdentity::load_or_create(app).map_err(|e| TransportError::Message(e.to_string()))?;
        let local_id = identity.record.device_id.clone();
        let (challenge_bytes, local_nonce_b64) = local_handshake_challenge(&local_id)?;

        let mut stream = connect_with_timeout(&addr, OUTBOUND_CONNECT_TIMEOUT)?;
        configure_outbound_stream(&stream)?;
        std::thread::sleep(HANDSHAKE_WRITE_SETTLE);
        write_raw_frame(&mut stream, &challenge_bytes, "outbound handshake challenge")?;
        p2p_log(&format!(
            "outbound handshake challenge sent ({} bytes) to {addr}",
            challenge_bytes.len()
        ));

        let remote_challenge = read_raw_message(&mut stream, "outbound read peer challenge")?;
        if remote_challenge.kind == MessageKind::HandshakeReject {
            let body: HandshakeRejectBody = serde_json::from_value(remote_challenge.body)
                .map_err(|e| TransportError::Message(e.to_string()))?;
            return Err(TransportError::Message(format!(
                "Peer rejected LAN handshake at {host}:{port}: {}",
                body.reason
            )));
        }
        if remote_challenge.kind != MessageKind::HandshakeChallenge {
            return Err(TransportError::Message(format!(
                "LAN endpoint at {host}:{port} sent unexpected handshake message."
            )));
        }
        let remote_body: HandshakeChallengeBody = serde_json::from_value(remote_challenge.body)
            .map_err(|e| TransportError::Message(e.to_string()))?;

        if remote_body.device_id != expected_device_id {
            return Err(TransportError::Message(format!(
                "LAN endpoint at {host}:{port} answered as {} but handoff expected {expected_device_id}. Wait for mDNS to refresh the peer port, then retry.",
                remote_body.device_id
            )));
        }

        if !is_trusted_peer(app, &remote_body.device_id) {
            return Err(TransportError::Message(
                "Rejected connection from unpaired peer.".into(),
            ));
        }

        let peer = find_peer(app, &remote_body.device_id)?;
        let sign_bytes = handshake_signing_bytes(&local_id, &remote_body.nonce_b64);
        let sig = general_purpose::STANDARD.encode(identity.sign(&sign_bytes));
        let response = WireMessage {
            v: PROTOCOL_VERSION,
            kind: MessageKind::HandshakeResponse,
            body: serde_json::to_value(HandshakeResponseBody {
                device_id: local_id.clone(),
                signature_b64: sig.clone(),
            })
            .map_err(|e| TransportError::Message(e.to_string()))?,
        };
        write_raw_frame(&mut stream, &serialize_message(&response)?, "outbound handshake response")?;

        let remote_response = read_raw_message(&mut stream, "outbound read peer response")?;
        let remote_resp: HandshakeResponseBody = serde_json::from_value(remote_response.body)
            .map_err(|e| TransportError::Message(e.to_string()))?;

        verify_peer_signature(&peer.public_key_b64, &remote_resp, &local_nonce_b64)?;

        let local_sig = general_purpose::STANDARD
            .decode(sig.trim())
            .map_err(|e| TransportError::Message(e.to_string()))?;
        let remote_sig = general_purpose::STANDARD
            .decode(remote_resp.signature_b64.trim())
            .map_err(|e| TransportError::Message(e.to_string()))?;
        let session_key = derive_session_key(&local_sig, &remote_sig);

        p2p_log(&format!("outbound LAN handshake ok with {}", remote_body.device_id));
        Ok(Self {
            stream,
            cipher: SessionCipher::new(&session_key),
        })
    }

    fn send_encrypted(&mut self, msg: &WireMessage) -> Result<(), TransportError> {
        let encrypted = encrypt_message(&self.cipher, msg)?;
        write_raw_frame(&mut self.stream, &encrypted, "encrypted message")
    }

    fn recv_encrypted(&mut self) -> Result<WireMessage, TransportError> {
        let payload = read_raw_payload(&mut self.stream, "encrypted payload")?;
        decrypt_message(&self.cipher, &payload).map_err(|e| TransportError::Message(e.to_string()))
    }
}

pub fn connect_handoff(
    app: &AppHandle,
    host: &str,
    port: u16,
    expected_device_id: &str,
) -> Result<HandoffSession, TransportError> {
    Ok(HandoffSession {
        inner: P2pSession::connect(app, host, port, expected_device_id)?,
    })
}

pub fn send_handoff_bundles(
    app: &AppHandle,
    session: &mut HandoffSession,
    bundles: &[(String, String)],
) -> Result<(), TransportError> {
    let vaults: Vec<String> = bundles.iter().map(|(v, _)| v.clone()).collect();

    session.inner.send_encrypted(&WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::SnapshotRequest,
        body: serde_json::to_value(SnapshotRequestBody { vaults })
            .map_err(|e| TransportError::Message(e.to_string()))?,
    })?;

    for (vault, snapshot_b64) in bundles {
        session.inner.send_encrypted(&WireMessage {
            v: PROTOCOL_VERSION,
            kind: MessageKind::SnapshotBundle,
            body: serde_json::to_value(SnapshotBundleBody {
                vault: vault.clone(),
                snapshot_base64: snapshot_b64.clone(),
            })
            .map_err(|e| TransportError::Message(e.to_string()))?,
        })?;
    }

    session.inner.send_encrypted(&WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::SnapshotComplete,
        body: serde_json::json!({}),
    })?;

    let _ = app.emit(
        "p2p:handoff-complete",
        serde_json::json!({ "direction": "outbound" }),
    );
    Ok(())
}

pub fn send_delta_batch(
    app: &AppHandle,
    host: &str,
    port: u16,
    expected_device_id: &str,
    updates: Vec<super::protocol::DeltaUpdate>,
) -> Result<(), TransportError> {
    let mut session = P2pSession::connect(app, host, port, expected_device_id)?;
    session.send_encrypted(&WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::DeltaBatch,
        body: serde_json::to_value(DeltaBatchBody { updates })
            .map_err(|e| TransportError::Message(e.to_string()))?,
    })?;
    let _ = session.recv_encrypted()?;
    Ok(())
}

struct InboundSession {
    stream: TcpStream,
    cipher: SessionCipher,
    peer_device_id: String,
}

fn read_exact_inbound(
    stream: &mut TcpStream,
    buf: &mut [u8],
    addr: SocketAddr,
    step: &str,
) -> Result<(), TransportError> {
    use std::os::fd::AsRawFd;

    let fd = stream.as_raw_fd();
    let deadline = std::time::Instant::now() + INBOUND_READ_TIMEOUT;
    let mut filled = 0;
    let mut zero_avail_polls = 0u32;
    while filled < buf.len() {
        let remaining_ms = (deadline - std::time::Instant::now())
            .as_millis()
            .min(i32::MAX as u128) as i32;
        if remaining_ms <= 0 {
            let avail = inbound_bytes_available(fd);
            return Err(TransportError::Io(format!(
                "{step} from {addr}: timed out waiting for inbound data (avail={avail})"
            )));
        }
        let mut pollfd = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        let rc = unsafe { libc::poll(&mut pollfd, 1, remaining_ms) };
        match rc {
            0 => {
                let avail = inbound_bytes_available(fd);
                return Err(TransportError::Io(format!(
                    "{step} from {addr}: timed out waiting for inbound data (avail={avail})"
                )));
            }
            -1 => {
                return Err(TransportError::Io(format!(
                    "{step} from {addr}: poll: {}",
                    std::io::Error::last_os_error()
                )));
            }
            _ => {
                let revents = pollfd.revents;
                if revents & (libc::POLLERR | libc::POLLNVAL) != 0 {
                    return Err(TransportError::Io(format!(
                        "{step} from {addr}: inbound socket error (poll revents={revents})"
                    )));
                }
                if revents & libc::POLLHUP != 0 && revents & libc::POLLIN == 0 {
                    return Err(TransportError::Io(format!(
                        "{step} from {addr}: peer disconnected before inbound data (poll revents={revents})"
                    )));
                }
                if revents & libc::POLLIN != 0 {
                    let avail = inbound_bytes_available(fd);
                    if avail == 0 {
                        zero_avail_polls += 1;
                        if zero_avail_polls == 1 || zero_avail_polls % 40 == 0 {
                            p2p_log(&format!(
                                "inbound {step} from {addr}: poll POLLIN but avail=0, waiting (pass {zero_avail_polls}, revents={revents})"
                            ));
                        }
                        continue;
                    }
                    p2p_log(&format!(
                        "inbound {step} from {addr}: reading {}/{} bytes (avail={avail}, revents={revents})",
                        buf.len() - filled,
                        buf.len(),
                        avail = avail
                    ));
                    let n = unsafe {
                        libc::recv(
                            fd,
                            buf[filled..].as_mut_ptr() as *mut libc::c_void,
                            buf.len() - filled,
                            0,
                        )
                    };
                    if n < 0 {
                        let err = std::io::Error::last_os_error();
                        if err.kind() == ErrorKind::WouldBlock
                            || err.raw_os_error() == Some(libc::EAGAIN)
                        {
                            continue;
                        }
                        return Err(TransportError::Io(format!(
                            "{step} from {addr}: {err} (poll revents={revents}, avail={avail})"
                        )));
                    }
                    if n == 0 {
                        return Err(TransportError::Io(format!(
                            "{step} from {addr}: connection closed after partial read (expected {} bytes, avail was {avail})",
                            buf.len()
                        )));
                    }
                    filled += n as usize;
                }
            }
        }
    }
    Ok(())
}

fn read_raw_payload_inbound(
    stream: &mut TcpStream,
    addr: SocketAddr,
    step: &str,
) -> Result<Vec<u8>, TransportError> {
    let mut len_buf = [0u8; 4];
    read_exact_inbound(
        stream,
        &mut len_buf,
        addr,
        &format!("{step} length"),
    )?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len > MAX_FRAME_BYTES {
        return Err(TransportError::Message(format!(
            "LAN frame too large ({len} bytes, max {MAX_FRAME_BYTES})"
        )));
    }
    let mut payload = vec![0u8; len];
    if len > 0 {
        read_exact_inbound(
            stream,
            &mut payload,
            addr,
            &format!("{step} payload"),
        )?;
    }
    Ok(payload)
}

fn read_raw_message_inbound(
    stream: &mut TcpStream,
    addr: SocketAddr,
    step: &str,
) -> Result<WireMessage, TransportError> {
    let payload = read_raw_payload_inbound(stream, addr, step)?;
    deserialize_message(&payload).map_err(|e| TransportError::Message(e.to_string()))
}

fn complete_inbound_handshake(
    mut stream: TcpStream,
    addr: SocketAddr,
    remote_challenge: WireMessage,
    identity: DeviceIdentity,
    peers_path: PathBuf,
) -> Result<InboundSession, TransportError> {
    let local_id = identity.record.device_id.clone();
    let (challenge_bytes, local_nonce_b64) = local_handshake_challenge(&local_id)?;
    write_raw_frame(&mut stream, &challenge_bytes, "inbound handshake challenge")?;
    p2p_log(&format!("inbound handshake challenge sent to {addr}"));

    if remote_challenge.kind != MessageKind::HandshakeChallenge {
        let reason = format!(
            "Expected handshake challenge from {addr}, got {:?}.",
            remote_challenge.kind
        );
        let _ = send_handshake_reject(&mut stream, &reason);
        return Err(TransportError::Message(reason));
    }

    let remote_body: HandshakeChallengeBody = match serde_json::from_value(remote_challenge.body) {
        Ok(body) => body,
        Err(e) => {
            let reason = format!("Invalid handshake challenge from {addr}: {e}");
            let _ = send_handshake_reject(&mut stream, &reason);
            return Err(TransportError::Message(reason));
        }
    };

    p2p_log(&format!(
        "inbound handshake challenge from {} ({addr})",
        remote_body.device_id
    ));

    if !is_trusted_peer_at_path(&peers_path, &remote_body.device_id) {
        let reason = format!(
            "Rejected LAN connection from unpaired device {} ({addr}). Re-pair both Macs in Settings → P2P.",
            remote_body.device_id
        );
        let _ = send_handshake_reject(&mut stream, &reason);
        return Err(TransportError::Message(reason));
    }

    let peer = match find_peer_at_path(&peers_path, &remote_body.device_id) {
        Ok(peer) => peer,
        Err(e) => {
            let reason = format!(
                "Peer lookup failed for {} ({addr}): {e}",
                remote_body.device_id
            );
            p2p_log(&format!("inbound handshake peer lookup failed: {reason}"));
            let _ = send_handshake_reject(&mut stream, &reason);
            return Err(TransportError::Message(reason));
        }
    };

    let sign_bytes = handshake_signing_bytes(&local_id, &remote_body.nonce_b64);
    let sig = general_purpose::STANDARD.encode(identity.sign(&sign_bytes));
    let response = WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::HandshakeResponse,
        body: serde_json::to_value(HandshakeResponseBody {
            device_id: local_id.clone(),
            signature_b64: sig.clone(),
        })
        .map_err(|e| TransportError::Message(e.to_string()))?,
    };
    write_raw_frame(&mut stream, &serialize_message(&response)?, "inbound handshake response")?;

    let remote_response =
        read_raw_message_inbound(&mut stream, addr, "inbound read peer response")?;
    let remote_resp: HandshakeResponseBody = serde_json::from_value(remote_response.body)
        .map_err(|e| TransportError::Message(e.to_string()))?;

    verify_peer_signature(&peer.public_key_b64, &remote_resp, &local_nonce_b64)?;

    let local_sig = general_purpose::STANDARD
        .decode(sig.trim())
        .map_err(|e| TransportError::Message(e.to_string()))?;
    let remote_sig = general_purpose::STANDARD
        .decode(remote_resp.signature_b64.trim())
        .map_err(|e| TransportError::Message(e.to_string()))?;
    let session_key = derive_session_key(&local_sig, &remote_sig);
    let cipher = SessionCipher::new(&session_key);

    p2p_log(&format!(
        "inbound LAN handshake ok with {} ({addr})",
        remote_body.device_id
    ));

    Ok(InboundSession {
        stream,
        cipher,
        peer_device_id: remote_body.device_id,
    })
}

fn run_inbound_session(app: AppHandle, mut session: InboundSession) -> Result<(), TransportError> {
    let peer_device_id = session.peer_device_id.clone();
    let cipher = &session.cipher;
    let stream = &mut session.stream;

    loop {
        let peer_addr = stream
            .peer_addr()
            .unwrap_or_else(|_| SocketAddr::from(([0, 0, 0, 0], 0)));
        let payload = read_raw_payload_inbound(stream, peer_addr, "inbound encrypted payload")?;
        let msg = decrypt_message(cipher, &payload).map_err(|e| TransportError::Message(e.to_string()))?;
        match msg.kind {
            MessageKind::SnapshotRequest => {
                let _ = app.emit(
                    "p2p:handoff-request",
                    serde_json::json!({ "peerDeviceId": peer_device_id }),
                );
            }
            MessageKind::SnapshotBundle => {
                let body: SnapshotBundleBody = serde_json::from_value(msg.body)
                    .map_err(|e| TransportError::Message(e.to_string()))?;
                let _ = app.emit(
                    "p2p:handoff-bundle",
                    serde_json::json!({
                        "peerDeviceId": peer_device_id,
                        "vault": body.vault,
                        "snapshotBase64": body.snapshot_base64,
                    }),
                );
            }
            MessageKind::SnapshotComplete => {
                let _ = app.emit(
                    "p2p:handoff-complete",
                    serde_json::json!({
                        "peerDeviceId": peer_device_id,
                        "direction": "inbound",
                    }),
                );
                break;
            }
            MessageKind::DeltaBatch => {
                let body: DeltaBatchBody = serde_json::from_value(msg.body)
                    .map_err(|e| TransportError::Message(e.to_string()))?;
                let count = body.updates.len() as u32;
                let _ = app.emit(
                    "p2p:delta-received",
                    serde_json::json!({
                        "peerDeviceId": peer_device_id,
                        "updates": body.updates,
                    }),
                );
                let ack = WireMessage {
                    v: PROTOCOL_VERSION,
                    kind: MessageKind::DeltaAck,
                    body: serde_json::to_value(DeltaAckBody { accepted: count })
                        .map_err(|e| TransportError::Message(e.to_string()))?,
                };
                let encrypted = encrypt_message(cipher, &ack)?;
                write_raw_frame(stream, &encrypted, "inbound delta ack")?;
                break;
            }
            _ => {}
        }
    }

    Ok(())
}

fn local_handshake_challenge(device_id: &str) -> Result<(Vec<u8>, String), TransportError> {
    let bytes = handshake_message(device_id).map_err(|e| TransportError::Message(e.to_string()))?;
    let msg = deserialize_message(&bytes).map_err(|e| TransportError::Message(e.to_string()))?;
    let body: HandshakeChallengeBody = serde_json::from_value(msg.body)
        .map_err(|e| TransportError::Message(e.to_string()))?;
    Ok((bytes, body.nonce_b64))
}

fn p2p_log(message: &str) {
    eprintln!("[suchconfig-p2p] {message}");
}

fn emit_sync_error(app: &AppHandle, err: &TransportError) {
    let message = err.to_string();
    p2p_log(&format!("sync error: {message}"));
    let _ = app.emit(
        "p2p:sync-error",
        serde_json::json!({ "message": message }),
    );
}

fn send_handshake_reject(stream: &mut TcpStream, reason: &str) -> Result<(), TransportError> {
    let msg = WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::HandshakeReject,
        body: serde_json::to_value(HandshakeRejectBody {
            reason: reason.to_string(),
        })
        .map_err(|e| TransportError::Message(e.to_string()))?,
    };
    write_raw_frame(stream, &serialize_message(&msg)?, "handshake reject")?;
    shutdown_stream(stream);
    Ok(())
}

fn shutdown_stream(stream: &mut TcpStream) {
    let _ = stream.shutdown(Shutdown::Both);
}

fn peers_file_path(app: &AppHandle) -> Result<PathBuf, TransportError> {
    use super::device::device_path;
    let device_path = device_path(app).map_err(|e| TransportError::Message(e.to_string()))?;
    Ok(device_path
        .parent()
        .ok_or_else(|| TransportError::Message("P2P data directory unavailable.".into()))?
        .join(super::store::PEERS_FILENAME))
}

fn is_trusted_peer(app: &AppHandle, device_id: &str) -> bool {
    PeerStore::list(app)
        .ok()
        .map(|peers| peers.iter().any(|p| p.device_id == device_id))
        .unwrap_or(false)
}

fn is_trusted_peer_at_path(peers_path: &PathBuf, device_id: &str) -> bool {
    PeerStore::list_at_path(peers_path)
        .ok()
        .map(|peers| peers.iter().any(|p| p.device_id == device_id))
        .unwrap_or(false)
}

fn find_peer(app: &AppHandle, device_id: &str) -> Result<PairedPeer, TransportError> {
    PeerStore::list(app)
        .map_err(|e| TransportError::Message(e.to_string()))?
        .into_iter()
        .find(|p| p.device_id == device_id)
        .ok_or_else(|| TransportError::Message("Peer not found.".into()))
}

fn find_peer_at_path(peers_path: &PathBuf, device_id: &str) -> Result<PairedPeer, TransportError> {
    PeerStore::list_at_path(peers_path)
        .map_err(|e| TransportError::Message(e.to_string()))?
        .into_iter()
        .find(|p| p.device_id == device_id)
        .ok_or_else(|| TransportError::Message("Peer not found.".into()))
}

fn verify_peer_signature(
    public_key_b64: &str,
    remote_resp: &HandshakeResponseBody,
    nonce_b64: &str,
) -> Result<(), TransportError> {
    let remote_sign_bytes = handshake_signing_bytes(&remote_resp.device_id, nonce_b64);
    if !verify_signature(public_key_b64, &remote_sign_bytes, &remote_resp.signature_b64) {
        return Err(TransportError::Message(format!(
            "Peer signature verification failed for {}. Re-pair both devices if this persists.",
            remote_resp.device_id
        )));
    }
    Ok(())
}

fn emit_inbound_error(app: &AppHandle, err: &TransportError) {
    p2p_log(&format!("inbound sync error: {err}"));
    if matches!(err, TransportError::Io(_)) {
        return;
    }
    let msg = err.to_string();
    if msg.contains("expected value at line 1") {
        return;
    }
    emit_sync_error(app, err);
}

fn connect_with_timeout(addr: &str, timeout: Duration) -> Result<TcpStream, TransportError> {
    use std::net::ToSocketAddrs;

    let mut resolved: Vec<SocketAddr> = addr
        .to_socket_addrs()
        .map_err(|e| TransportError::Io(format!("resolve {addr}: {e}")))?
        .collect();
    resolved.sort_by_key(|a| !a.is_ipv4());

    let mut last_err =
        TransportError::Io(format!("no socket address resolved for {addr}"));
    for socket_addr in resolved {
        match TcpStream::connect_timeout(&socket_addr, timeout) {
            Ok(stream) => return Ok(stream),
            Err(e) => last_err = TransportError::Io(e.to_string()),
        }
    }
    Err(last_err)
}

fn try_set_tcp_nodelay(stream: &TcpStream, direction: &str) {
    use socket2::SockRef;

    if stream.set_nodelay(true).is_ok() {
        return;
    }

    if SockRef::from(stream).set_nodelay(true).is_ok() {
        return;
    }

    p2p_log(&format!(
        "{direction} set nodelay skipped (non-fatal; TCP_NODELAY unavailable on this socket)"
    ));
}

fn configure_outbound_stream(stream: &TcpStream) -> Result<(), TransportError> {
    use socket2::SockRef;
    let sock = SockRef::from(stream);
    sock.set_nonblocking(false).map_err(|e| {
        TransportError::Io(format!("outbound set blocking mode: {e}"))
    })?;
    try_set_tcp_nodelay(stream, "outbound");
    let timeout = Some(Duration::from_secs(120));
    sock.set_read_timeout(timeout).map_err(|e| {
        TransportError::Io(format!("outbound set read timeout: {e}"))
    })?;
    sock.set_write_timeout(timeout).map_err(|e| {
        TransportError::Io(format!("outbound set write timeout: {e}"))
    })?;
    Ok(())
}

fn inbound_bytes_available(fd: i32) -> i32 {
    let mut avail: i32 = 0;
    unsafe {
        if libc::ioctl(fd, libc::FIONREAD, &mut avail as *mut i32) != 0 {
            return -1;
        }
    }
    avail
}

fn write_raw_frame(stream: &mut TcpStream, payload: &[u8], step: &str) -> Result<(), TransportError> {
    let frame = encode_frame(payload);
    stream
        .write_all(&frame)
        .map_err(|e| TransportError::Io(format!("{step}: {e}")))?;
    stream
        .flush()
        .map_err(|e| TransportError::Io(format!("{step} flush: {e}")))?;
    Ok(())
}

fn read_exact_outbound(
    stream: &mut TcpStream,
    buf: &mut [u8],
    step: &str,
) -> Result<(), TransportError> {
    stream.read_exact(buf).map_err(|e| {
        let msg = match e.kind() {
            ErrorKind::UnexpectedEof => format!(
                "{step}: connection closed after partial read (expected {} bytes)",
                buf.len()
            ),
            _ => format!("{step}: {e}"),
        };
        TransportError::Io(msg)
    })
}

fn read_raw_payload(stream: &mut TcpStream, step: &str) -> Result<Vec<u8>, TransportError> {
    let mut len_buf = [0u8; 4];
    read_exact_outbound(stream, &mut len_buf, &format!("{step} length"))?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len > MAX_FRAME_BYTES {
        return Err(TransportError::Message(format!(
            "LAN frame too large ({len} bytes, max {MAX_FRAME_BYTES})"
        )));
    }
    let mut payload = vec![0u8; len];
    read_exact_outbound(stream, &mut payload, &format!("{step} payload"))?;
    Ok(payload)
}

fn read_raw_message(stream: &mut TcpStream, step: &str) -> Result<WireMessage, TransportError> {
    let payload = read_raw_payload(stream, step)?;
    deserialize_message(&payload).map_err(|e| TransportError::Message(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::p2p::device::{verify_signature, DeviceIdentity, DeviceRecord};
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;

    fn test_identity(label: &str) -> DeviceIdentity {
        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key = signing_key.verifying_key();
        DeviceIdentity::from_record(DeviceRecord {
            device_id: format!("{label}-device-id"),
            device_name: label.to_string(),
            public_key_b64: general_purpose::STANDARD.encode(verifying_key.as_bytes()),
            secret_key_b64: general_purpose::STANDARD.encode(signing_key.to_bytes()),
            created_at: chrono::Utc::now().to_rfc3339(),
        })
        .expect("identity")
    }

    #[test]
    fn inbound_read_waits_for_late_client_write() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");

        let server = thread::spawn(move || {
            let (mut stream, peer) = listener.accept().expect("accept");
            let payload = read_raw_payload_inbound(&mut stream, peer, "late client write").expect("read");
            deserialize_message(&payload).expect("message")
        });

        thread::sleep(Duration::from_millis(30));
        let mut client = TcpStream::connect(addr).expect("connect");
        configure_outbound_stream(&client).expect("configure outbound");
        thread::sleep(Duration::from_millis(30));
        let (challenge_bytes, _) = local_handshake_challenge("late-client").expect("challenge");
        write_raw_frame(&mut client, &challenge_bytes, "write").expect("write");

        let msg = server.join().expect("server");
        assert_eq!(msg.kind, MessageKind::HandshakeChallenge);
    }

    #[test]
    fn handshake_reject_frame_round_trip() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");

        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().expect("accept");
            let mut stream = stream;
            send_handshake_reject(&mut stream, "unpaired device").expect("reject");
        });

        let mut client = TcpStream::connect(addr).expect("connect");
        configure_outbound_stream(&client).expect("configure outbound");
        write_raw_frame(&mut client, b"probe", "probe").expect("write");
        let msg = read_raw_message(&mut client, "read reject").expect("read");
        assert_eq!(msg.kind, MessageKind::HandshakeReject);
        let body: HandshakeRejectBody =
            serde_json::from_value(msg.body).expect("reject body");
        assert!(body.reason.contains("unpaired device"));
        server.join().expect("server");
    }

    #[test]
    fn inbound_reads_initiator_challenge_before_sending() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");

        let server = thread::spawn(move || {
            let (mut stream, peer) = listener.accept().expect("accept");
            let payload = read_raw_payload_inbound(&mut stream, peer, "read initiator").expect("read");
            let initiator_msg = deserialize_message(&payload).expect("message");
            let (local_bytes, _) = local_handshake_challenge("responder-device").expect("challenge");
            write_raw_frame(&mut stream, &local_bytes, "inbound challenge").expect("write");
            initiator_msg
        });

        let mut client = TcpStream::connect(addr).expect("connect");
        configure_outbound_stream(&client).expect("configure outbound");
        let (init_bytes, _) = local_handshake_challenge("initiator-device").expect("challenge");
        write_raw_frame(&mut client, &init_bytes, "outbound challenge").expect("write");
        let payload = read_raw_payload(&mut client, "read responder").expect("read");
        let msg = deserialize_message(&payload).expect("message");
        assert_eq!(msg.kind, MessageKind::HandshakeChallenge);

        let initiator_msg = server.join().expect("server");
        assert_eq!(initiator_msg.kind, MessageKind::HandshakeChallenge);
    }

    #[test]
    fn handshake_response_verifies_against_local_challenge_nonce() {
        let initiator = test_identity("initiator");
        let responder = test_identity("responder");

        let (_, initiator_nonce) =
            local_handshake_challenge(&initiator.record.device_id).expect("initiator challenge");
        let (_, responder_nonce) =
            local_handshake_challenge(&responder.record.device_id).expect("responder challenge");

        let responder_sign_bytes =
            handshake_signing_bytes(&responder.record.device_id, &initiator_nonce);
        let responder_sig =
            general_purpose::STANDARD.encode(responder.sign(&responder_sign_bytes));
        let responder_resp = HandshakeResponseBody {
            device_id: responder.record.device_id.clone(),
            signature_b64: responder_sig,
        };

        assert!(verify_signature(
            &responder.record.public_key_b64,
            &handshake_signing_bytes(&responder_resp.device_id, &initiator_nonce),
            &responder_resp.signature_b64,
        ));
        assert!(!verify_signature(
            &responder.record.public_key_b64,
            &handshake_signing_bytes(&responder_resp.device_id, &responder_nonce),
            &responder_resp.signature_b64,
        ));
    }
}
