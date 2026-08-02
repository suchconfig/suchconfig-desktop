use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};
use thiserror::Error;

use super::device::P2P_DIR;

pub const LAN_SYNC_FILENAME: &str = "lan_sync.json";

#[derive(Debug, Error)]
pub enum SettingsError {
    #[error("app data directory unavailable")]
    AppDataDir,
    #[error("io error: {0}")]
    Io(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LanSyncSettings {
    #[serde(default)]
    pub enabled: bool,
}

impl Default for LanSyncSettings {
    fn default() -> Self {
        Self { enabled: false }
    }
}

pub fn load(app: &AppHandle) -> Result<LanSyncSettings, SettingsError> {
    let path = settings_path(app)?;
    if !path.exists() {
        return Ok(LanSyncSettings::default());
    }
    let raw = fs::read_to_string(&path).map_err(|e| SettingsError::Io(e.to_string()))?;
    serde_json::from_str(&raw).map_err(|e| SettingsError::Io(e.to_string()))
}

pub fn save(app: &AppHandle, settings: &LanSyncSettings) -> Result<(), SettingsError> {
    let path = settings_path(app)?;
    let json =
        serde_json::to_string_pretty(settings).map_err(|e| SettingsError::Io(e.to_string()))?;
    fs::write(&path, json).map_err(|e| SettingsError::Io(e.to_string()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

pub fn set_enabled(app: &AppHandle, enabled: bool) -> Result<LanSyncSettings, SettingsError> {
    let mut settings = load(app)?;
    settings.enabled = enabled;
    save(app, &settings)?;
    Ok(settings)
}

fn settings_path(app: &AppHandle) -> Result<PathBuf, SettingsError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| SettingsError::AppDataDir)?;
    let p2p_dir = dir.join(P2P_DIR);
    fs::create_dir_all(&p2p_dir).map_err(|e| SettingsError::Io(e.to_string()))?;
    Ok(p2p_dir.join(LAN_SYNC_FILENAME))
}
