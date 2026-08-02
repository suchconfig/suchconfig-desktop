use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use tracing::{info, warn};
use uuid::Uuid;

#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

const MAX_FRAME_BYTES: usize = 1024 * 1024;

pub struct BrokerSidecarState {
    inner: Mutex<ManagedBroker>,
}

struct ManagedBroker {
    child: Option<Child>,
    scope_id: Option<String>,
    socket_path: PathBuf,
    manifest_path: Option<PathBuf>,
}

impl BrokerSidecarState {
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(ManagedBroker {
                child: None,
                scope_id: None,
                socket_path: default_socket_path(),
                manifest_path: None,
            }),
        }
    }

    pub fn stop(&self) {
        if let Ok(mut guard) = self.inner.lock() {
            let socket_path = guard.socket_path.clone();

            if let Some(mut child) = guard.child.take() {
                shutdown_child(&mut child);
                info!("broker sidecar stopped");
            }

            terminate_broker_at_socket(&socket_path);
            guard.scope_id = None;
            guard.manifest_path = None;
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BrokerSidecarStatus {
    pub running: bool,
    pub managed: bool,
    pub scope_id: Option<String>,
    pub socket_path: String,
    pub manifest_loaded: bool,
    pub health_status: Option<String>,
    pub proxy_enabled: bool,
    pub proxy_url: Option<String>,
    pub proxy_ca_cert_path: Option<String>,
    pub proxy_ca_fingerprint: Option<String>,
    pub proxy_ca_pinned: bool,
}

#[derive(Debug, Deserialize)]
struct BrokerIpcResponse {
    ok: bool,
    result: Option<serde_json::Value>,
    error: Option<BrokerIpcError>,
}

#[derive(Debug, Deserialize)]
struct BrokerIpcError {
    message: String,
}

pub fn default_run_dir() -> PathBuf {
    std::env::var("HOME")
        .map(|home| PathBuf::from(home).join(".suchconfig/run"))
        .unwrap_or_else(|_| PathBuf::from("/tmp/.suchconfig/run"))
}

pub fn default_socket_path() -> PathBuf {
    std::env::var("SUCHCONFIG_BROKER_SOCKET")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| default_run_dir().join("broker.sock"))
}

pub fn manifest_path_for_scope(scope_id: &str) -> PathBuf {
    default_run_dir().join(format!("{scope_id}.manifest.json"))
}

pub fn write_manifest(scope_id: &str, manifest: &serde_json::Value) -> Result<PathBuf, String> {
    let run_dir = default_run_dir();
    fs::create_dir_all(&run_dir).map_err(|error| format!("create run dir: {error}"))?;

    let path = manifest_path_for_scope(scope_id);
    let json = serde_json::to_string_pretty(manifest)
        .map_err(|error| format!("serialize manifest: {error}"))?;

    write_private_file(&path, json.as_bytes())?;
    Ok(path)
}

fn write_private_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
    #[cfg(unix)]
    {
        use std::fs::OpenOptions;
        use std::io::Write as _;

        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)
            .map_err(|error| format!("write {}: {error}", path.display()))?;
        file.write_all(bytes)
            .map_err(|error| format!("write {}: {error}", path.display()))?;
        return Ok(());
    }

    #[cfg(not(unix))]
    {
        fs::write(path, bytes).map_err(|error| format!("write {}: {error}", path.display()))
    }
}

pub fn resolve_cli_binary(app: &AppHandle) -> Result<PathBuf, String> {
    if let Ok(path) = std::env::var("SUCHCONFIG_CLI_PATH") {
        let candidate = PathBuf::from(path.trim());
        if candidate.is_file() {
            return Ok(candidate);
        }
    }

    let dev_cli = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("suchconfig-cli")
        .join("target")
        .join("debug")
        .join("suchconfig");

    if dev_cli.is_file() {
        return Ok(dev_cli);
    }

    let release_cli = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("suchconfig-cli")
        .join("target")
        .join("release")
        .join("suchconfig");

    if release_cli.is_file() {
        return Ok(release_cli);
    }

    if let Ok(output) = Command::new("which").arg("suchconfig").output() {
        if output.status.success() {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() {
                return Ok(PathBuf::from(path));
            }
        }
    }

    let _ = app;
    Err("suchconfig CLI not found; set SUCHCONFIG_CLI_PATH or build suchconfig-cli".to_string())
}

fn broker_ipc_request(socket_path: &Path, method: &str) -> Result<serde_json::Value, String> {
    #[cfg(unix)]
    {
        use std::os::unix::net::UnixStream;

        let mut stream = UnixStream::connect(socket_path)
            .map_err(|_| format!("broker not listening on {}", socket_path.display()))?;
        stream.set_read_timeout(Some(Duration::from_secs(5))).ok();
        stream.set_write_timeout(Some(Duration::from_secs(5))).ok();

        let request = serde_json::json!({
            "id": Uuid::new_v4().to_string(),
            "method": method,
            "params": {}
        });
        let payload =
            serde_json::to_vec(&request).map_err(|error| format!("encode request: {error}"))?;

        if payload.is_empty() || payload.len() > MAX_FRAME_BYTES {
            return Err("invalid request frame".into());
        }

        let len = u32::try_from(payload.len()).map_err(|_| "frame length overflow".to_string())?;
        stream
            .write_all(&len.to_be_bytes())
            .map_err(|error| format!("write request: {error}"))?;
        stream
            .write_all(&payload)
            .map_err(|error| format!("write request: {error}"))?;

        let mut len_buf = [0u8; 4];
        stream
            .read_exact(&mut len_buf)
            .map_err(|error| format!("read response length: {error}"))?;
        let resp_len = u32::from_be_bytes(len_buf) as usize;

        if resp_len == 0 || resp_len > MAX_FRAME_BYTES {
            return Err("invalid response frame".into());
        }

        let mut resp_buf = vec![0u8; resp_len];
        stream
            .read_exact(&mut resp_buf)
            .map_err(|error| format!("read response: {error}"))?;

        let response: BrokerIpcResponse = serde_json::from_slice(&resp_buf)
            .map_err(|error| format!("decode response: {error}"))?;

        if !response.ok {
            let message = response
                .error
                .map(|error| error.message)
                .unwrap_or_else(|| "broker request failed".into());
            return Err(message);
        }

        Ok(response.result.unwrap_or(serde_json::Value::Null))
    }

    #[cfg(not(unix))]
    {
        let _ = (socket_path, method);
        Err("Unix broker socket is not supported on this platform".into())
    }
}

fn wait_for_broker(socket_path: &Path, attempts: u32) -> Result<serde_json::Value, String> {
    for _ in 0..attempts {
        if let Ok(status) = broker_ipc_request(socket_path, "status") {
            return Ok(status);
        }
        std::thread::sleep(Duration::from_millis(200));
    }

    Err("broker failed to become ready".into())
}

fn child_running(child: &mut Child) -> bool {
    matches!(child.try_wait(), Ok(None))
}

fn shutdown_child(child: &mut Child) {
    #[cfg(unix)]
    {
        let pid = child.id();
        let _ = Command::new("kill")
            .args(["-TERM", &pid.to_string()])
            .status();

        for _ in 0..25 {
            if !child_running(child) {
                let _ = child.wait();
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    let _ = child.kill();
    let _ = child.wait();
}

fn terminate_broker_at_socket(socket_path: &Path) {
    wait_for_broker_down(socket_path, 25);
    kill_process_holding_socket(socket_path);
    wait_for_broker_down(socket_path, 10);
    cleanup_stale_socket(socket_path);
}

fn wait_for_broker_down(socket_path: &Path, attempts: u32) {
    for _ in 0..attempts {
        if broker_ipc_request(socket_path, "status").is_err() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
}

fn cleanup_stale_socket(socket_path: &Path) {
    let _ = fs::remove_file(socket_path);
}

#[cfg(unix)]
fn kill_process_holding_socket(socket_path: &Path) {
    let Ok(output) = Command::new("lsof")
        .args(["-t", &socket_path.to_string_lossy()])
        .output()
    else {
        return;
    };

    if !output.status.success() {
        return;
    }

    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let pid = line.trim();
        if pid.is_empty() {
            continue;
        }

        let _ = Command::new("kill").args(["-TERM", pid]).status();

        for _ in 0..15 {
            if Command::new("kill")
                .args(["-0", pid])
                .status()
                .map(|status| !status.success())
                .unwrap_or(true)
            {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }

        let _ = Command::new("kill").args(["-KILL", pid]).status();
    }
}

#[cfg(not(unix))]
fn kill_process_holding_socket(_socket_path: &Path) {}

fn status_from_ipc(
    ipc: serde_json::Value,
    managed: bool,
    socket_path: &Path,
    include_health: bool,
) -> BrokerSidecarStatus {
    let running = ipc.get("running").and_then(|value| value.as_bool()) == Some(true);
    let scope_id = ipc
        .get("scope_id")
        .and_then(|value| value.as_str())
        .map(str::to_string);
    let manifest_loaded = ipc
        .get("manifest_loaded")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let health_status = if include_health {
        broker_ipc_request(socket_path, "health")
            .ok()
            .and_then(|value| {
                value
                    .get("status")
                    .and_then(|status| status.as_str())
                    .map(str::to_string)
            })
    } else {
        Some("ok".into())
    };
    let proxy = ipc.get("proxy");
    let proxy_enabled = proxy
        .and_then(|value| value.get("enabled"))
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    let proxy_url = proxy
        .and_then(|value| value.get("url"))
        .and_then(|value| value.as_str())
        .map(str::to_string);
    let proxy_ca_cert_path = proxy
        .and_then(|value| value.get("ca_cert_path"))
        .and_then(|value| value.as_str())
        .map(str::to_string);
    let proxy_ca_fingerprint = proxy
        .and_then(|value| value.get("ca_fingerprint"))
        .and_then(|value| value.as_str())
        .map(str::to_string);
    let proxy_ca_pinned = match (scope_id.as_deref(), proxy_ca_fingerprint.as_deref()) {
        (Some(scope), Some(fingerprint)) if proxy_enabled => {
            pin_proxy_ca_fingerprint(scope, fingerprint)
        }
        _ => false,
    };

    BrokerSidecarStatus {
        running,
        managed,
        scope_id,
        socket_path: socket_path.display().to_string(),
        manifest_loaded,
        health_status,
        proxy_enabled,
        proxy_url,
        proxy_ca_cert_path,
        proxy_ca_fingerprint,
        proxy_ca_pinned,
    }
}

fn idle_status(socket_path: &Path) -> BrokerSidecarStatus {
    BrokerSidecarStatus {
        running: false,
        managed: false,
        scope_id: None,
        socket_path: socket_path.display().to_string(),
        manifest_loaded: false,
        health_status: None,
        proxy_enabled: false,
        proxy_url: None,
        proxy_ca_cert_path: None,
        proxy_ca_fingerprint: None,
        proxy_ca_pinned: false,
    }
}

fn pin_proxy_ca_fingerprint(scope_id: &str, fingerprint: &str) -> bool {
    use crate::app_identity::VAULT_KEYCHAIN_SERVICE;
    use keyring::Entry;

    let account = format!("broker-proxy-ca:{scope_id}");
    match Entry::new(VAULT_KEYCHAIN_SERVICE, &account) {
        Ok(entry) => match entry.set_password(fingerprint) {
            Ok(()) => true,
            Err(error) => {
                warn!("failed to pin broker proxy CA fingerprint: {error}");
                false
            }
        },
        Err(error) => {
            warn!("failed to open keychain for broker proxy CA pin: {error}");
            false
        }
    }
}

#[tauri::command]
pub async fn broker_start(
    app: AppHandle,
    scope_id: String,
    manifest: serde_json::Value,
    enable_proxy: bool,
) -> Result<BrokerSidecarStatus, String> {
    tokio::task::spawn_blocking(move || broker_start_sync(app, scope_id, manifest, enable_proxy))
        .await
        .map_err(|error| format!("broker start task failed: {error}"))?
}

fn broker_start_sync(
    app: AppHandle,
    scope_id: String,
    manifest: serde_json::Value,
    enable_proxy: bool,
) -> Result<BrokerSidecarStatus, String> {
    let scope_id = scope_id.trim().to_string();
    if scope_id.is_empty() {
        return Err("scope id required".into());
    }

    let state = app.state::<BrokerSidecarState>();
    let socket_path = default_socket_path();

    if let Ok(status) = broker_ipc_request(&socket_path, "status") {
        let existing_scope = status.get("scope_id").and_then(|value| value.as_str());

        let existing_proxy = status
            .get("proxy")
            .and_then(|proxy| proxy.get("enabled"))
            .and_then(|value| value.as_bool())
            .unwrap_or(false);

        if existing_scope == Some(scope_id.as_str()) && existing_proxy == enable_proxy {
            return Ok(status_from_ipc(status, false, &socket_path, false));
        }

        if let Some(existing) = existing_scope.filter(|_| existing_scope != Some(scope_id.as_str()))
        {
            return Err(format!(
                "broker already running for scope \"{existing}\" on {} — stop it first or use the same scope id",
                socket_path.display()
            ));
        }
    }

    let mut guard = state
        .inner
        .lock()
        .map_err(|_| "broker state lock poisoned".to_string())?;

    if let Some(child) = guard.child.as_mut() {
        if child_running(child) {
            if let Some(mut child) = guard.child.take() {
                shutdown_child(&mut child);
            }
        } else {
            guard.child = None;
        }
    }

    let manifest_path = write_manifest(&scope_id, &manifest)?;
    terminate_broker_at_socket(&socket_path);
    let cli = resolve_cli_binary(&app)?;
    let log_path = default_run_dir().join(format!("{scope_id}.broker.log"));

    let log_file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .map_err(|error| format!("open broker log {}: {error}", log_path.display()))?;

    info!(
        "starting broker sidecar scope={scope_id} cli={} manifest={}",
        cli.display(),
        manifest_path.display()
    );

    let mut command = Command::new(&cli);
    command
        .arg("broker")
        .arg("start")
        .arg("--scope")
        .arg(&scope_id)
        .arg("--manifest")
        .arg(&manifest_path);
    if enable_proxy {
        command.arg("--enable-proxy");
    }
    let child = command
        .env("SUCHCONFIG_LOCAL_BROKER_LICENSE", "true")
        .stdout(Stdio::from(
            log_file
                .try_clone()
                .map_err(|error| format!("broker log: {error}"))?,
        ))
        .stderr(Stdio::from(log_file))
        .spawn()
        .map_err(|error| format!("spawn broker: {error}"))?;

    guard.child = Some(child);
    guard.scope_id = Some(scope_id.clone());
    guard.socket_path = socket_path.clone();
    guard.manifest_path = Some(manifest_path);
    drop(guard);

    let status = wait_for_broker(&socket_path, 25)?;
    Ok(status_from_ipc(status, true, &socket_path, false))
}

#[tauri::command]
pub async fn broker_stop(app: AppHandle) -> Result<BrokerSidecarStatus, String> {
    tokio::task::spawn_blocking(move || {
        let state = app.state::<BrokerSidecarState>();
        let socket_path = {
            let guard = state
                .inner
                .lock()
                .map_err(|_| "broker state lock poisoned".to_string())?;
            guard.socket_path.clone()
        };

        state.stop();
        Ok(idle_status(&socket_path))
    })
    .await
    .map_err(|error| format!("broker stop task failed: {error}"))?
}

#[tauri::command]
pub async fn broker_status(
    app: AppHandle,
    scope_id: Option<String>,
) -> Result<BrokerSidecarStatus, String> {
    tokio::task::spawn_blocking(move || broker_status_sync(app, scope_id))
        .await
        .map_err(|error| format!("broker status task failed: {error}"))?
}

fn broker_status_sync(
    app: AppHandle,
    scope_id: Option<String>,
) -> Result<BrokerSidecarStatus, String> {
    let state = app.state::<BrokerSidecarState>();
    let (managed, expected_scope) = {
        let mut guard = state
            .inner
            .lock()
            .map_err(|_| "broker state lock poisoned".to_string())?;
        let managed = guard
            .child
            .as_mut()
            .map(|child| child_running(child))
            .unwrap_or(false);
        (managed, guard.scope_id.clone())
    };

    let socket_path = default_socket_path();
    let ipc = broker_ipc_request(&socket_path, "status").ok();

    let Some(ipc) = ipc else {
        return Ok(idle_status(&socket_path));
    };

    if let Some(expected) = scope_id.as_deref().filter(|value| !value.is_empty()) {
        if ipc.get("scope_id").and_then(|value| value.as_str()) != Some(expected) {
            return Ok(idle_status(&socket_path));
        }
    } else if let Some(expected) = expected_scope.as_deref() {
        if ipc.get("scope_id").and_then(|value| value.as_str()) != Some(expected) {
            return Ok(idle_status(&socket_path));
        }
    }

    Ok(status_from_ipc(ipc, managed, &socket_path, false))
}

pub fn stop_managed(app: &AppHandle) {
    if let Some(state) = app.try_state::<BrokerSidecarState>() {
        state.stop();
    } else {
        warn!("BrokerSidecarState not managed; sidecar lifecycle not tracked");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_path_for_scope_uses_run_dir() {
        let path = manifest_path_for_scope("my-app-staging");
        assert!(path
            .to_string_lossy()
            .ends_with("my-app-staging.manifest.json"));
        assert!(path.to_string_lossy().contains(".suchconfig/run"));
    }

    #[test]
    fn write_manifest_round_trip() {
        let dir = tempfile::tempdir().expect("tempdir");
        let original_home = std::env::var("HOME").ok();
        std::env::set_var("HOME", dir.path());

        let manifest = serde_json::json!({
            "scope_id": "uat-scope",
            "enabled": true,
            "allowed_domains": ["httpbin.org"],
            "folder_id": 1,
            "credentials": {}
        });

        let path = write_manifest("uat-scope", &manifest).expect("write manifest");
        assert!(path.is_file());

        let raw = fs::read_to_string(path).expect("read manifest");
        let decoded: serde_json::Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(decoded["scope_id"], "uat-scope");

        if let Some(home) = original_home {
            std::env::set_var("HOME", home);
        } else {
            std::env::remove_var("HOME");
        }
    }
}
