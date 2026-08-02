use base64::engine::general_purpose;
use base64::Engine as _;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tauri::AppHandle;
use thiserror::Error;

use super::device::{verify_signature, DeviceIdentity};
use super::qr;
use super::store::{PairedPeer, PeerStore};

pub const PAIRING_VERSION: u8 = 1;
pub const SESSION_TTL_SECS: u64 = 600;

#[derive(Debug, Error)]
pub enum PairingError {
    #[error("{0}")]
    Message(String),
}

impl PairingError {
    fn msg(text: impl Into<String>) -> Self {
        Self::Message(text.into())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct PairingOffer {
    pub v: u8,
    pub kind: String,
    pub session_id: String,
    pub device_id: String,
    pub device_name: String,
    pub public_key: String,
    pub short_code: String,
    pub expires_at: u64,
    pub signature: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct PairingResponse {
    pub v: u8,
    pub kind: String,
    pub session_id: String,
    pub initiator_device_id: String,
    pub device_id: String,
    pub device_name: String,
    pub public_key: String,
    pub signature: String,
}

#[derive(Debug, Clone)]
enum SessionRole {
    Initiator {
        offer: PairingOffer,
    },
    Responder {
        offer: PairingOffer,
        confirmed: bool,
    },
}

#[derive(Debug, Clone)]
struct PairingSession {
    role: SessionRole,
    expires_at: u64,
}

#[derive(Default)]
pub struct PairingState {
    sessions: Mutex<HashMap<String, PairingSession>>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalDeviceInfo {
    pub device_id: String,
    pub device_name: String,
    pub public_key: String,
    pub platform: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StartPairingResult {
    pub session_id: String,
    pub short_code: String,
    pub offer_json: String,
    pub qr_png_base64: String,
    pub expires_at: u64,
    pub device_name: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubmitOfferResult {
    pub session_id: String,
    pub remote_device_name: String,
    pub remote_device_id: String,
    pub short_code: String,
    pub expires_at: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfirmResponderResult {
    pub session_id: String,
    pub response_json: String,
    pub qr_png_base64: String,
    pub peer_device_name: String,
    pub peer_device_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CompleteInitiatorResult {
    pub peer_device_name: String,
    pub peer_device_id: String,
}

pub fn local_device_info(app: &AppHandle) -> Result<LocalDeviceInfo, PairingError> {
    let identity = DeviceIdentity::load_or_create(app).map_err(|e| PairingError::msg(e.to_string()))?;
    Ok(LocalDeviceInfo {
        device_id: identity.record.device_id.clone(),
        device_name: identity.record.device_name.clone(),
        public_key: identity.record.public_key_b64.clone(),
        platform: std::env::consts::OS.to_string(),
    })
}

pub fn list_peers(app: &AppHandle) -> Result<Vec<PairedPeer>, PairingError> {
    PeerStore::list(app).map_err(|e| PairingError::msg(e.to_string()))
}

pub fn remove_peer(app: &AppHandle, device_id: &str) -> Result<bool, PairingError> {
    PeerStore::remove(app, device_id).map_err(|e| PairingError::msg(e.to_string()))
}

pub fn start_pairing(
    app: &AppHandle,
    state: &PairingState,
) -> Result<StartPairingResult, PairingError> {
    purge_expired(state);
    let identity = DeviceIdentity::load_or_create(app).map_err(|e| PairingError::msg(e.to_string()))?;
    let session_id = uuid::Uuid::new_v4().to_string();
    let short_code = random_short_code();
    let expires_at = now_secs() + SESSION_TTL_SECS;
    let offer = build_offer(&identity, &session_id, &short_code, expires_at)?;
    let offer_json =
        serde_json::to_string(&offer).map_err(|e| PairingError::msg(e.to_string()))?;
    let qr_png_base64 = qr::png_base64(&offer_json).map_err(PairingError::msg)?;

    state.sessions.lock().unwrap().insert(
        session_id.clone(),
        PairingSession {
            role: SessionRole::Initiator { offer: offer.clone() },
            expires_at,
        },
    );

    Ok(StartPairingResult {
        session_id,
        short_code,
        offer_json,
        qr_png_base64,
        expires_at,
        device_name: identity.record.device_name,
    })
}

pub fn cancel_pairing(state: &PairingState, session_id: &str) -> Result<(), PairingError> {
    purge_expired(state);
    state
        .sessions
        .lock()
        .unwrap()
        .remove(session_id)
        .ok_or_else(|| PairingError::msg("Pairing session not found or expired."))?;
    Ok(())
}

pub fn submit_pairing_offer(
    app: &AppHandle,
    state: &PairingState,
    offer_json: &str,
) -> Result<SubmitOfferResult, PairingError> {
    purge_expired(state);
    let offer: PairingOffer = parse_pairing_offer_json(offer_json)?;
    validate_offer(&offer)?;

    if offer.device_id == DeviceIdentity::load_or_create(app).map_err(|e| PairingError::msg(e.to_string()))?.record.device_id {
        return Err(PairingError::msg("You cannot pair this device with itself."));
    }

    if PeerStore::list(app)
        .map_err(|e| PairingError::msg(e.to_string()))?
        .iter()
        .any(|p| p.device_id == offer.device_id)
    {
        return Err(PairingError::msg("This device is already paired."));
    }

    let session_id = offer.session_id.clone();
    state.sessions.lock().unwrap().insert(
        session_id.clone(),
        PairingSession {
            role: SessionRole::Responder {
                offer: offer.clone(),
                confirmed: false,
            },
            expires_at: offer.expires_at,
        },
    );

    Ok(SubmitOfferResult {
        session_id,
        remote_device_name: offer.device_name,
        remote_device_id: offer.device_id,
        short_code: offer.short_code,
        expires_at: offer.expires_at,
    })
}

pub fn confirm_pairing_responder(
    app: &AppHandle,
    state: &PairingState,
    session_id: &str,
) -> Result<ConfirmResponderResult, PairingError> {
    purge_expired(state);
    let identity = DeviceIdentity::load_or_create(app).map_err(|e| PairingError::msg(e.to_string()))?;
    let mut sessions = state.sessions.lock().unwrap();
    let session = sessions
        .get_mut(session_id)
        .ok_or_else(|| PairingError::msg("Pairing session not found or expired."))?;
    ensure_not_expired(session.expires_at)?;

    let SessionRole::Responder { offer, confirmed } = &mut session.role else {
        return Err(PairingError::msg("This session is not waiting for responder confirmation."));
    };
    if *confirmed {
        return Err(PairingError::msg("This device already confirmed pairing."));
    }

    validate_offer(offer)?;
    let response = build_response(&identity, offer)?;
    let response_json =
        serde_json::to_string(&response).map_err(|e| PairingError::msg(e.to_string()))?;
    let qr_png_base64 = qr::png_base64(&response_json).map_err(PairingError::msg)?;

    let peer = PairedPeer {
        device_id: offer.device_id.clone(),
        device_name: offer.device_name.clone(),
        public_key_b64: offer.public_key.clone(),
        paired_at: chrono::Utc::now().to_rfc3339(),
        pinned: true,
    };
    PeerStore::upsert(app, peer).map_err(|e| PairingError::msg(e.to_string()))?;
    *confirmed = true;

    Ok(ConfirmResponderResult {
        session_id: session_id.to_string(),
        response_json,
        qr_png_base64,
        peer_device_name: offer.device_name.clone(),
        peer_device_id: offer.device_id.clone(),
    })
}

pub fn complete_pairing_initiator(
    app: &AppHandle,
    state: &PairingState,
    response_json: &str,
) -> Result<CompleteInitiatorResult, PairingError> {
    purge_expired(state);
    let response: PairingResponse = parse_pairing_response_json(response_json)?;
    validate_response(&response)?;

    let identity = DeviceIdentity::load_or_create(app).map_err(|e| PairingError::msg(e.to_string()))?;
    if response.initiator_device_id != identity.record.device_id {
        return Err(PairingError::msg("This pairing response is for a different device."));
    }

    let mut sessions = state.sessions.lock().unwrap();
    let session = sessions
        .get(&response.session_id)
        .ok_or_else(|| PairingError::msg("Pairing session not found or expired."))?;
    ensure_not_expired(session.expires_at)?;

    let SessionRole::Initiator { offer } = &session.role else {
        return Err(PairingError::msg("This session is not an initiator pairing."));
    };

    if offer.session_id != response.session_id || offer.device_id != response.initiator_device_id {
        return Err(PairingError::msg("Pairing response does not match the active session."));
    }

    if response.device_id == identity.record.device_id {
        return Err(PairingError::msg("You cannot pair this device with itself."));
    }

    let peer = PairedPeer {
        device_id: response.device_id.clone(),
        device_name: response.device_name.clone(),
        public_key_b64: response.public_key.clone(),
        paired_at: chrono::Utc::now().to_rfc3339(),
        pinned: true,
    };
    PeerStore::upsert(app, peer).map_err(|e| PairingError::msg(e.to_string()))?;
    sessions.remove(&response.session_id);

    Ok(CompleteInitiatorResult {
        peer_device_name: response.device_name,
        peer_device_id: response.device_id,
    })
}

fn build_offer(
    identity: &DeviceIdentity,
    session_id: &str,
    short_code: &str,
    expires_at: u64,
) -> Result<PairingOffer, PairingError> {
    let payload = offer_signing_payload(session_id, &identity.record.device_id, &identity.record.public_key_b64, expires_at);
    let signature = general_purpose::STANDARD.encode(identity.sign(payload.as_bytes()));
    Ok(PairingOffer {
        v: PAIRING_VERSION,
        kind: "pairing_offer".to_string(),
        session_id: session_id.to_string(),
        device_id: identity.record.device_id.clone(),
        device_name: identity.record.device_name.clone(),
        public_key: identity.record.public_key_b64.clone(),
        short_code: short_code.to_string(),
        expires_at,
        signature,
    })
}

fn build_response(identity: &DeviceIdentity, offer: &PairingOffer) -> Result<PairingResponse, PairingError> {
    let payload = response_signing_payload(
        &offer.session_id,
        &offer.device_id,
        &identity.record.device_id,
        &identity.record.public_key_b64,
    );
    let signature = general_purpose::STANDARD.encode(identity.sign(payload.as_bytes()));
    Ok(PairingResponse {
        v: PAIRING_VERSION,
        kind: "pairing_response".to_string(),
        session_id: offer.session_id.clone(),
        initiator_device_id: offer.device_id.clone(),
        device_id: identity.record.device_id.clone(),
        device_name: identity.record.device_name.clone(),
        public_key: identity.record.public_key_b64.clone(),
        signature,
    })
}

fn validate_offer(offer: &PairingOffer) -> Result<(), PairingError> {
    if offer.v != PAIRING_VERSION || offer.kind != "pairing_offer" {
        return Err(PairingError::msg("Unsupported pairing offer version."));
    }
    ensure_not_expired(offer.expires_at)?;
    if offer.short_code.len() != 6 {
        return Err(PairingError::msg("Invalid pairing short code."));
    }
    let payload = offer_signing_payload(&offer.session_id, &offer.device_id, &offer.public_key, offer.expires_at);
    if !verify_signature(&offer.public_key, payload.as_bytes(), &offer.signature) {
        return Err(PairingError::msg("Pairing offer signature is invalid."));
    }
    Ok(())
}

fn validate_response(response: &PairingResponse) -> Result<(), PairingError> {
    if response.v != PAIRING_VERSION || response.kind != "pairing_response" {
        return Err(PairingError::msg("Unsupported pairing response version."));
    }
    let payload = response_signing_payload(
        &response.session_id,
        &response.initiator_device_id,
        &response.device_id,
        &response.public_key,
    );
    if !verify_signature(&response.public_key, payload.as_bytes(), &response.signature) {
        return Err(PairingError::msg("Pairing response signature is invalid."));
    }
    Ok(())
}

fn offer_signing_payload(session_id: &str, device_id: &str, public_key: &str, expires_at: u64) -> String {
    format!(
        "suchconfig-pair-offer-v1|{session_id}|{device_id}|{public_key}|{expires_at}"
    )
}

fn response_signing_payload(
    session_id: &str,
    initiator_device_id: &str,
    responder_device_id: &str,
    public_key: &str,
) -> String {
    format!(
        "suchconfig-pair-response-v1|{session_id}|{initiator_device_id}|{responder_device_id}|{public_key}"
    )
}

fn random_short_code() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let mut bytes = [0u8; 6];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes
        .iter()
        .map(|b| ALPHABET[(*b as usize) % ALPHABET.len()] as char)
        .collect()
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_secs()
}

fn ensure_not_expired(expires_at: u64) -> Result<(), PairingError> {
    if now_secs() > expires_at {
        return Err(PairingError::msg("Pairing session expired. Start again."));
    }
    Ok(())
}

fn parse_pairing_offer_json(raw: &str) -> Result<PairingOffer, PairingError> {
    parse_pairing_json(raw, "Invalid pairing code. Use Copy pairing code on the other computer and paste the full JSON block here.")
}

fn parse_pairing_response_json(raw: &str) -> Result<PairingResponse, PairingError> {
    parse_pairing_json(raw, "Invalid pairing response. Use Copy response for other device and paste the full JSON block here.")
}

fn parse_pairing_json<T: for<'de> Deserialize<'de>>(raw: &str, error: &str) -> Result<T, PairingError> {
    let candidates = normalized_json_candidates(raw);

    for candidate in candidates {
        if let Ok(value) = serde_json::from_str::<T>(&candidate) {
            return Ok(value);
        }
    }

    Err(PairingError::msg(error))
}

fn normalized_json_candidates(raw: &str) -> Vec<String> {
    let trimmed = raw.trim().trim_start_matches('\u{feff}');
    let mut candidates = Vec::new();

    if !trimmed.is_empty() {
        candidates.push(trimmed.to_string());
        candidates.push(normalize_smart_quotes(trimmed));
    }

    if let Some(slice) = extract_json_object(trimmed) {
        candidates.push(slice.to_string());
        candidates.push(normalize_smart_quotes(slice));
    }

    candidates.sort_by_key(|s| s.len());
    candidates.reverse();
    candidates.dedup();
    candidates
}

fn extract_json_object(raw: &str) -> Option<&str> {
    let start = raw.find('{')?;
    let end = raw.rfind('}')?;
    if end >= start {
        Some(&raw[start..=end])
    } else {
        None
    }
}

fn normalize_smart_quotes(raw: &str) -> String {
    raw.replace('\u{201c}', "\"")
        .replace('\u{201d}', "\"")
        .replace('\u{2018}', "'")
        .replace('\u{2019}', "'")
}

fn purge_expired(state: &PairingState) {
    let now = now_secs();
    state
        .sessions
        .lock()
        .unwrap()
        .retain(|_, session| session.expires_at >= now);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::p2p::device::DeviceRecord;
    use ed25519_dalek::SigningKey;
    use rand::rngs::OsRng;

    fn mock_identity(name: &str) -> DeviceIdentity {
        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key = signing_key.verifying_key();
        DeviceIdentity::from_record(DeviceRecord {
            device_id: uuid::Uuid::new_v4().to_string(),
            device_name: name.to_string(),
            public_key_b64: general_purpose::STANDARD.encode(verifying_key.as_bytes()),
            secret_key_b64: general_purpose::STANDARD.encode(signing_key.to_bytes()),
            created_at: chrono::Utc::now().to_rfc3339(),
        })
        .expect("identity")
    }

    #[test]
    fn offer_and_response_validate() {
        let initiator = mock_identity("initiator");
        let responder = mock_identity("responder");
        let session_id = uuid::Uuid::new_v4().to_string();
        let short_code = "ABC234".to_string();
        let expires_at = now_secs() + 300;
        let offer = build_offer(&initiator, &session_id, &short_code, expires_at).expect("offer");
        validate_offer(&offer).expect("valid offer");
        let response = build_response(&responder, &offer).expect("response");
        validate_response(&response).expect("valid response");
    }

    #[test]
    fn parse_offer_json_accepts_wrapped_paste() {
        let initiator = mock_identity("initiator");
        let session_id = uuid::Uuid::new_v4().to_string();
        let short_code = "ABC234".to_string();
        let expires_at = now_secs() + 300;
        let offer = build_offer(&initiator, &session_id, &short_code, expires_at).expect("offer");
        let offer_json =
            serde_json::to_string(&offer).expect("offer json");
        let wrapped = format!("Pairing code:\n{offer_json}\n");
        let parsed: PairingOffer = parse_pairing_offer_json(&wrapped).expect("parsed");
        assert_eq!(parsed.session_id, offer.session_id);
    }
}
