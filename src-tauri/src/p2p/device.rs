use base64::engine::general_purpose;
use base64::Engine as _;
use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};
use thiserror::Error;

pub const P2P_DIR: &str = "p2p";
pub const DEVICE_FILENAME: &str = "device.json";

#[derive(Debug, Error)]
pub enum DeviceError {
    #[error("app data directory unavailable")]
    AppDataDir,
    #[error("io error: {0}")]
    Io(String),
    #[error("invalid device record")]
    InvalidRecord,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceRecord {
    pub device_id: String,
    pub device_name: String,
    pub public_key_b64: String,
    pub secret_key_b64: String,
    pub created_at: String,
}

#[derive(Debug, Clone)]
pub struct DeviceIdentity {
    pub record: DeviceRecord,
    signing_key: SigningKey,
}

impl DeviceIdentity {
    pub fn load_or_create(app: &AppHandle) -> Result<Self, DeviceError> {
        let path = device_path(app)?;
        if path.exists() {
            let raw = fs::read_to_string(&path).map_err(|e| DeviceError::Io(e.to_string()))?;
            let record: DeviceRecord =
                serde_json::from_str(&raw).map_err(|_| DeviceError::InvalidRecord)?;
            return Self::from_record(record);
        }

        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key = signing_key.verifying_key();
        let record = DeviceRecord {
            device_id: uuid::Uuid::new_v4().to_string(),
            device_name: default_device_name(),
            public_key_b64: general_purpose::STANDARD.encode(verifying_key.as_bytes()),
            secret_key_b64: general_purpose::STANDARD.encode(signing_key.to_bytes()),
            created_at: chrono::Utc::now().to_rfc3339(),
        };
        let identity = Self::from_record(record.clone())?;
        save_record(app, &record)?;
        Ok(identity)
    }

    pub fn from_record(record: DeviceRecord) -> Result<Self, DeviceError> {
        let secret_bytes = general_purpose::STANDARD
            .decode(record.secret_key_b64.trim())
            .map_err(|_| DeviceError::InvalidRecord)?;
        let key_array: [u8; 32] = secret_bytes
            .try_into()
            .map_err(|_| DeviceError::InvalidRecord)?;
        let signing_key = SigningKey::from_bytes(&key_array);
        let verifying_key = signing_key.verifying_key();
        let expected_pk = general_purpose::STANDARD.encode(verifying_key.as_bytes());
        if expected_pk != record.public_key_b64 {
            return Err(DeviceError::InvalidRecord);
        }
        Ok(Self { record, signing_key })
    }

    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        use ed25519_dalek::Signer;
        self.signing_key.sign(message).to_bytes().to_vec()
    }
}

pub fn device_path(app: &AppHandle) -> Result<PathBuf, DeviceError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| DeviceError::AppDataDir)?;
    let p2p_dir = dir.join(P2P_DIR);
    fs::create_dir_all(&p2p_dir).map_err(|e| DeviceError::Io(e.to_string()))?;
    Ok(p2p_dir.join(DEVICE_FILENAME))
}

fn save_record(app: &AppHandle, record: &DeviceRecord) -> Result<(), DeviceError> {
    let path = device_path(app)?;
    let json = serde_json::to_string_pretty(record).map_err(|e| DeviceError::Io(e.to_string()))?;
    fs::write(&path, json).map_err(|e| DeviceError::Io(e.to_string()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

fn default_device_name() -> String {
    hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .map(|s| sanitize_device_name(&s))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "SuchConfig".to_string())
}

fn sanitize_device_name(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        "SuchConfig".to_string()
    } else {
        trimmed.chars().take(64).collect()
    }
}

pub fn verify_signature(public_key_b64: &str, message: &[u8], signature_b64: &str) -> bool {
    let Ok(pk_bytes) = general_purpose::STANDARD.decode(public_key_b64.trim()) else {
        return false;
    };
    let Ok(pk_array): Result<[u8; 32], _> = pk_bytes.try_into() else {
        return false;
    };
    let Ok(verifying_key) = VerifyingKey::from_bytes(&pk_array) else {
        return false;
    };
    let Ok(sig_bytes) = general_purpose::STANDARD.decode(signature_b64.trim()) else {
        return false;
    };
    let Ok(sig_array): Result<[u8; 64], _> = sig_bytes.try_into() else {
        return false;
    };
    use ed25519_dalek::Signature;
    let signature = Signature::from_bytes(&sig_array);
    verifying_key.verify_strict(message, &signature).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_record_and_sign() {
        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key = signing_key.verifying_key();
        let record = DeviceRecord {
            device_id: uuid::Uuid::new_v4().to_string(),
            device_name: "test-host".to_string(),
            public_key_b64: general_purpose::STANDARD.encode(verifying_key.as_bytes()),
            secret_key_b64: general_purpose::STANDARD.encode(signing_key.to_bytes()),
            created_at: chrono::Utc::now().to_rfc3339(),
        };
        let identity = DeviceIdentity::from_record(record).expect("record");
        let msg = b"suchconfig-test";
        let sig = general_purpose::STANDARD.encode(identity.sign(msg));
        assert!(verify_signature(
            &identity.record.public_key_b64,
            msg,
            &sig
        ));
    }
}
