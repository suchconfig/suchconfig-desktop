use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};
use thiserror::Error;

use super::device::P2P_DIR;

pub const FRONTIERS_FILENAME: &str = "frontiers.json";

#[derive(Debug, Error)]
pub enum FrontierError {
    #[error("app data directory unavailable")]
    AppDataDir,
    #[error("io error: {0}")]
    Io(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct FrontierStoreFile {
    peers: HashMap<String, HashMap<String, FrontierEntry>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrontierEntry {
    pub snapshot_base64: String,
    pub snapshot_hash: String,
    pub updated_at: String,
}

pub struct FrontierStore;

impl FrontierStore {
    pub fn get(app: &AppHandle, peer_id: &str, item_key: &str) -> Result<Option<FrontierEntry>, FrontierError> {
        let file = Self::read_file(app)?;
        Ok(file
            .peers
            .get(peer_id)
            .and_then(|items| items.get(item_key))
            .cloned())
    }

    pub fn set(
        app: &AppHandle,
        peer_id: &str,
        item_key: &str,
        snapshot_base64: &str,
        snapshot_hash: &str,
    ) -> Result<(), FrontierError> {
        let mut file = Self::read_file(app)?;
        let entry = FrontierEntry {
            snapshot_base64: snapshot_base64.to_string(),
            snapshot_hash: snapshot_hash.to_string(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        };
        file.peers
            .entry(peer_id.to_string())
            .or_default()
            .insert(item_key.to_string(), entry);
        Self::write_file(app, &file)
    }

    fn read_file(app: &AppHandle) -> Result<FrontierStoreFile, FrontierError> {
        let path = frontiers_path(app)?;
        if !path.exists() {
            return Ok(FrontierStoreFile::default());
        }
        let raw = fs::read_to_string(&path).map_err(|e| FrontierError::Io(e.to_string()))?;
        serde_json::from_str(&raw).map_err(|e| FrontierError::Io(e.to_string()))
    }

    fn write_file(app: &AppHandle, file: &FrontierStoreFile) -> Result<(), FrontierError> {
        let path = frontiers_path(app)?;
        let json =
            serde_json::to_string_pretty(file).map_err(|e| FrontierError::Io(e.to_string()))?;
        fs::write(&path, json).map_err(|e| FrontierError::Io(e.to_string()))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}

fn frontiers_path(app: &AppHandle) -> Result<PathBuf, FrontierError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| FrontierError::AppDataDir)?;
    let p2p_dir = dir.join(P2P_DIR);
    fs::create_dir_all(&p2p_dir).map_err(|e| FrontierError::Io(e.to_string()))?;
    Ok(p2p_dir.join(FRONTIERS_FILENAME))
}
