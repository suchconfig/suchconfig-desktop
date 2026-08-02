use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use tauri::{AppHandle, Manager};
use tracing::{info, warn};

pub const PHOENIX_PORT: u16 = 4000;

pub struct PhoenixSidecarState {
    child: Mutex<Option<Child>>,
}

impl PhoenixSidecarState {
    pub fn new() -> Self {
        Self {
            child: Mutex::new(None),
        }
    }

    pub fn stop(&self) {
        if let Ok(mut guard) = self.child.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill();
                let _ = child.wait();
                info!("phoenix sidecar stopped");
            }
        }
    }
}

pub fn ensure_started(app: &AppHandle) -> Result<(), String> {
    if server_already_running() {
        info!("phoenix already listening on port {}", PHOENIX_PORT);
        return Ok(());
    }

    if cfg!(debug_assertions) {
        return Err(
            "Phoenix is not running on localhost:4000. Use pnpm run tauri:dev (starts Phoenix via beforeDevCommand)."
                .to_string(),
        );
    }

    start_bundled_release(app)
}

fn server_already_running() -> bool {
    let url = format!("http://127.0.0.1:{PHOENIX_PORT}/");
    ureq::get(&url)
        .timeout(std::time::Duration::from_secs(2))
        .call()
        .map(|r| r.status() == 200 || r.status() == 302)
        .unwrap_or(false)
}

fn start_bundled_release(app: &AppHandle) -> Result<(), String> {
    let release_root = resolve_release_root(app)?;
    let bin = release_root.join("bin").join("suchconfig_desktop");
    if !bin.is_file() {
        return Err(format!(
            "phoenix sidecar binary missing at {}",
            bin.display()
        ));
    }

    let data_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("app data dir: {e}"))?;
    fs::create_dir_all(&data_dir).map_err(|e| format!("create app data dir: {e}"))?;

    let db_path = data_dir.join("suchconfig_desktop_prod.db");
    let log_path = data_dir.join("phoenix-sidecar.log");

    info!(
        "starting phoenix sidecar from {} (db: {})",
        release_root.display(),
        db_path.display()
    );

    let log_file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_path)
        .map_err(|e| format!("open phoenix log {}: {e}", log_path.display()))?;

    let child = Command::new(&bin)
        .current_dir(&release_root)
        .env("PHX_SERVER", "true")
        .env("PORT", PHOENIX_PORT.to_string())
        .env("PHX_HOST", "localhost")
        .env("RELEASE_DISTRIBUTION", "none")
        .env("SUCHCONFIG_DATABASE_PATH", &db_path)
        .arg("start")
        .stdout(Stdio::from(log_file.try_clone().map_err(|e| e.to_string())?))
        .stderr(Stdio::from(log_file))
        .spawn()
        .map_err(|e| format!("spawn phoenix sidecar: {e}"))?;

    if let Some(state) = app.try_state::<PhoenixSidecarState>() {
        if let Ok(mut guard) = state.child.lock() {
            *guard = Some(child);
        }
    } else {
        warn!("PhoenixSidecarState not managed; sidecar lifecycle not tracked");
    }

    Ok(())
}

fn resolve_release_root(app: &AppHandle) -> Result<PathBuf, String> {
    let resource_dir = app
        .path()
        .resource_dir()
        .map_err(|e| format!("resource dir: {e}"))?;

    let bundled = resource_dir
        .join("phoenix-sidecar")
        .join("suchconfig_desktop");

    if release_looks_valid(&bundled) {
        return Ok(bundled);
    }

    let dev_release = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("phoenix-app")
        .join("_build")
        .join("prod")
        .join("rel")
        .join("suchconfig_desktop");

    if release_looks_valid(&dev_release) {
        return Ok(dev_release);
    }

    Err(format!(
        "phoenix release not found (checked {} and {})",
        bundled.display(),
        dev_release.display()
    ))
}

fn release_looks_valid(root: &Path) -> bool {
    root.join("bin")
        .join("suchconfig_desktop")
        .is_file()
        && root.join("releases").is_dir()
}

pub fn stop_managed(app: &AppHandle) {
    if let Some(state) = app.try_state::<PhoenixSidecarState>() {
        state.stop();
    }
}
