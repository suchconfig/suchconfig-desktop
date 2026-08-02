use crate::app_identity::{VAULT_KEY_HOME_DIR, VAULT_KEYCHAIN_SERVICE};
use crate::trusted_folder::{
    self, ensure_sync_dir, load_config, sync_enc_paths, validate_trusted_folder, ENC_FILE_SUFFIX,
    PROJECTS_ENC_NAME, SECRETS_ENC_NAME,
};
use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use argon2::Argon2;
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use notify::{Config, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use parking_lot::Mutex;
use rand::RngCore;
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager, State};
use thiserror::Error;
use tokio::sync::{mpsc, watch};
use tracing::{error, info, warn};

pub const VAULT_UPDATED_EVENT: &str = "vault:updated";
pub const TRUSTED_FOLDER_SYNCED_EVENT: &str = "trusted-folder:synced";
pub const TRUSTED_FOLDER_IMPORT_EVENT: &str = "trusted-folder:import-snapshot";
pub const DEFAULT_VAULT_KEY_ID: &str = "suchconfig.project_manager.vault";
pub const DEBOUNCE_MS: u64 = 500;
const ENVELOPE_MAGIC: &[u8; 7] = b"SCENC01";
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 12;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum VaultRole {
    Secrets,
    Projects,
}

impl VaultRole {
    #[expect(dead_code)]
    pub fn enc_filename(self) -> &'static str {
        match self {
            VaultRole::Secrets => SECRETS_ENC_NAME,
            VaultRole::Projects => PROJECTS_ENC_NAME,
        }
    }

    pub fn from_filename(name: &str) -> Option<Self> {
        match name {
            SECRETS_ENC_NAME => Some(VaultRole::Secrets),
            PROJECTS_ENC_NAME => Some(VaultRole::Projects),
            _ => None,
        }
    }
}

#[derive(Debug, Error)]
pub enum WatcherError {
    #[error("trusted folder not configured")]
    NotConfigured,
    #[error("invalid trusted folder: {0}")]
    InvalidFolder(String),
    #[error("watcher already running")]
    AlreadyRunning,
    #[error("watcher is not running")]
    NotRunning,
    #[error("notify error: {0}")]
    Notify(String),
    #[error("io error: {0}")]
    Io(String),
    #[error("checksum mismatch for {0}")]
    ChecksumMismatch(String),
    #[error("master key unavailable: {0}")]
    MasterKey(String),
    #[error("crypto error: {0}")]
    Crypto(String),
    #[error("snapshot unavailable for {0:?}")]
    SnapshotUnavailable(VaultRole),
    #[error("unknown enc file: {0}")]
    UnknownEncFile(String),
    #[error("event emit failed: {0}")]
    EventEmit(String),
    #[error("trusted folder error: {0}")]
    TrustedFolder(#[from] trusted_folder::TrustedFolderError),
}

impl WatcherError {
    fn into_command_string(self) -> String {
        self.to_string()
    }
}

pub fn sha256_hex(data: &[u8]) -> String {
    let digest = Sha256::digest(data);
    hex::encode(digest)
}

pub fn checksum_sidecar_path(enc_path: &Path) -> PathBuf {
    enc_path.with_extension("sha256")
}

pub fn write_checksum_sidecar(enc_path: &Path, encrypted: &[u8]) -> Result<(), WatcherError> {
    let sidecar = checksum_sidecar_path(enc_path);
    let hash = sha256_hex(encrypted);
    if let Some(parent) = sidecar.parent() {
        fs::create_dir_all(parent).map_err(|e| WatcherError::Io(e.to_string()))?;
    }
    fs::write(&sidecar, hash.as_bytes()).map_err(|e| WatcherError::Io(e.to_string()))
}

pub fn verify_checksum(enc_path: &Path, encrypted: &[u8]) -> Result<(), WatcherError> {
    let sidecar = checksum_sidecar_path(enc_path);
    if !sidecar.exists() {
        warn!(path = %sidecar.display(), "checksum sidecar missing; writing new manifest");
        write_checksum_sidecar(enc_path, encrypted)?;
        return Ok(());
    }
    let expected = fs::read_to_string(&sidecar).map_err(|e| WatcherError::Io(e.to_string()))?;
    let actual = sha256_hex(encrypted);
    if expected.trim() != actual {
        return Err(WatcherError::ChecksumMismatch(
            enc_path.display().to_string(),
        ));
    }
    Ok(())
}

pub fn verify_checksum_strict(enc_path: &Path, encrypted: &[u8]) -> Result<(), WatcherError> {
    let sidecar = checksum_sidecar_path(enc_path);
    if !sidecar.exists() {
        return Err(WatcherError::ChecksumMismatch(format!(
            "checksum sidecar missing for {}",
            enc_path.display()
        )));
    }
    let expected = fs::read_to_string(&sidecar).map_err(|e| WatcherError::Io(e.to_string()))?;
    let actual = sha256_hex(encrypted);
    if expected.trim() != actual {
        return Err(WatcherError::ChecksumMismatch(
            enc_path.display().to_string(),
        ));
    }
    Ok(())
}

pub fn atomic_write_bytes(path: &Path, bytes: &[u8]) -> Result<(), WatcherError> {
    trusted_folder::write_bytes_atomic(path, bytes).map_err(WatcherError::from)
}

pub fn resolve_master_key(
    app: &AppHandle,
    key_id: &str,
    override_key: Option<&str>,
) -> Result<Vec<u8>, WatcherError> {
    if let Some(key) = override_key {
        let trimmed = key.trim();
        if !trimmed.is_empty() {
            return Ok(trimmed.as_bytes().to_vec());
        }
    }

    load_master_key(app, key_id)
}

pub fn load_master_key(app: &AppHandle, key_id: &str) -> Result<Vec<u8>, WatcherError> {
    #[cfg(target_os = "macos")]
    {
        use keyring::Entry;
        for id in [key_id, "suchconfig.project_manager.vault", "vault_master"] {
            if let Ok(entry) = Entry::new(VAULT_KEYCHAIN_SERVICE, id) {
                if let Ok(pw) = entry.get_password() {
                    if !pw.is_empty() {
                        return Ok(pw.into_bytes());
                    }
                }
            }
        }
    }

    if let Ok(path) = app.path().app_data_dir() {
        let file = path.join("suchconfig_vault_key");
        if file.exists() {
            if let Ok(contents) = fs::read_to_string(&file) {
                let key = contents.trim();
                if !key.is_empty() {
                    return Ok(key.as_bytes().to_vec());
                }
            }
        }
    }

    let home_fallback = std::env::var("HOME").ok().map(|h| {
        PathBuf::from(h)
            .join(VAULT_KEY_HOME_DIR)
            .join("suchconfig_vault_key")
    });
    if let Some(path) = home_fallback {
        if path.exists() {
            if let Ok(contents) = fs::read_to_string(&path) {
                let key = contents.trim();
                if !key.is_empty() {
                    return Ok(key.as_bytes().to_vec());
                }
            }
        }
    }

    Err(WatcherError::MasterKey(
        "no vault key in keychain or app data".to_string(),
    ))
}

fn derive_aes_key(master: &[u8], salt: &[u8]) -> Result<[u8; 32], WatcherError> {
    let mut key = [0u8; 32];
    Argon2::default()
        .hash_password_into(master, salt, &mut key)
        .map_err(|e| WatcherError::Crypto(e.to_string()))?;
    Ok(key)
}

pub fn encrypt_snapshot(master: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, WatcherError> {
    let mut salt = [0u8; SALT_LEN];
    let mut nonce_bytes = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    rand::thread_rng().fill_bytes(&mut nonce_bytes);

    let key = derive_aes_key(master, &salt)?;
    let cipher =
        Aes256Gcm::new_from_slice(&key).map_err(|e| WatcherError::Crypto(e.to_string()))?;
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| WatcherError::Crypto(e.to_string()))?;

    let mut out =
        Vec::with_capacity(ENVELOPE_MAGIC.len() + SALT_LEN + NONCE_LEN + ciphertext.len());
    out.extend_from_slice(ENVELOPE_MAGIC);
    out.extend_from_slice(&salt);
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

pub fn decrypt_snapshot(master: &[u8], blob: &[u8]) -> Result<Vec<u8>, WatcherError> {
    let header_len = ENVELOPE_MAGIC.len() + SALT_LEN + NONCE_LEN;
    if blob.len() < header_len || &blob[..ENVELOPE_MAGIC.len()] != ENVELOPE_MAGIC {
        return Err(WatcherError::Crypto(
            "invalid encrypted envelope".to_string(),
        ));
    }
    let salt = &blob[ENVELOPE_MAGIC.len()..ENVELOPE_MAGIC.len() + SALT_LEN];
    let nonce_bytes = &blob[ENVELOPE_MAGIC.len() + SALT_LEN..header_len];
    let ciphertext = &blob[header_len..];

    let key = derive_aes_key(master, salt)?;
    let cipher =
        Aes256Gcm::new_from_slice(&key).map_err(|e| WatcherError::Crypto(e.to_string()))?;
    let nonce = Nonce::from_slice(nonce_bytes);
    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| WatcherError::Crypto(e.to_string()))
}

pub trait VaultSnapshotStore: Send + Sync {
    fn export_snapshot(&self, role: VaultRole) -> Result<Vec<u8>, WatcherError>;
    fn import_snapshot(&self, role: VaultRole, snapshot: &[u8]) -> Result<(), WatcherError>;
}

#[derive(Default)]
pub struct SharedVaultStore {
    secrets: Mutex<Option<Vec<u8>>>,
    projects: Mutex<Option<Vec<u8>>>,
}

impl SharedVaultStore {
    pub fn register(&self, role: VaultRole, snapshot: Vec<u8>) {
        match role {
            VaultRole::Secrets => *self.secrets.lock() = Some(snapshot),
            VaultRole::Projects => *self.projects.lock() = Some(snapshot),
        }
    }
}

impl VaultSnapshotStore for SharedVaultStore {
    fn export_snapshot(&self, role: VaultRole) -> Result<Vec<u8>, WatcherError> {
        let guard = match role {
            VaultRole::Secrets => self.secrets.lock(),
            VaultRole::Projects => self.projects.lock(),
        };
        guard.clone().ok_or(WatcherError::SnapshotUnavailable(role))
    }

    fn import_snapshot(&self, role: VaultRole, snapshot: &[u8]) -> Result<(), WatcherError> {
        self.register(role, snapshot.to_vec());
        Ok(())
    }
}

struct ImportBridgeStore {
    inner: Arc<SharedVaultStore>,
    app: AppHandle,
}

impl VaultSnapshotStore for ImportBridgeStore {
    fn export_snapshot(&self, role: VaultRole) -> Result<Vec<u8>, WatcherError> {
        self.inner.export_snapshot(role)
    }

    fn import_snapshot(&self, role: VaultRole, snapshot: &[u8]) -> Result<(), WatcherError> {
        self.inner.import_snapshot(role, snapshot)?;
        let encoded = B64.encode(snapshot);
        self.app
            .emit(
                TRUSTED_FOLDER_IMPORT_EVENT,
                serde_json::json!({
                    "vault": role,
                    "snapshot_base64": encoded,
                    "byte_len": snapshot.len(),
                }),
            )
            .map_err(|e| WatcherError::EventEmit(e.to_string()))?;
        Ok(())
    }
}

fn is_watched_enc_file(sync_dir: &Path, path: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
        return false;
    };
    if !name.ends_with(ENC_FILE_SUFFIX) {
        return false;
    }
    VaultRole::from_filename(name).is_some() && path.starts_with(sync_dir)
}

struct WatcherRuntime {
    _watcher: RecommendedWatcher,
    #[expect(dead_code)]
    debounce_tx: mpsc::UnboundedSender<PathBuf>,
    shutdown_tx: watch::Sender<bool>,
    debounce_task: tauri::async_runtime::JoinHandle<()>,
}

static SELF_WRITE_GUARD: LazyLock<Mutex<HashMap<PathBuf, Instant>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub struct TrustedFolderAppState {
    pub store: Arc<SharedVaultStore>,
    runtime: Mutex<Option<Arc<WatcherRuntime>>>,
}

impl Default for TrustedFolderAppState {
    fn default() -> Self {
        Self {
            store: Arc::new(SharedVaultStore::default()),
            runtime: Mutex::new(None),
        }
    }
}

impl TrustedFolderAppState {
    pub fn is_watcher_running(&self) -> bool {
        self.runtime.lock().is_some()
    }

    pub fn make_watcher(&self, app: AppHandle) -> TrustedFolderWatcher {
        let bridge = Arc::new(ImportBridgeStore {
            inner: Arc::clone(&self.store),
            app: app.clone(),
        });
        TrustedFolderWatcher::new(app, bridge, DEFAULT_VAULT_KEY_ID.to_string())
    }

    pub fn start_watcher(&self, app: AppHandle) -> Result<(), WatcherError> {
        self.make_watcher(app).start_watching(self)
    }

    pub fn stop_watcher(&self, app: AppHandle) -> Result<(), WatcherError> {
        self.make_watcher(app).stop_watching(self)
    }

    pub fn force_sync(&self, app: AppHandle, master_key: Option<String>) -> Result<(), WatcherError> {
        self.make_watcher(app)
            .sync_vaults_to_disk(master_key.as_deref())
    }

    pub fn try_auto_start_watcher(&self, app: &AppHandle) -> Result<(), WatcherError> {
        let config = load_config(app)?;
        let Some(path) = config
            .trusted_folder_path
            .filter(|p| !p.trim().is_empty())
        else {
            return Ok(());
        };
        if self.is_watcher_running() {
            return Ok(());
        }
        validate_trusted_folder(&path)?;
        info!(path = %path, "auto-starting trusted folder watcher");
        self.start_watcher(app.clone())
    }

    pub fn register_snapshot(
        &self,
        role: VaultRole,
        snapshot: Vec<u8>,
    ) -> Result<(), WatcherError> {
        self.store.register(role, snapshot);
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct TrustedFolderInfo {
    pub trusted_folder_path: Option<String>,
    pub sync_dir: Option<String>,
    pub watcher_running: bool,
    pub projects_enc_path: Option<String>,
    pub secrets_enc_path: Option<String>,
    pub projects_enc_present: bool,
    pub secrets_enc_present: bool,
    pub projects_enc_bytes: Option<u64>,
    pub secrets_enc_bytes: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultIntegrityReport {
    pub vault: String,
    pub present: bool,
    pub bytes: Option<u64>,
    pub checksum_ok: Option<bool>,
    pub decrypt_ok: Option<bool>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TrustedFolderIntegrityReport {
    pub sync_dir: Option<String>,
    pub projects: VaultIntegrityReport,
    pub secrets: VaultIntegrityReport,
    pub all_ok: bool,
}

fn enc_file_stat(path: &Path) -> (bool, Option<u64>) {
    match fs::metadata(path) {
        Ok(meta) if meta.is_file() => (true, Some(meta.len())),
        _ => (false, None),
    }
}

pub fn build_trusted_folder_info(
    app: &AppHandle,
    state: &TrustedFolderAppState,
) -> Result<TrustedFolderInfo, WatcherError> {
    let config = load_config(app)?;
    let path = config.trusted_folder_path.filter(|p| !p.trim().is_empty());
    let (sync_dir, projects_enc_path, secrets_enc_path, projects_enc_present, secrets_enc_present, projects_enc_bytes, secrets_enc_bytes) =
        match path.as_deref() {
        Some(p) => {
            let root = validate_trusted_folder(p).map_err(|e| {
                WatcherError::InvalidFolder(e.to_string())
            })?;
            let sync = ensure_sync_dir(&root)?;
            let (projects, secrets) = sync_enc_paths(&sync);
            let (projects_present, projects_bytes) = enc_file_stat(&projects);
            let (secrets_present, secrets_bytes) = enc_file_stat(&secrets);
            (
                Some(sync.display().to_string()),
                Some(projects.display().to_string()),
                Some(secrets.display().to_string()),
                projects_present,
                secrets_present,
                projects_bytes,
                secrets_bytes,
            )
        }
        None => (None, None, None, false, false, None, None),
    };
    Ok(TrustedFolderInfo {
        trusted_folder_path: path,
        sync_dir,
        watcher_running: state.is_watcher_running(),
        projects_enc_path,
        secrets_enc_path,
        projects_enc_present,
        secrets_enc_present,
        projects_enc_bytes,
        secrets_enc_bytes,
    })
}

fn verify_vault_enc_file(
    app: &AppHandle,
    key_id: &str,
    role: VaultRole,
    path: &Path,
    master_key: Option<&str>,
) -> VaultIntegrityReport {
    let vault = match role {
        VaultRole::Projects => "projects",
        VaultRole::Secrets => "secrets",
    }
    .to_string();

    if !path.is_file() {
        return VaultIntegrityReport {
            vault,
            present: false,
            bytes: None,
            checksum_ok: None,
            decrypt_ok: None,
            error: Some("backup file missing".to_string()),
        };
    }

    let bytes = match fs::metadata(path) {
        Ok(meta) if meta.is_file() => Some(meta.len()),
        _ => None,
    };

    let encrypted = match fs::read(path) {
        Ok(data) => data,
        Err(e) => {
            return VaultIntegrityReport {
                vault,
                present: true,
                bytes,
                checksum_ok: None,
                decrypt_ok: None,
                error: Some(format!("read failed: {e}")),
            };
        }
    };

    match verify_checksum_strict(path, &encrypted) {
        Ok(()) => {}
        Err(err) => {
            return VaultIntegrityReport {
                vault,
                present: true,
                bytes,
                checksum_ok: Some(false),
                decrypt_ok: None,
                error: Some(err.to_string()),
            };
        }
    }

    let decrypt_ok = if master_key.is_some() {
        match resolve_master_key(app, key_id, master_key) {
            Ok(master) => match decrypt_snapshot(&master, &encrypted) {
                Ok(_) => Some(true),
                Err(_) => Some(false),
            },
            Err(_) => Some(false),
        }
    } else {
        None
    };

    let error = if decrypt_ok == Some(false) {
        Some("decrypt failed — unlock your vault and try again".to_string())
    } else {
        None
    };

    VaultIntegrityReport {
        vault,
        present: true,
        bytes,
        checksum_ok: Some(true),
        decrypt_ok,
        error,
    }
}

pub fn build_trusted_folder_integrity_report(
    app: &AppHandle,
    master_key: Option<&str>,
) -> Result<TrustedFolderIntegrityReport, WatcherError> {
    let sync_dir = resolve_sync_dir(app)?;
    let (projects_path, secrets_path) = sync_enc_paths(&sync_dir);
    let key_id = DEFAULT_VAULT_KEY_ID;

    let projects = verify_vault_enc_file(
        app,
        key_id,
        VaultRole::Projects,
        &projects_path,
        master_key,
    );
    let secrets = verify_vault_enc_file(app, key_id, VaultRole::Secrets, &secrets_path, master_key);

    let all_ok = [projects.checksum_ok, secrets.checksum_ok]
        .into_iter()
        .all(|value| value != Some(false))
        && projects.error.is_none()
        && secrets.error.is_none()
        && (master_key.is_none()
            || [projects.decrypt_ok, secrets.decrypt_ok]
               .into_iter()
               .all(|value| value != Some(false)));

    Ok(TrustedFolderIntegrityReport {
        sync_dir: Some(sync_dir.display().to_string()),
        projects,
        secrets,
        all_ok,
    })
}

fn mark_self_write(path: &Path) {
    let until = Instant::now() + Duration::from_millis(DEBOUNCE_MS + 300);
    SELF_WRITE_GUARD
        .lock()
        .insert(path.to_path_buf(), until);
}

fn should_process_external_write(path: &Path) -> bool {
    let mut guard = SELF_WRITE_GUARD.lock();
    if let Some(until) = guard.get(path) {
        if Instant::now() < *until {
            return false;
        }
        guard.remove(path);
    }
    true
}

fn resolve_sync_dir(app: &AppHandle) -> Result<PathBuf, WatcherError> {
    let config = load_config(app)?;
    let trusted_path = config
        .trusted_folder_path
        .ok_or(WatcherError::NotConfigured)?;
    let trusted_root = validate_trusted_folder(&trusted_path)
        .map_err(|e| WatcherError::InvalidFolder(e.to_string()))?;
    ensure_sync_dir(&trusted_root).map_err(WatcherError::from)
}

pub struct TrustedFolderWatcher {
    app: AppHandle,
    store: Arc<dyn VaultSnapshotStore>,
    key_id: String,
}

impl TrustedFolderWatcher {
    pub fn new(app: AppHandle, store: Arc<dyn VaultSnapshotStore>, key_id: String) -> Self {
        Self { app, store, key_id }
    }

    pub fn start_watching(&self, state: &TrustedFolderAppState) -> Result<(), WatcherError> {
        if state.runtime.lock().is_some() {
            return Err(WatcherError::AlreadyRunning);
        }

        let sync_dir = resolve_sync_dir(&self.app)?;
        let (debounce_tx, debounce_rx) = mpsc::unbounded_channel();
        let (shutdown_tx, shutdown_rx) = watch::channel(false);

        let app_for_events = self.app.clone();
        let store_for_events = Arc::clone(&self.store);
        let key_id = self.key_id.clone();
        let sync_dir_for_task = sync_dir.clone();

        let debounce_task = tauri::async_runtime::spawn(async move {
            run_debounce_loop(
                debounce_rx,
                shutdown_rx,
                app_for_events,
                store_for_events,
                key_id,
                sync_dir_for_task,
            )
            .await;
        });

        let sync_dir_watch = sync_dir.clone();
        let debounce_tx_notify = debounce_tx.clone();
        let mut watcher = RecommendedWatcher::new(
            move |res: Result<notify::Event, notify::Error>| {
                let Ok(event) = res else {
                    return;
                };
                if !matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_)) {
                    return;
                }
                for path in event.paths {
                    if is_watched_enc_file(&sync_dir_watch, &path) {
                        let _ = debounce_tx_notify.send(path);
                    }
                }
            },
            Config::default().with_poll_interval(Duration::from_millis(400)),
        )
        .map_err(|e| WatcherError::Notify(e.to_string()))?;

        watcher
            .watch(&sync_dir, RecursiveMode::NonRecursive)
            .map_err(|e| WatcherError::Notify(e.to_string()))?;

        info!(sync_dir = %sync_dir.display(), "trusted folder watcher started");

        *state.runtime.lock() = Some(Arc::new(WatcherRuntime {
            _watcher: watcher,
            debounce_tx,
            shutdown_tx,
            debounce_task,
        }));

        Ok(())
    }

    pub fn stop_watching(&self, state: &TrustedFolderAppState) -> Result<(), WatcherError> {
        let runtime = state
            .runtime
            .lock()
            .take()
            .ok_or(WatcherError::NotRunning)?;
        let _ = runtime.shutdown_tx.send(true);
        runtime.debounce_task.abort();
        info!("trusted folder watcher stopped");
        Ok(())
    }

    pub fn sync_vaults_to_disk(&self, master_key: Option<&str>) -> Result<(), WatcherError> {
        let sync_dir = resolve_sync_dir(&self.app)?;
        let master = resolve_master_key(&self.app, &self.key_id, master_key)?;
        let (projects_path, secrets_path) = sync_enc_paths(&sync_dir);

        let projects_wrote =
            self.try_write_role_snapshot(VaultRole::Projects, &projects_path, &master)?;
        let secrets_wrote =
            self.try_write_role_snapshot(VaultRole::Secrets, &secrets_path, &master)?;

        if !projects_wrote && !secrets_wrote {
            return Err(WatcherError::SnapshotUnavailable(VaultRole::Projects));
        }

        self.app
            .emit(
                TRUSTED_FOLDER_SYNCED_EVENT,
                serde_json::json!({
                    "sync_dir": sync_dir.display().to_string(),
                    "projects_path": projects_path.display().to_string(),
                    "secrets_path": secrets_path.display().to_string(),
                    "projects_wrote": projects_wrote,
                    "secrets_wrote": secrets_wrote,
                }),
            )
            .map_err(|e| WatcherError::EventEmit(e.to_string()))?;

        self.app
            .emit(
                VAULT_UPDATED_EVENT,
                serde_json::json!({ "source": "trusted_folder_watcher" }),
            )
            .map_err(|e| WatcherError::EventEmit(e.to_string()))?;

        Ok(())
    }

    fn try_write_role_snapshot(
        &self,
        role: VaultRole,
        path: &Path,
        master: &[u8],
    ) -> Result<bool, WatcherError> {
        let plaintext = match self.store.export_snapshot(role) {
            Ok(snapshot) => snapshot,
            Err(WatcherError::SnapshotUnavailable(_)) => {
                info!(vault = ?role, "skipping trusted-folder write; no snapshot registered");
                return Ok(false);
            }
            Err(err) => return Err(err),
        };

        let encrypted = encrypt_snapshot(master, &plaintext)?;
        mark_self_write(path);
        atomic_write_bytes(path, &encrypted)?;
        write_checksum_sidecar(path, &encrypted)?;
        info!(vault = ?role, path = %path.display(), bytes = encrypted.len(), "wrote trusted-folder enc snapshot");
        Ok(true)
    }

    fn handle_incoming_enc(&self, path: PathBuf) -> Result<(), WatcherError> {
        if !should_process_external_write(&path) {
            return Ok(());
        }

        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| WatcherError::UnknownEncFile(path.display().to_string()))?;
        let role = VaultRole::from_filename(name)
            .ok_or_else(|| WatcherError::UnknownEncFile(name.to_string()))?;

        let encrypted = fs::read(&path).map_err(|e| WatcherError::Io(e.to_string()))?;
        verify_checksum(&path, &encrypted)?;
        let master = load_master_key(&self.app, &self.key_id)?;
        let plaintext = decrypt_snapshot(&master, &encrypted)?;
        self.store.import_snapshot(role, &plaintext)?;

        self.app
            .emit(
                VAULT_UPDATED_EVENT,
                serde_json::json!({
                    "source": "trusted_folder_watcher",
                    "vault": role,
                    "path": path.display().to_string(),
                }),
            )
            .map_err(|e| WatcherError::EventEmit(e.to_string()))?;

        info!(vault = ?role, path = %path.display(), "imported trusted-folder enc snapshot");
        Ok(())
    }
}

async fn run_debounce_loop(
    mut debounce_rx: mpsc::UnboundedReceiver<PathBuf>,
    mut shutdown_rx: watch::Receiver<bool>,
    app: AppHandle,
    store: Arc<dyn VaultSnapshotStore>,
    key_id: String,
    sync_dir: PathBuf,
) {
    let mut pending: HashMap<PathBuf, tauri::async_runtime::JoinHandle<()>> = HashMap::new();

    loop {
        tokio::select! {
            _ = shutdown_rx.changed() => {
                if *shutdown_rx.borrow() {
                    for (_, handle) in pending.drain() {
                        handle.abort();
                    }
                    break;
                }
            }
            msg = debounce_rx.recv() => {
                match msg {
                    Some(path) => {
                        if !is_watched_enc_file(&sync_dir, &path) {
                            continue;
                        }
                        if let Some(handle) = pending.remove(&path) {
                            handle.abort();
                        }
                        let watcher = TrustedFolderWatcher::new(app.clone(), Arc::clone(&store), key_id.clone());
                        let path_clone = path.clone();
                        let handle = tauri::async_runtime::spawn(async move {
                            tokio::time::sleep(Duration::from_millis(DEBOUNCE_MS)).await;
                            if let Err(e) = watcher.handle_incoming_enc(path_clone) {
                                error!(error = %e, "trusted folder import failed");
                            }
                        });
                        pending.insert(path, handle);
                    }
                    None => break,
                }
            }
        }
    }
}

#[tauri::command]
pub async fn setup_trusted_folder(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
    force_picker: Option<bool>,
    projects_archive_base64: Option<String>,
    secrets_archive_base64: Option<String>,
) -> Result<String, String> {
    let force = force_picker.unwrap_or(false);
    let path = trusted_folder::run_setup_trusted_folder(
        app.clone(),
        force,
        projects_archive_base64,
        secrets_archive_base64,
    )
    .await
    .map_err(|e| e.to_string())?;
    if state.is_watcher_running() {
        state
            .stop_watcher(app.clone())
            .map_err(WatcherError::into_command_string)?;
    }
    state
        .try_auto_start_watcher(&app)
        .map_err(WatcherError::into_command_string)?;
    Ok(path)
}

#[tauri::command]
pub async fn get_trusted_folder(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
) -> Result<TrustedFolderInfo, String> {
    build_trusted_folder_info(&app, &state).map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn verify_trusted_folder_integrity(
    app: tauri::AppHandle,
    master_key: Option<String>,
) -> Result<TrustedFolderIntegrityReport, String> {
    build_trusted_folder_integrity_report(&app, master_key.as_deref())
        .map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn force_sync_trusted_folder(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
    master_key: Option<String>,
) -> Result<(), String> {
    state
        .force_sync(app, master_key)
        .map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn start_trusted_folder_watcher(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
) -> Result<(), String> {
    state
        .start_watcher(app)
        .map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn stop_trusted_folder_watcher(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
) -> Result<(), String> {
    state
        .stop_watcher(app)
        .map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn trusted_folder_register_snapshot(
    state: State<'_, TrustedFolderAppState>,
    vault: String,
    snapshot_base64: String,
) -> Result<(), String> {
    let role = match vault.as_str() {
        "secrets" => VaultRole::Secrets,
        "projects" => VaultRole::Projects,
        _ => return Err(format!("unknown vault role: {vault}")),
    };
    let bytes = B64
        .decode(snapshot_base64.trim())
        .map_err(|e| format!("invalid base64: {e}"))?;
    state
        .register_snapshot(role, bytes)
        .map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn trusted_folder_notify_vault_updated(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
) -> Result<(), String> {
    state
        .force_sync(app, None)
        .map_err(WatcherError::into_command_string)
}

#[tauri::command]
pub async fn trusted_folder_vault_changed(
    app: tauri::AppHandle,
    state: State<'_, TrustedFolderAppState>,
    vault: String,
) -> Result<(), String> {
    let role = match vault.as_str() {
        "secrets" => VaultRole::Secrets,
        "projects" => VaultRole::Projects,
        _ => return Err(format!("unknown vault role: {vault}")),
    };
    info!(vault = ?role, "vault change received; pushing trusted-folder sync");
    state
        .force_sync(app, None)
        .map_err(WatcherError::into_command_string)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn atomic_write_roundtrip_stub() {
        let dir = TempDir::new().expect("tempdir");
        let path = dir.path().join("projects.loro.enc");
        atomic_write_bytes(&path, b"ciphertext").expect("write");
        let read = fs::read(&path).expect("read");
        assert_eq!(read, b"ciphertext");
    }

    #[test]
    fn sha256_checksum_verify_stub() {
        let dir = TempDir::new().expect("tempdir");
        let enc = dir.path().join("secrets.loro.enc");
        let bytes = b"encrypted-bytes";
        write_checksum_sidecar(&enc, bytes).expect("sidecar");
        verify_checksum(&enc, bytes).expect("verify");
        assert!(checksum_sidecar_path(&enc).exists());
    }

    #[test]
    fn verify_checksum_strict_rejects_missing_sidecar() {
        let dir = TempDir::new().expect("tempdir");
        let enc = dir.path().join("projects.loro.enc");
        atomic_write_bytes(&enc, b"ciphertext").expect("write");
        assert!(verify_checksum_strict(&enc, b"ciphertext").is_err());
    }

    #[test]
    fn export_snapshot_unavailable_when_not_registered() {
        let store = SharedVaultStore::default();
        let err = store
            .export_snapshot(VaultRole::Secrets)
            .expect_err("missing snapshot");
        assert!(matches!(err, WatcherError::SnapshotUnavailable(VaultRole::Secrets)));
    }

    #[test]
    fn merge_import_updates_shared_store_stub() {
        let store = SharedVaultStore::default();
        let snapshot = b"loro-snapshot-bytes";
        store
            .import_snapshot(VaultRole::Projects, snapshot)
            .expect("import");
        let exported = store.export_snapshot(VaultRole::Projects).expect("export");
        assert_eq!(exported, snapshot);
    }

    #[test]
    fn encrypt_decrypt_roundtrip_stub() {
        let master = b"test-master-key-material";
        let plain = b"loro-binary-snapshot";
        let enc = encrypt_snapshot(master, plain).expect("encrypt");
        let dec = decrypt_snapshot(master, &enc).expect("decrypt");
        assert_eq!(dec, plain);
    }

    #[test]
    fn role_from_filename_maps_enc_names() {
        assert_eq!(
            VaultRole::from_filename(PROJECTS_ENC_NAME),
            Some(VaultRole::Projects)
        );
        assert_eq!(
            VaultRole::from_filename(SECRETS_ENC_NAME),
            Some(VaultRole::Secrets)
        );
    }
}
