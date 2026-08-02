use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};
use thiserror::Error;

use super::device::{DeviceError, P2P_DIR};

pub const PEERS_FILENAME: &str = "peers.json";

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("app data directory unavailable")]
    AppDataDir,
    #[error("io error: {0}")]
    Io(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairedPeer {
    pub device_id: String,
    pub device_name: String,
    pub public_key_b64: String,
    pub paired_at: String,
    pub pinned: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct PeerStoreFile {
    peers: HashMap<String, PairedPeer>,
}

pub struct PeerStore;

impl PeerStore {
    pub fn list_at_path(path: &PathBuf) -> Result<Vec<PairedPeer>, StoreError> {
        let file = Self::read_file_at_path(path)?;
        let mut peers: Vec<PairedPeer> = file.peers.into_values().collect();
        peers.sort_by(|a, b| a.device_name.cmp(&b.device_name));
        Ok(peers)
    }

    pub fn list(app: &AppHandle) -> Result<Vec<PairedPeer>, StoreError> {
        let file = Self::read_file(app)?;
        let mut peers: Vec<PairedPeer> = file.peers.into_values().collect();
        peers.sort_by(|a, b| a.device_name.cmp(&b.device_name));
        Ok(peers)
    }

    pub fn upsert(app: &AppHandle, peer: PairedPeer) -> Result<PairedPeer, StoreError> {
        let mut file = Self::read_file(app)?;
        let device_id = peer.device_id.clone();
        file.peers.insert(device_id, peer.clone());
        Self::write_file(app, &file)?;
        Ok(peer)
    }

    pub fn remove(app: &AppHandle, device_id: &str) -> Result<bool, StoreError> {
        let mut file = Self::read_file(app)?;
        let removed = file.peers.remove(device_id).is_some();
        if removed {
            Self::write_file(app, &file)?;
        }
        Ok(removed)
    }

    fn read_file(app: &AppHandle) -> Result<PeerStoreFile, StoreError> {
        Self::read_file_at_path(&peers_path(app)?)
    }

    fn read_file_at_path(path: &PathBuf) -> Result<PeerStoreFile, StoreError> {
        if !path.exists() {
            return Ok(PeerStoreFile::default());
        }
        let raw = fs::read_to_string(path).map_err(|e| StoreError::Io(e.to_string()))?;
        serde_json::from_str(&raw).map_err(|e| StoreError::Io(e.to_string()))
    }

    fn write_file(app: &AppHandle, file: &PeerStoreFile) -> Result<(), StoreError> {
        let path = peers_path(app)?;
        let json =
            serde_json::to_string_pretty(file).map_err(|e| StoreError::Io(e.to_string()))?;
        fs::write(&path, json).map_err(|e| StoreError::Io(e.to_string()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}

fn peers_path(app: &AppHandle) -> Result<PathBuf, StoreError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| StoreError::AppDataDir)?;
    let p2p_dir = dir.join(P2P_DIR);
    fs::create_dir_all(&p2p_dir).map_err(|e| StoreError::Io(e.to_string()))?;
    Ok(p2p_dir.join(PEERS_FILENAME))
}

impl From<DeviceError> for StoreError {
    fn from(value: DeviceError) -> Self {
        StoreError::Io(value.to_string())
    }
}
