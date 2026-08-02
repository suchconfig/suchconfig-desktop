// Trusted Folder Sync — expand with notify watcher, scheduled export, and SHA-256 manifests.

use base64::engine::general_purpose;
use base64::Engine as _;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Component, Path, PathBuf};
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_dialog::DialogExt;
use thiserror::Error;
use tracing::{info, warn};

pub const SYNC_SUBDIR: &str = ".suchconfig";
pub const PROJECTS_ARCHIVE_NAME: &str = "projects.suchvault";
pub const SECRETS_ARCHIVE_NAME: &str = "secrets.suchvault";
pub const PROJECTS_ENC_NAME: &str = "projects.loro.enc";
pub const SECRETS_ENC_NAME: &str = "secrets.loro.enc";
pub const ENC_FILE_SUFFIX: &str = ".enc";
pub const CONFIG_FILENAME: &str = "trusted_folder.json";
pub const SETUP_COMPLETE_EVENT: &str = "trusted-folder:setup-complete";
pub const REQUEST_INITIAL_EXPORT_EVENT: &str = "trusted-folder:request-initial-export";

#[derive(Debug, Error)]
pub enum TrustedFolderError {
    #[error("app data directory unavailable")]
    AppDataDir,
    #[error("failed to read config: {0}")]
    ConfigRead(String),
    #[error("failed to write config: {0}")]
    ConfigWrite(String),
    #[error("invalid trusted folder path: {0}")]
    InvalidPath(String),
    #[error("trusted folder is not a directory: {0}")]
    NotADirectory(String),
    #[error("trusted folder is not writable: {0}")]
    NotWritable(String),
    #[error("folder selection cancelled")]
    SelectionCancelled,
    #[error("failed to create sync directory: {0}")]
    SyncDirCreate(String),
    #[error("failed to write archive: {0}")]
    ArchiveWrite(String),
    #[error("invalid base64 archive payload: {0}")]
    InvalidBase64(String),
    #[error("archive path escapes trusted sync directory")]
    PathEscape,
    #[error("no trusted folder configured")]
    NotConfigured,
    #[error("event emit failed: {0}")]
    EventEmit(String),
}

impl TrustedFolderError {
    fn into_command_string(self) -> String {
        self.to_string()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TrustedFolderConfig {
    pub trusted_folder_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub setup_completed_at: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct TrustedFolderSetupPayload {
    pub trusted_folder_path: String,
    pub sync_dir: String,
    pub projects_archive_path: String,
    pub secrets_archive_path: String,
    pub reused_existing: bool,
}

fn config_path(app: &AppHandle) -> Result<PathBuf, TrustedFolderError> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| TrustedFolderError::AppDataDir)?;
    fs::create_dir_all(&dir).map_err(|e| TrustedFolderError::ConfigWrite(e.to_string()))?;
    Ok(dir.join(CONFIG_FILENAME))
}

pub fn load_config(app: &AppHandle) -> Result<TrustedFolderConfig, TrustedFolderError> {
    let path = config_path(app)?;
    if !path.exists() {
        return Ok(TrustedFolderConfig::default());
    }
    let raw =
        fs::read_to_string(&path).map_err(|e| TrustedFolderError::ConfigRead(e.to_string()))?;
    serde_json::from_str(&raw).map_err(|e| TrustedFolderError::ConfigRead(e.to_string()))
}

pub fn save_config(
    app: &AppHandle,
    config: &TrustedFolderConfig,
) -> Result<(), TrustedFolderError> {
    let path = config_path(app)?;
    let json = serde_json::to_string_pretty(config)
        .map_err(|e| TrustedFolderError::ConfigWrite(e.to_string()))?;
    fs::write(&path, json).map_err(|e| TrustedFolderError::ConfigWrite(e.to_string()))
}

pub fn validate_trusted_folder(path: &str) -> Result<PathBuf, TrustedFolderError> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err(TrustedFolderError::InvalidPath("path is empty".to_string()));
    }
    let candidate = PathBuf::from(trimmed);
    if candidate
        .components()
        .any(|c| matches!(c, Component::ParentDir))
    {
        return Err(TrustedFolderError::InvalidPath(
            "path must not contain parent references".to_string(),
        ));
    }
    let canonical = candidate
        .canonicalize()
        .map_err(|e| TrustedFolderError::InvalidPath(e.to_string()))?;
    if !canonical.is_dir() {
        return Err(TrustedFolderError::NotADirectory(
            canonical.display().to_string(),
        ));
    }
    let probe = canonical.join(format!("{SYNC_SUBDIR}.write_probe"));
    if let Some(parent) = probe.parent() {
        fs::create_dir_all(parent).map_err(|e| TrustedFolderError::NotWritable(e.to_string()))?;
    }
    fs::write(&probe, b"ok").map_err(|e| TrustedFolderError::NotWritable(e.to_string()))?;
    let _ = fs::remove_file(&probe);
    Ok(canonical)
}

pub fn sync_dir_for(trusted_root: &Path) -> PathBuf {
    trusted_root.join(SYNC_SUBDIR)
}

pub fn archive_paths(sync_dir: &Path) -> (PathBuf, PathBuf) {
    (
        sync_dir.join(PROJECTS_ARCHIVE_NAME),
        sync_dir.join(SECRETS_ARCHIVE_NAME),
    )
}

pub fn sync_enc_paths(sync_dir: &Path) -> (PathBuf, PathBuf) {
    (
        sync_dir.join(PROJECTS_ENC_NAME),
        sync_dir.join(SECRETS_ENC_NAME),
    )
}

pub fn ensure_sync_dir(trusted_root: &Path) -> Result<PathBuf, TrustedFolderError> {
    let sync_dir = sync_dir_for(trusted_root);
    fs::create_dir_all(&sync_dir).map_err(|e| TrustedFolderError::SyncDirCreate(e.to_string()))?;
    Ok(sync_dir)
}

pub fn write_bytes_atomic(path: &Path, bytes: &[u8]) -> Result<(), TrustedFolderError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| TrustedFolderError::ArchiveWrite(e.to_string()))?;
    }
    let tmp = path.with_extension("suchconfig.tmp");
    fs::write(&tmp, bytes).map_err(|e| TrustedFolderError::ArchiveWrite(e.to_string()))?;
    fs::rename(&tmp, path).map_err(|e| TrustedFolderError::ArchiveWrite(e.to_string()))?;
    Ok(())
}

fn path_within_sync_dir(sync_dir: &Path, target: &Path) -> Result<(), TrustedFolderError> {
    let sync_canon = sync_dir
        .canonicalize()
        .map_err(|e| TrustedFolderError::InvalidPath(e.to_string()))?;
    let target_canon = if target.exists() {
        target
            .canonicalize()
            .map_err(|e| TrustedFolderError::InvalidPath(e.to_string()))?
    } else {
        let parent = target
            .parent()
            .ok_or_else(|| TrustedFolderError::InvalidPath("missing parent".to_string()))?;
        let parent_canon = parent
            .canonicalize()
            .map_err(|e| TrustedFolderError::InvalidPath(e.to_string()))?;
        let name = target
            .file_name()
            .ok_or_else(|| TrustedFolderError::InvalidPath("missing file name".to_string()))?;
        parent_canon.join(name)
    };
    if !target_canon.starts_with(&sync_canon) {
        return Err(TrustedFolderError::PathEscape);
    }
    Ok(())
}

pub fn write_sync_archive(
    app: &AppHandle,
    relative_name: &str,
    content_base64: &str,
) -> Result<String, TrustedFolderError> {
    let config = load_config(app)?;
    let trusted_path = config
        .trusted_folder_path
        .ok_or(TrustedFolderError::NotConfigured)?;
    let trusted_root = validate_trusted_folder(&trusted_path)?;
    let sync_dir = ensure_sync_dir(&trusted_root)?;
    let rel = Path::new(relative_name);
    if rel.is_absolute() || rel.components().any(|c| matches!(c, Component::ParentDir)) {
        return Err(TrustedFolderError::InvalidPath(
            "relative_name must be a simple file name under the sync directory".to_string(),
        ));
    }
    let target = sync_dir.join(rel);
    path_within_sync_dir(&sync_dir, &target)?;
    let bytes = general_purpose::STANDARD
        .decode(content_base64.trim())
        .map_err(|e| TrustedFolderError::InvalidBase64(e.to_string()))?;
    write_bytes_atomic(&target, &bytes)?;
    Ok(target.display().to_string())
}

fn seed_initial_archives(
    sync_dir: &Path,
    projects_b64: Option<&str>,
    secrets_b64: Option<&str>,
) -> Result<bool, TrustedFolderError> {
    let (projects_path, secrets_path) = archive_paths(sync_dir);
    let mut wrote_any = false;

    if let Some(b64) = projects_b64 {
        let bytes = general_purpose::STANDARD
            .decode(b64.trim())
            .map_err(|e| TrustedFolderError::InvalidBase64(e.to_string()))?;
        write_bytes_atomic(&projects_path, &bytes)?;
        wrote_any = true;
        info!(path = %projects_path.display(), "seeded projects trusted-folder archive");
    }

    if let Some(b64) = secrets_b64 {
        let bytes = general_purpose::STANDARD
            .decode(b64.trim())
            .map_err(|e| TrustedFolderError::InvalidBase64(e.to_string()))?;
        write_bytes_atomic(&secrets_path, &bytes)?;
        wrote_any = true;
        info!(path = %secrets_path.display(), "seeded secrets trusted-folder archive");
    }

    Ok(wrote_any)
}

fn emit_setup_events(
    app: &AppHandle,
    payload: &TrustedFolderSetupPayload,
    needs_initial_export: bool,
) -> Result<(), TrustedFolderError> {
    app.emit(SETUP_COMPLETE_EVENT, payload)
        .map_err(|e| TrustedFolderError::EventEmit(e.to_string()))?;
    if needs_initial_export {
        app.emit(
            REQUEST_INITIAL_EXPORT_EVENT,
            serde_json::json!({
                "trusted_folder_path": payload.trusted_folder_path,
                "sync_dir": payload.sync_dir,
                "projects_archive_path": payload.projects_archive_path,
                "secrets_archive_path": payload.secrets_archive_path,
            }),
        )
        .map_err(|e| TrustedFolderError::EventEmit(e.to_string()))?;
    }
    Ok(())
}

fn pick_trusted_folder(app: &AppHandle) -> Result<PathBuf, TrustedFolderError> {
    info!("opening native folder picker for trusted folder");
    let dialog = app.dialog();
    let picked = dialog
        .file()
        .set_title("SuchConfig — select Trusted Folder")
        .blocking_pick_folder();
    match picked {
        Some(path) => validate_trusted_folder(&path.to_string()),
        None => Err(TrustedFolderError::SelectionCancelled),
    }
}

pub async fn run_setup_trusted_folder(
    app: AppHandle,
    force_picker: bool,
    projects_archive_base64: Option<String>,
    secrets_archive_base64: Option<String>,
) -> Result<String, TrustedFolderError> {
    let existing = load_config(&app)?;
    let reused_existing = !force_picker
        && existing
            .trusted_folder_path
            .as_deref()
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .is_some();

    let trusted_root = if force_picker {
        pick_trusted_folder(&app)?
    } else if let Some(path) = existing
        .trusted_folder_path
        .filter(|p| !p.trim().is_empty())
    {
        info!("trusted folder already configured; reusing stored path");
        validate_trusted_folder(&path)?
    } else {
        pick_trusted_folder(&app)?
    };

    let trusted_folder_path = trusted_root.display().to_string();
    let sync_dir = ensure_sync_dir(&trusted_root)?;
    let (projects_archive_path, secrets_archive_path) = archive_paths(&sync_dir);

    let wrote_archives = seed_initial_archives(
        &sync_dir,
        projects_archive_base64.as_deref(),
        secrets_archive_base64.as_deref(),
    )?;

    let needs_initial_export =
        !wrote_archives && (!projects_archive_path.exists() || !secrets_archive_path.exists());

    let setup_completed_at = chrono::Utc::now().to_rfc3339();
    save_config(
        &app,
        &TrustedFolderConfig {
            trusted_folder_path: Some(trusted_folder_path.clone()),
            setup_completed_at: Some(setup_completed_at),
        },
    )?;

    let payload = TrustedFolderSetupPayload {
        trusted_folder_path: trusted_folder_path.clone(),
        sync_dir: sync_dir.display().to_string(),
        projects_archive_path: projects_archive_path.display().to_string(),
        secrets_archive_path: secrets_archive_path.display().to_string(),
        reused_existing,
    };

    emit_setup_events(&app, &payload, needs_initial_export)?;

    if needs_initial_export {
        warn!(
            "trusted folder sync dir ready; Phoenix should export encrypted archives via {}",
            REQUEST_INITIAL_EXPORT_EVENT
        );
    }

    Ok(trusted_folder_path)
}

#[tauri::command]
pub async fn get_trusted_folder_path(app: tauri::AppHandle) -> Result<Option<String>, String> {
    load_config(&app)
        .map(|c| c.trusted_folder_path)
        .map_err(TrustedFolderError::into_command_string)
}

#[tauri::command]
pub async fn write_trusted_sync_archive(
    app: tauri::AppHandle,
    relative_name: String,
    content_base64: String,
) -> Result<String, String> {
    write_sync_archive(&app, &relative_name, &content_base64)
        .map_err(TrustedFolderError::into_command_string)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn validate_rejects_parent_dir_segments() {
        let err = validate_trusted_folder("../etc").unwrap_err();
        assert!(matches!(err, TrustedFolderError::InvalidPath(_)));
    }

    #[test]
    fn write_bytes_atomic_roundtrip() {
        let dir = TempDir::new().expect("tempdir");
        let path = dir.path().join("nested").join("archive.suchvault");
        write_bytes_atomic(&path, b"encrypted-payload").expect("write");
        let read = fs::read(&path).expect("read");
        assert_eq!(read, b"encrypted-payload");
    }

    #[test]
    fn config_roundtrip_json() {
        let cfg = TrustedFolderConfig {
            trusted_folder_path: Some("/tmp/trusted".to_string()),
            setup_completed_at: Some("2026-05-31T00:00:00Z".to_string()),
        };
        let json = serde_json::to_string(&cfg).expect("serialize");
        let back: TrustedFolderConfig = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(back.trusted_folder_path, cfg.trusted_folder_path);
    }

    #[test]
    fn validate_accepts_writable_directory() {
        let dir = TempDir::new().expect("tempdir");
        let root = validate_trusted_folder(dir.path().to_str().expect("utf8")).expect("valid");
        assert!(root.is_dir());
    }
}
