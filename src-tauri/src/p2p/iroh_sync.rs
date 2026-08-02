use std::time::Duration;

use base64::engine::general_purpose;
use base64::Engine as _;
use iroh::endpoint::{Connection, RecvStream, SendStream};
use serde::Serialize;
use tauri::{AppHandle, Emitter};

use super::device::{verify_signature, DeviceIdentity};
use super::protocol::{
    decrypt_message, derive_session_key, encode_frame, encrypt_message, handshake_message,
    handshake_signing_bytes, deserialize_message, serialize_message, DeltaAckBody, DeltaBatchBody,
    HandshakeChallengeBody, HandshakeRejectBody, HandshakeResponseBody, MessageKind,
    ProtocolError, SessionCipher, SnapshotBundleBody, SnapshotRequestBody, WireMessage,
    PROTOCOL_VERSION,
};
use super::store::{PairedPeer, PeerStore};

pub const SPIKE_ECHO_MESSAGE: &[u8] = b"suchconfig-iroh-spike-v1";
const SPIKE_PREFIX: &[u8] = b"such";
const SPIKE_READ_LIMIT: usize = 256;
const MAX_FRAME_BYTES: usize = 32 * 1024 * 1024;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IrohSpikeEchoResult {
    pub device_id: String,
    pub remote_endpoint_id: String,
    pub sent: String,
    pub echoed: String,
    pub bytes_sent: usize,
    pub bytes_received: usize,
}

pub struct IrohHandoffSession {
    connection: Connection,
    send: SendStream,
    recv: RecvStream,
    cipher: SessionCipher,
}

impl IrohHandoffSession {
    pub async fn send_handoff_bundles(
        &mut self,
        app: &AppHandle,
        bundles: &[(String, String)],
    ) -> Result<(), String> {
        p2p_log(&format!(
            "iroh outbound handoff sending {} bundle(s)",
            bundles.len()
        ));
        tokio::task::yield_now().await;
        let vaults: Vec<String> = bundles.iter().map(|(v, _)| v.clone()).collect();

        send_encrypted(
            &mut self.send,
            &self.cipher,
            &WireMessage {
                v: PROTOCOL_VERSION,
                kind: MessageKind::SnapshotRequest,
                body: serde_json::to_value(SnapshotRequestBody { vaults })
                    .map_err(|e| e.to_string())?,
            },
        )
        .await?;

        for (vault, snapshot_b64) in bundles {
            send_encrypted(
                &mut self.send,
                &self.cipher,
                &WireMessage {
                    v: PROTOCOL_VERSION,
                    kind: MessageKind::SnapshotBundle,
                    body: serde_json::to_value(SnapshotBundleBody {
                        vault: vault.clone(),
                        snapshot_base64: snapshot_b64.clone(),
                    })
                    .map_err(|e| e.to_string())?,
                },
            )
            .await?;
        }

        send_encrypted(
            &mut self.send,
            &self.cipher,
            &WireMessage {
                v: PROTOCOL_VERSION,
                kind: MessageKind::SnapshotComplete,
                body: serde_json::json!({}),
            },
        )
        .await?;

        let _ = self.send.finish();

        match tokio::time::timeout(Duration::from_secs(120), read_message(&mut self.recv)).await {
            Ok(Ok(msg)) if msg.kind == MessageKind::DeltaAck => {
                p2p_log("iroh outbound handoff ack received");
            }
            Ok(Ok(msg)) => {
                return Err(format!(
                    "unexpected post-handoff message {:?}",
                    msg.kind
                ));
            }
            Ok(Err(err)) => return Err(err),
            Err(_) => {
                return Err("handoff timed out waiting for receiver ack".into());
            }
        }

        let _ = app.emit(
            "p2p:handoff-complete",
            serde_json::json!({ "direction": "outbound" }),
        );
        Ok(())
    }
}

impl Drop for IrohHandoffSession {
    fn drop(&mut self) {
        self.connection.close(0u32.into(), b"handoff-done");
    }
}

pub async fn run_spike_echo(conn: &Connection) -> Result<Vec<u8>, String> {
    let (mut send, mut recv) = conn
        .open_bi()
        .await
        .map_err(|e| format!("open bi stream: {e}"))?;
    send.write_all(SPIKE_ECHO_MESSAGE)
        .await
        .map_err(|e| format!("write spike payload: {e}"))?;
    send.finish()
        .map_err(|e| format!("finish send stream: {e}"))?;
    let response = recv
        .read_to_end(SPIKE_READ_LIMIT)
        .await
        .map_err(|e| format!("read spike echo: {e}"))?;
    if response != SPIKE_ECHO_MESSAGE {
        return Err(format!(
            "unexpected spike echo (got {} bytes)",
            response.len()
        ));
    }
    conn.close(0u32.into(), b"spike-ok");
    Ok(response)
}

pub async fn connect_handoff(
    app: &AppHandle,
    conn: Connection,
    expected_device_id: &str,
) -> Result<IrohHandoffSession, String> {
    let (mut send, mut recv) = conn
        .open_bi()
        .await
        .map_err(|e| format!("open bi stream: {e}"))?;

    let identity =
        DeviceIdentity::load_or_create(app).map_err(|e| e.to_string())?;
    let local_id = identity.record.device_id.clone();
    let (challenge_bytes, local_nonce_b64) = local_handshake_challenge(&local_id)?;

    write_frame(&mut send, &challenge_bytes).await?;
    p2p_log(&format!(
        "iroh outbound handshake challenge sent for peer {expected_device_id}"
    ));

    let remote_challenge = read_message(&mut recv).await?;
    if remote_challenge.kind == MessageKind::HandshakeReject {
        let body: HandshakeRejectBody = serde_json::from_value(remote_challenge.body)
            .map_err(|e| e.to_string())?;
        return Err(format!("Peer rejected LAN handshake: {}", body.reason));
    }
    if remote_challenge.kind != MessageKind::HandshakeChallenge {
        return Err("Peer sent unexpected handshake message.".into());
    }
    let remote_body: HandshakeChallengeBody = serde_json::from_value(remote_challenge.body)
        .map_err(|e| e.to_string())?;

    if remote_body.device_id != expected_device_id {
        return Err(format!(
            "Peer answered as {} but handoff expected {expected_device_id}.",
            remote_body.device_id
        ));
    }

    if !is_trusted_peer(app, &remote_body.device_id) {
        return Err("Rejected connection from unpaired peer.".into());
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
        .map_err(|e| e.to_string())?,
    };
    write_message(&mut send, &response).await?;

    let remote_response = read_message(&mut recv).await?;
    let remote_resp: HandshakeResponseBody = serde_json::from_value(remote_response.body)
        .map_err(|e| e.to_string())?;

    verify_peer_signature(&peer.public_key_b64, &remote_resp, &local_nonce_b64)?;

    let local_sig = general_purpose::STANDARD
        .decode(sig.trim())
        .map_err(|e| e.to_string())?;
    let remote_sig = general_purpose::STANDARD
        .decode(remote_resp.signature_b64.trim())
        .map_err(|e| e.to_string())?;
    let session_key = derive_session_key(&local_sig, &remote_sig);

    p2p_log(&format!(
        "iroh outbound handshake ok with {}",
        remote_body.device_id
    ));

    Ok(IrohHandoffSession {
        connection: conn,
        send,
        recv,
        cipher: SessionCipher::new(&session_key),
    })
}

pub async fn handle_inbound_connection(app: AppHandle, connection: Connection) -> Result<(), String> {
    let remote = connection.remote_id();
    let remote_b64 = general_purpose::STANDARD.encode(remote.as_bytes());
    p2p_log(&format!("iroh inbound connection from {remote_b64}"));

    let (mut send, mut recv) = connection
        .accept_bi()
        .await
        .map_err(|e| format!("accept bi stream: {e}"))?;

    let mut head = [0u8; 4];
    recv.read_exact(&mut head)
        .await
        .map_err(|e| format!("read stream header: {e}"))?;

    if &head == SPIKE_PREFIX {
        let mut tail = vec![0u8; SPIKE_ECHO_MESSAGE.len() - SPIKE_PREFIX.len()];
        recv.read_exact(&mut tail)
            .await
            .map_err(|e| format!("read spike tail: {e}"))?;
        let mut msg = Vec::with_capacity(SPIKE_ECHO_MESSAGE.len());
        msg.extend_from_slice(SPIKE_PREFIX);
        msg.extend_from_slice(&tail);
        if msg != SPIKE_ECHO_MESSAGE {
            return Err(format!(
                "unexpected spike payload (got {} bytes)",
                msg.len()
            ));
        }
        send.write_all(SPIKE_ECHO_MESSAGE)
            .await
            .map_err(|e| format!("write spike echo: {e}"))?;
        send.finish()
            .map_err(|e| format!("finish spike echo: {e}"))?;
        connection.closed().await;
        p2p_log(&format!("iroh inbound spike echo ok from {remote_b64}"));
        return Ok(());
    }

    let len = u32::from_be_bytes(head) as usize;
    if len > MAX_FRAME_BYTES {
        return Err(format!("LAN frame too large ({len} bytes)"));
    }
    let mut payload = vec![0u8; len];
    if len > 0 {
        recv.read_exact(&mut payload)
            .await
            .map_err(|e| format!("read handshake payload: {e}"))?;
    }
    let remote_challenge = deserialize_message(&payload).map_err(|e| e.to_string())?;

    let session = complete_inbound_handshake(app.clone(), send, recv, remote_challenge).await?;
    run_inbound_session(app, session).await
}

async fn complete_inbound_handshake(
    app: AppHandle,
    mut send: SendStream,
    mut recv: RecvStream,
    remote_challenge: WireMessage,
) -> Result<InboundSession, String> {
    let identity = DeviceIdentity::load_or_create(&app).map_err(|e| e.to_string())?;
    let local_id = identity.record.device_id.clone();
    let (challenge_bytes, local_nonce_b64) = local_handshake_challenge(&local_id)?;
    write_frame(&mut send, &challenge_bytes).await?;
    p2p_log("iroh inbound handshake challenge sent");

    if remote_challenge.kind != MessageKind::HandshakeChallenge {
        let reason = format!(
            "Expected handshake challenge, got {:?}.",
            remote_challenge.kind
        );
        let _ = send_handshake_reject(&mut send, &reason).await;
        return Err(reason);
    }

    let remote_body: HandshakeChallengeBody = match serde_json::from_value(remote_challenge.body) {
        Ok(body) => body,
        Err(e) => {
            let reason = format!("Invalid handshake challenge: {e}");
            let _ = send_handshake_reject(&mut send, &reason).await;
            return Err(reason);
        }
    };

    p2p_log(&format!(
        "iroh inbound handshake challenge from {}",
        remote_body.device_id
    ));

    if !is_trusted_peer(&app, &remote_body.device_id) {
        let reason = format!(
            "Rejected LAN connection from unpaired device {}. Re-pair both Macs in Settings → P2P.",
            remote_body.device_id
        );
        let _ = send_handshake_reject(&mut send, &reason).await;
        return Err(reason);
    }

    let peer = find_peer(&app, &remote_body.device_id)?;
    let sign_bytes = handshake_signing_bytes(&local_id, &remote_body.nonce_b64);
    let sig = general_purpose::STANDARD.encode(identity.sign(&sign_bytes));
    let response = WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::HandshakeResponse,
        body: serde_json::to_value(HandshakeResponseBody {
            device_id: local_id.clone(),
            signature_b64: sig.clone(),
        })
        .map_err(|e| e.to_string())?,
    };
    write_message(&mut send, &response).await?;

    let remote_response = read_message(&mut recv).await?;
    let remote_resp: HandshakeResponseBody = serde_json::from_value(remote_response.body)
        .map_err(|e| e.to_string())?;

    verify_peer_signature(&peer.public_key_b64, &remote_resp, &local_nonce_b64)?;

    let local_sig = general_purpose::STANDARD
        .decode(sig.trim())
        .map_err(|e| e.to_string())?;
    let remote_sig = general_purpose::STANDARD
        .decode(remote_resp.signature_b64.trim())
        .map_err(|e| e.to_string())?;
    let session_key = derive_session_key(&local_sig, &remote_sig);

    p2p_log(&format!(
        "iroh inbound handshake ok with {}",
        remote_body.device_id
    ));

    Ok(InboundSession {
        send,
        recv,
        cipher: SessionCipher::new(&session_key),
        peer_device_id: remote_body.device_id,
    })
}

struct InboundSession {
    send: SendStream,
    recv: RecvStream,
    cipher: SessionCipher,
    peer_device_id: String,
}

async fn run_inbound_session(app: AppHandle, mut session: InboundSession) -> Result<(), String> {
    let peer_device_id = session.peer_device_id.clone();
    let mut bundles_received = 0u32;
    loop {
        let msg = recv_encrypted(&mut session.recv, &session.cipher).await?;
        match msg.kind {
            MessageKind::SnapshotRequest => {
                let _ = app.emit(
                    "p2p:handoff-request",
                    serde_json::json!({ "peerDeviceId": peer_device_id }),
                );
            }
            MessageKind::SnapshotBundle => {
                bundles_received += 1;
                let body: SnapshotBundleBody = serde_json::from_value(msg.body)
                    .map_err(|e| e.to_string())?;
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
                let ack = WireMessage {
                    v: PROTOCOL_VERSION,
                    kind: MessageKind::DeltaAck,
                    body: serde_json::to_value(DeltaAckBody {
                        accepted: bundles_received,
                    })
                    .map_err(|e| e.to_string())?,
                };
                send_encrypted(&mut session.send, &session.cipher, &ack).await?;
                let _ = session.send.finish();
                p2p_log(&format!(
                    "iroh inbound handoff ack sent ({bundles_received} bundle(s))"
                ));
                break;
            }
            MessageKind::DeltaBatch => {
                let body: DeltaBatchBody = serde_json::from_value(msg.body)
                    .map_err(|e| e.to_string())?;
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
                        .map_err(|e| e.to_string())?,
                };
                send_encrypted(&mut session.send, &session.cipher, &ack).await?;
                let _ = session.send.finish();
                break;
            }
            _ => {}
        }
    }
    Ok(())
}

async fn write_frame(send: &mut SendStream, payload: &[u8]) -> Result<(), String> {
    send.write_all(&encode_frame(payload))
        .await
        .map_err(|e| e.to_string())
}

async fn read_payload(recv: &mut RecvStream) -> Result<Vec<u8>, String> {
    let mut len_buf = [0u8; 4];
    recv.read_exact(&mut len_buf)
        .await
        .map_err(|e| e.to_string())?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len > MAX_FRAME_BYTES {
        return Err(format!("LAN frame too large ({len} bytes)"));
    }
    let mut payload = vec![0u8; len];
    if len > 0 {
        recv.read_exact(&mut payload)
            .await
            .map_err(|e| e.to_string())?;
    }
    Ok(payload)
}

async fn write_message(send: &mut SendStream, msg: &WireMessage) -> Result<(), String> {
    let payload = serialize_message(msg).map_err(|e| e.to_string())?;
    write_frame(send, &payload).await
}

async fn read_message(recv: &mut RecvStream) -> Result<WireMessage, String> {
    let payload = read_payload(recv).await?;
    deserialize_message(&payload).map_err(|e| e.to_string())
}

async fn send_encrypted(
    send: &mut SendStream,
    cipher: &SessionCipher,
    msg: &WireMessage,
) -> Result<(), String> {
    let encrypted = encrypt_message(cipher, msg).map_err(|e: ProtocolError| e.to_string())?;
    write_frame(send, &encrypted).await
}

async fn recv_encrypted(recv: &mut RecvStream, cipher: &SessionCipher) -> Result<WireMessage, String> {
    let payload = read_payload(recv).await?;
    decrypt_message(cipher, &payload).map_err(|e: ProtocolError| e.to_string())
}

async fn send_handshake_reject(send: &mut SendStream, reason: &str) -> Result<(), String> {
    let msg = WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::HandshakeReject,
        body: serde_json::to_value(HandshakeRejectBody {
            reason: reason.to_string(),
        })
        .map_err(|e| e.to_string())?,
    };
    write_message(send, &msg).await
}

fn local_handshake_challenge(device_id: &str) -> Result<(Vec<u8>, String), String> {
    let bytes = handshake_message(device_id).map_err(|e| e.to_string())?;
    let msg = deserialize_message(&bytes).map_err(|e| e.to_string())?;
    let body: HandshakeChallengeBody = serde_json::from_value(msg.body).map_err(|e| e.to_string())?;
    Ok((bytes, body.nonce_b64))
}

fn is_trusted_peer(app: &AppHandle, device_id: &str) -> bool {
    PeerStore::list(app)
        .ok()
        .map(|peers| peers.iter().any(|p| p.device_id == device_id))
        .unwrap_or(false)
}

fn find_peer(app: &AppHandle, device_id: &str) -> Result<PairedPeer, String> {
    PeerStore::list(app)
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|p| p.device_id == device_id)
        .ok_or_else(|| "Peer not found.".into())
}

fn verify_peer_signature(
    public_key_b64: &str,
    remote_resp: &HandshakeResponseBody,
    nonce_b64: &str,
) -> Result<(), String> {
    let remote_sign_bytes = handshake_signing_bytes(&remote_resp.device_id, nonce_b64);
    if !verify_signature(public_key_b64, &remote_sign_bytes, &remote_resp.signature_b64) {
        return Err(format!(
            "Peer signature verification failed for {}. Re-pair both devices if this persists.",
            remote_resp.device_id
        ));
    }
    Ok(())
}

fn p2p_log(message: &str) {
    eprintln!("[suchconfig-p2p] {message}");
}

pub fn emit_sync_error(app: &AppHandle, message: &str) {
    p2p_log(&format!("sync error: {message}"));
    let _ = app.emit(
        "p2p:sync-error",
        serde_json::json!({ "message": message }),
    );
}
