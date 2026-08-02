use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose;
use base64::Engine as _;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

pub const PROTOCOL_VERSION: u8 = 1;
pub const SYNC_ALPN: &[u8] = b"suchconfig/sync/1";
pub const SERVICE_TYPE: &str = "_suchconfig._tcp.local.";
pub const HANDSHAKE_DOMAIN: &[u8] = b"suchconfig-p2p-challenge-v1";
pub const SESSION_KEY_DOMAIN: &[u8] = b"suchconfig-p2p-session-v1";

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("decryption failed")]
    DecryptFailed,
    #[error("serialization error: {0}")]
    Serde(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MessageKind {
    HandshakeChallenge,
    HandshakeResponse,
    HandshakeReject,
    SnapshotRequest,
    SnapshotBundle,
    SnapshotComplete,
    DeltaBatch,
    DeltaAck,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WireMessage {
    pub v: u8,
    pub kind: MessageKind,
    #[serde(flatten)]
    pub body: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HandshakeChallengeBody {
    pub device_id: String,
    pub nonce_b64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HandshakeResponseBody {
    pub device_id: String,
    pub signature_b64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HandshakeRejectBody {
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotRequestBody {
    pub vaults: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotBundleBody {
    pub vault: String,
    pub snapshot_base64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeltaUpdate {
    pub item_key: String,
    pub vault: String,
    pub delta_base64: String,
    pub snapshot_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeltaBatchBody {
    pub updates: Vec<DeltaUpdate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeltaAckBody {
    pub accepted: u32,
}

pub fn encode_frame(payload: &[u8]) -> Vec<u8> {
    let len = payload.len() as u32;
    let mut out = Vec::with_capacity(4 + payload.len());
    out.extend_from_slice(&len.to_be_bytes());
    out.extend_from_slice(payload);
    out
}

pub fn serialize_message(msg: &WireMessage) -> Result<Vec<u8>, ProtocolError> {
    serde_json::to_vec(msg).map_err(|e| ProtocolError::Serde(e.to_string()))
}

pub fn deserialize_message(bytes: &[u8]) -> Result<WireMessage, ProtocolError> {
    serde_json::from_slice(bytes).map_err(|e| ProtocolError::Serde(e.to_string()))
}

pub fn handshake_message(device_id: &str) -> Result<Vec<u8>, ProtocolError> {
    let mut nonce = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut nonce);
    let msg = WireMessage {
        v: PROTOCOL_VERSION,
        kind: MessageKind::HandshakeChallenge,
        body: serde_json::to_value(HandshakeChallengeBody {
            device_id: device_id.to_string(),
            nonce_b64: general_purpose::STANDARD.encode(nonce),
        })
        .map_err(|e| ProtocolError::Serde(e.to_string()))?,
    };
    serialize_message(&msg)
}

pub fn handshake_signing_bytes(device_id: &str, nonce_b64: &str) -> Vec<u8> {
    let mut out = HANDSHAKE_DOMAIN.to_vec();
    out.push(b'|');
    out.extend_from_slice(device_id.as_bytes());
    out.push(b'|');
    out.extend_from_slice(nonce_b64.as_bytes());
    out
}

pub fn derive_session_key(local_sig: &[u8], remote_sig: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(SESSION_KEY_DOMAIN);
    hasher.update(b"|");
    if local_sig <= remote_sig {
        hasher.update(local_sig);
        hasher.update(remote_sig);
    } else {
        hasher.update(remote_sig);
        hasher.update(local_sig);
    }
    hasher.finalize().into()
}

pub struct SessionCipher {
    cipher: Aes256Gcm,
}

impl SessionCipher {
    pub fn new(key: &[u8; 32]) -> Self {
        Self {
            cipher: Aes256Gcm::new_from_slice(key).expect("aes key"),
        }
    }

    pub fn encrypt(&self, plaintext: &[u8]) -> Result<Vec<u8>, ProtocolError> {
        let mut nonce_bytes = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);
        let ciphertext = self
            .cipher
            .encrypt(nonce, plaintext)
            .map_err(|_| ProtocolError::DecryptFailed)?;
        let mut out = Vec::with_capacity(12 + ciphertext.len());
        out.extend_from_slice(&nonce_bytes);
        out.extend_from_slice(&ciphertext);
        Ok(out)
    }

    pub fn decrypt(&self, blob: &[u8]) -> Result<Vec<u8>, ProtocolError> {
        if blob.len() < 13 {
            return Err(ProtocolError::DecryptFailed);
        }
        let nonce = Nonce::from_slice(&blob[..12]);
        self.cipher
            .decrypt(nonce, &blob[12..])
            .map_err(|_| ProtocolError::DecryptFailed)
    }
}

pub fn encrypt_message(cipher: &SessionCipher, msg: &WireMessage) -> Result<Vec<u8>, ProtocolError> {
    let plain = serialize_message(msg)?;
    cipher.encrypt(&plain)
}

pub fn decrypt_message(cipher: &SessionCipher, blob: &[u8]) -> Result<WireMessage, ProtocolError> {
    let plain = cipher.decrypt(blob)?;
    deserialize_message(&plain)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_encoding() {
        let payload = b"hello-p2p";
        let frame = encode_frame(payload);
        let len = u32::from_be_bytes([frame[0], frame[1], frame[2], frame[3]]) as usize;
        assert_eq!(len, payload.len());
        assert_eq!(&frame[4..], payload);
    }

    #[test]
    fn session_key_is_symmetric_for_equal_length_signatures() {
        let sig_a = [1u8; 64];
        let sig_b = [2u8; 64];
        assert_eq!(
            derive_session_key(&sig_a, &sig_b),
            derive_session_key(&sig_b, &sig_a)
        );
    }

    #[test]
    fn session_cipher_round_trip() {
        let key = derive_session_key(b"sig-a", b"sig-b");
        let cipher = SessionCipher::new(&key);
        let msg = WireMessage {
            v: 1,
            kind: MessageKind::DeltaAck,
            body: serde_json::json!({ "accepted": 3 }),
        };
        let encrypted = encrypt_message(&cipher, &msg).expect("encrypt");
        let decrypted = decrypt_message(&cipher, &encrypted).expect("decrypt");
        assert_eq!(decrypted.kind, MessageKind::DeltaAck);
    }
}
