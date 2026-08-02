use base64::engine::general_purpose;
use base64::Engine as _;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::Duration;
use tauri::{Emitter, Manager};
use tauri_plugin_dialog::DialogExt;
use url::Url;

mod app_identity;
mod broker_sidecar;
mod linked_sync;
mod native_passkey_reason;
mod p2p;
mod phoenix_sidecar;
mod trusted_folder;
mod trusted_folder_watcher;

use app_identity::{VAULT_KEY_HOME_DIR, VAULT_KEYCHAIN_SERVICE};
use tracing::warn;

const VAULT_KEY_FILENAME: &str = "suchconfig_vault_key";

fn vault_key_file_path(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    if let Ok(dir) = app.path().app_data_dir() {
        if std::fs::create_dir_all(&dir).is_ok() {
            return Ok(dir.join(VAULT_KEY_FILENAME));
        }
    }
    let fallback = if cfg!(target_os = "windows") {
        std::env::var("APPDATA")
            .ok()
            .map(|s| PathBuf::from(s).join(VAULT_KEY_HOME_DIR))
    } else {
        std::env::var("HOME")
            .ok()
            .map(|s| PathBuf::from(s).join(VAULT_KEY_HOME_DIR))
    };
    match fallback {
        Some(dir) => {
            std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
            Ok(dir.join(VAULT_KEY_FILENAME))
        }
        None => Err("Could not resolve app data or HOME directory.".to_string()),
    }
}

fn vault_key_fallback_path() -> Option<PathBuf> {
    let dir = if cfg!(target_os = "windows") {
        std::env::var("APPDATA")
            .ok()
            .map(|s| PathBuf::from(s).join(VAULT_KEY_HOME_DIR))?
    } else {
        std::env::var("HOME")
            .ok()
            .map(|s| PathBuf::from(s).join(VAULT_KEY_HOME_DIR))?
    };
    Some(dir.join(VAULT_KEY_FILENAME))
}

fn read_vault_key_from_file(app: &tauri::AppHandle) -> Option<String> {
    if let Ok(path) = vault_key_file_path(app) {
        if let Ok(contents) = fs::read_to_string(&path) {
            let key = contents
                .trim_end_matches('\n')
                .trim_end_matches('\r')
                .to_string();
            if !key.is_empty() {
                return Some(key);
            }
        }
    }
    if let Some(path) = vault_key_fallback_path() {
        if path.exists() {
            if let Ok(contents) = fs::read_to_string(&path) {
                let key = contents
                    .trim_end_matches('\n')
                    .trim_end_matches('\r')
                    .to_string();
                if !key.is_empty() {
                    return Some(key);
                }
            }
        }
    }
    None
}

const CONFIG_FILES: &[&str] = &[
    "package.json",
    "mix.exs",
    "Makefile",
    "Dockerfile",
    "docker-compose.yml",
    "docker-compose.yaml",
    "README.md",
    "readme.md",
    ".env.example",
    ".env.sample",
    ".nvmrc",
    ".node-version",
    ".tool-versions",
    "tsconfig.json",
    "vite.config.js",
    "vite.config.ts",
    "webpack.config.js",
    "next.config.js",
    "nuxt.config.js",
    "nuxt.config.ts",
    "angular.json",
    "vue.config.js",
    ".prettierrc",
    ".eslintrc.json",
    ".eslintrc.js",
    "pyproject.toml",
    "requirements.txt",
    "Cargo.toml",
    "go.mod",
];

#[tauri::command]
fn start_phoenix_server() -> Result<String, String> {
    let phoenix_path =
        std::env::var("SUCHCONFIG_DESKTOP_PATH").unwrap_or_else(|_| "./phoenix-app".to_string());

    let phoenix_mix_path = PathBuf::from(&phoenix_path).join("mix.exs");

    if !phoenix_mix_path.exists() {
        return Err(format!("Phoenix project not found at: {}", phoenix_path));
    }

    thread::spawn(move || {
        let mut child = Command::new("mix")
            .arg("phx.server")
            .current_dir(&phoenix_path)
            .spawn()
            .expect("Failed to start Phoenix server");

        let _ = child.wait();
    });

    thread::sleep(Duration::from_millis(2000));
    Ok("Phoenix LiveView server started successfully".to_string())
}

#[tauri::command]
async fn select_file() -> Result<Option<String>, String> {
    Ok(Some("File selection will be implemented here".to_string()))
}

#[tauri::command]
async fn select_csv_file(
    app_handle: tauri::AppHandle,
) -> Result<Option<serde_json::Value>, String> {
    let dialog = app_handle.dialog();

    let file_path = dialog
        .file()
        .set_title("Select CSV File")
        .add_filter("CSV Files", &["csv", "tsv", "txt"])
        .add_filter("All Files", &["*"])
        .blocking_pick_file();

    match file_path {
        Some(path) => {
            let path_str = path.to_string();
            let file_path = PathBuf::from(&path_str);

            if !file_path.exists() {
                return Err(format!("File not found: {}", path_str));
            }

            let filename = file_path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "unknown".to_string());

            let metadata = fs::metadata(&file_path)
                .map_err(|e| format!("Failed to read file metadata: {}", e))?;

            let content = fs::read_to_string(&file_path)
                .map_err(|e| format!("Failed to read file: {}", e))?;

            Ok(Some(serde_json::json!({
                "filename": filename,
                "size": metadata.len(),
                "content": content,
                "path": path_str
            })))
        }
        None => Ok(None),
    }
}

#[tauri::command]
async fn select_project_folder(app_handle: tauri::AppHandle) -> Result<Option<String>, String> {
    let dialog = app_handle.dialog();

    let folder_path = dialog
        .file()
        .set_title("Select Project Folder")
        .blocking_pick_folder();

    match folder_path {
        Some(path) => Ok(Some(path.to_string())),
        None => Ok(None),
    }
}

#[derive(serde::Deserialize)]
struct JobFileEntry {
    relative_path: String,
    content: String,
}

fn sanitize_job_slug(slug: &str) -> Result<String, String> {
    let s: String = slug
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' || c == '.' {
                c
            } else {
                '-'
            }
        })
        .collect();
    let trimmed = s.trim_matches('-').trim_matches('.');
    if trimmed.is_empty() {
        Err("Invalid job slug".to_string())
    } else {
        Ok(trimmed.to_string())
    }
}

#[tauri::command]
async fn select_jobs_folder(app_handle: tauri::AppHandle) -> Result<Option<String>, String> {
    let dialog = app_handle.dialog();
    let folder_path = dialog
        .file()
        .set_title("SuchConfig — job storage")
        .blocking_pick_folder();
    match folder_path {
        Some(path) => Ok(Some(path.to_string())),
        None => Ok(None),
    }
}

#[tauri::command]
async fn select_vault_export_folder(
    app_handle: tauri::AppHandle,
) -> Result<Option<String>, String> {
    let dialog = app_handle.dialog();
    let folder_path = dialog
        .file()
        .set_title("Export vault archive — choose folder")
        .blocking_pick_folder();
    match folder_path {
        Some(path) => Ok(Some(path.to_string())),
        None => Ok(None),
    }
}

#[tauri::command]
async fn write_archive_export(path: String, content_base64: String) -> Result<(), String> {
    let bytes = general_purpose::STANDARD
        .decode(content_base64.trim())
        .map_err(|e| format!("Invalid base64: {}", e))?;
    fs::write(&path, bytes).map_err(|e| format!("Failed to write archive: {}", e))?;
    Ok(())
}

#[tauri::command]
async fn save_job_files(
    root: String,
    slug: String,
    files: Vec<JobFileEntry>,
) -> Result<String, String> {
    let root_path = PathBuf::from(&root);
    if !root_path.is_dir() {
        return Err(format!("Job storage root is not a directory: {}", root));
    }
    let slug_safe = sanitize_job_slug(&slug)?;
    let job_dir = root_path.join(&slug_safe);
    fs::create_dir_all(&job_dir).map_err(|e| e.to_string())?;
    for entry in files {
        let rel = entry.relative_path.replace('\\', "/");
        if rel.contains("..") || rel.starts_with('/') {
            return Err("Invalid relative path in job bundle".to_string());
        }
        let target = job_dir.join(&rel);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::write(&target, entry.content.as_bytes()).map_err(|e| e.to_string())?;
    }
    Ok(job_dir.to_string_lossy().to_string())
}

#[tauri::command]
async fn remove_path(path: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    if !p.exists() {
        return Ok(());
    }
    if p.is_dir() {
        fs::remove_dir_all(&p).map_err(|e| e.to_string())
    } else {
        fs::remove_file(&p).map_err(|e| e.to_string())
    }
}

#[tauri::command]
fn reveal_path_in_file_manager(path: String) -> Result<(), String> {
    let p = PathBuf::from(&path);
    if !p.exists() {
        return Err(format!("Path does not exist: {}", path));
    }
    if cfg!(target_os = "windows") {
        Command::new("explorer")
            .arg(p.as_os_str())
            .spawn()
            .map_err(|e| e.to_string())?;
    } else if cfg!(target_os = "macos") {
        Command::new("open")
            .arg(&p)
            .spawn()
            .map_err(|e| e.to_string())?;
    } else {
        Command::new("xdg-open")
            .arg(&p)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn read_project_files(path: String) -> Result<HashMap<String, String>, String> {
    let project_path = PathBuf::from(&path);

    if !project_path.is_dir() {
        return Err(format!("Path is not a directory: {}", path));
    }

    let mut files_map: HashMap<String, String> = HashMap::new();

    for filename in CONFIG_FILES {
        let file_path = project_path.join(filename);

        if file_path.exists() && file_path.is_file() {
            match fs::read_to_string(&file_path) {
                Ok(content) => {
                    files_map.insert(filename.to_string(), content);
                }
                Err(e) => {
                    eprintln!("Failed to read {}: {}", filename, e);
                }
            }
        }
    }

    Ok(files_map)
}

#[tauri::command]
fn get_app_info() -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "name": "SuchConfig",
        "version": "0.1.0",
        "description": "Desktop parsing application with Phoenix LiveView"
    }))
}

#[tauri::command]
async fn read_file_content(path: String) -> Result<serde_json::Value, String> {
    let file_path = PathBuf::from(&path);

    if !file_path.exists() {
        return Err(format!("File not found: {}", path));
    }

    if !file_path.is_file() {
        return Err(format!("Path is not a file: {}", path));
    }

    let filename = file_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    let metadata =
        fs::metadata(&file_path).map_err(|e| format!("Failed to read file metadata: {}", e))?;

    let content =
        fs::read_to_string(&file_path).map_err(|e| format!("Failed to read file: {}", e))?;

    Ok(serde_json::json!({
        "filename": filename,
        "size": metadata.len(),
        "content": content,
        "path": path
    }))
}

#[tauri::command]
async fn save_file_dialog(
    app_handle: tauri::AppHandle,
    content: Option<String>,
    content_base64: Option<String>,
    default_name: String,
    filter_name: String,
    filter_extensions: Vec<String>,
) -> Result<Option<String>, String> {
    let file_bytes: Vec<u8> = match (&content_base64, &content) {
        (Some(b64), _) => general_purpose::STANDARD
            .decode(b64.trim())
            .map_err(|e| format!("Invalid base64: {}", e))?,
        (None, Some(text)) => text.as_bytes().to_vec(),
        (None, None) => {
            return Err(
                "Either content or contentBase64 is required for save_file_dialog".to_string(),
            );
        }
    };

    let dialog = app_handle.dialog();

    let suggested_name = if let Some(first) = filter_extensions.first() {
        if !first.is_empty() && first != "*" {
            let has_match = filter_extensions
                .iter()
                .any(|ext| default_name.ends_with(&format!(".{}", ext)));
            if has_match {
                default_name.clone()
            } else {
                let stem = default_name.trim_end_matches('.');
                format!("{}.{}", stem, first)
            }
        } else {
            default_name.clone()
        }
    } else {
        default_name.clone()
    };

    let file_path = if filter_extensions.len() == 1
        && filter_extensions.first().map(|s| s.as_str()) == Some("*")
    {
        dialog
            .file()
            .set_title("Save File")
            .set_file_name(&suggested_name)
            .blocking_save_file()
    } else {
        let extensions: Vec<&str> = filter_extensions.iter().map(|s| s.as_str()).collect();
        dialog
            .file()
            .set_title("Save File")
            .set_file_name(&suggested_name)
            .add_filter(&filter_name, &extensions)
            .add_filter("All Files", &["*"])
            .blocking_save_file()
    };

    let default_ext = default_name
        .rfind('.')
        .map(|i| default_name[i + 1..].to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_default();

    match file_path {
        Some(path) => {
            let mut path_str = path.to_string();
            if path_str.ends_with(".*") {
                path_str = path_str.trim_end_matches(".*").to_string();
            }
            if !path_str.contains('.') {
                if !default_ext.is_empty() {
                    path_str = format!("{}.{}", path_str, default_ext);
                } else if let Some(first) = filter_extensions.first() {
                    if !first.is_empty() && first != "*" {
                        path_str = format!("{}.{}", path_str, first);
                    }
                }
            }
            match fs::write(&path_str, &file_bytes) {
                Ok(_) => Ok(Some(path_str)),
                Err(e) => Err(format!("Failed to write file: {}", e)),
            }
        }
        None => Ok(None),
    }
}

#[tauri::command]
async fn native_global_passkey_availability() -> Result<serde_json::Value, String> {
    let supported = cfg!(target_os = "macos");
    let code = if supported {
        "ready_for_native_integration"
    } else {
        "unsupported_platform"
    };
    let message = if supported {
        "Native Global Passkey integration is available in stub mode."
    } else {
        "Global Passkey native features are currently available only on macOS."
    };

    Ok(serde_json::json!({
        "ok": supported,
        "supported": supported,
        "code": code,
        "message": message,
        "platform": std::env::consts::OS,
        "stub": true,
        "provider": if supported { "macos_keychain_touch_id_stub" } else { "unsupported_platform_stub" }
    }))
}

#[tauri::command]
async fn native_global_passkey_authenticate(
    reason: Option<String>,
) -> Result<serde_json::Value, String> {
    let supported = cfg!(target_os = "macos");
    let reason_kind = native_passkey_reason::NativePasskeyReason::from_input(reason.as_deref());
    let prompt_reason = reason_kind.prompt().to_string();
    let reason_code = reason_kind.code();
    let code = if supported {
        "not_implemented"
    } else {
        "unsupported_platform"
    };
    let message = if supported {
        "macOS Keychain/Touch ID authentication stub is not implemented yet."
    } else {
        "Global Passkey native auth is currently available only on macOS."
    };

    Ok(serde_json::json!({
        "ok": false,
        "supported": supported,
        "authenticated": false,
        "stub": true,
        "platform": std::env::consts::OS,
        "provider": if supported { "macos_keychain_touch_id_stub" } else { "unsupported_platform_stub" },
        "reason": prompt_reason,
        "reason_code": reason_code,
        "code": code,
        "message": message
    }))
}

#[tauri::command]
async fn native_global_passkey_store_wrapped_key(
    app: tauri::AppHandle,
    key_id: String,
    wrapped_key: String,
) -> Result<serde_json::Value, String> {
    let supported = cfg!(target_os = "macos");
    let reason_kind = native_passkey_reason::NativePasskeyReason::StoreWrappedKey;
    let prompt_reason = reason_kind.prompt();
    let reason_code = reason_kind.code();

    let (mut stored, mut code, mut message) = if supported {
        #[cfg(target_os = "macos")]
        {
            use keyring::Entry;
            match Entry::new(VAULT_KEYCHAIN_SERVICE, &key_id) {
                Ok(entry) => match entry.set_password(&wrapped_key) {
                    Ok(()) => (
                        true,
                        "ok",
                        "Vault key stored in system keychain.".to_string(),
                    ),
                    Err(e) => (
                        false,
                        "keychain_error",
                        format!("Keychain store failed: {}", e),
                    ),
                },
                Err(e) => (
                    false,
                    "keychain_error",
                    format!("Keychain entry create failed: {}", e),
                ),
            }
        }
        #[cfg(not(target_os = "macos"))]
        (
            false,
            "unsupported_platform",
            "Global Passkey storage is currently available only on macOS.".to_string(),
        )
    } else {
        (
            false,
            "unsupported_platform",
            "Global Passkey wrapped-key storage is currently available only on macOS.".to_string(),
        )
    };

    let mut written = false;
    if let Ok(path) = vault_key_file_path(&app) {
        if fs::write(&path, &wrapped_key).is_ok() {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
            }
            written = true;
        }
    }
    if let Some(path) = vault_key_fallback_path() {
        if fs::write(&path, &wrapped_key).is_ok() {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600));
            }
            written = true;
        }
    }
    if written {
        stored = true;
        code = "ok";
        message = "Vault key stored.".to_string();
    }

    Ok(serde_json::json!({
        "ok": stored,
        "supported": supported,
        "stored": stored,
        "stub": false,
        "platform": std::env::consts::OS,
        "provider": if supported { "macos_keychain" } else { "unsupported_platform_stub" },
        "reason": prompt_reason,
        "reason_code": reason_code,
        "message": message,
        "key_id": key_id,
        "wrapped_key_len": wrapped_key.len(),
        "code": code
    }))
}

#[tauri::command]
async fn native_global_passkey_load_wrapped_key(
    app: tauri::AppHandle,
    key_id: String,
) -> Result<serde_json::Value, String> {
    let supported = cfg!(target_os = "macos");
    let reason_kind = native_passkey_reason::NativePasskeyReason::LoadWrappedKey;
    let prompt_reason = reason_kind.prompt();
    let reason_code = reason_kind.code();

    let (mut found, mut wrapped_key_value, mut code, mut message) = if supported {
        #[cfg(target_os = "macos")]
        {
            use keyring::Entry;
            match Entry::new(VAULT_KEYCHAIN_SERVICE, &key_id) {
                Ok(entry) => match entry.get_password() {
                    Ok(pw) => (
                        true,
                        serde_json::Value::String(pw),
                        "ok",
                        "Vault key loaded from system keychain.".to_string(),
                    ),
                    Err(e) => (
                        false,
                        serde_json::Value::Null,
                        "keychain_error",
                        e.to_string(),
                    ),
                },
                Err(e) => (
                    false,
                    serde_json::Value::Null,
                    "keychain_error",
                    format!("Keychain entry create failed: {}", e),
                ),
            }
        }
        #[cfg(not(target_os = "macos"))]
        (
            false,
            serde_json::Value::Null,
            "unsupported_platform",
            "Global Passkey loading is currently available only on macOS.".to_string(),
        )
    } else {
        (
            false,
            serde_json::Value::Null,
            "unsupported_platform",
            "Global Passkey wrapped-key loading is currently available only on macOS.".to_string(),
        )
    };

    if !found {
        if let Some(key) = read_vault_key_from_file(&app) {
            found = true;
            wrapped_key_value = serde_json::Value::String(key);
            code = "ok";
            message = "Vault key loaded from app data.".to_string();
        }
    }

    Ok(serde_json::json!({
        "ok": found,
        "supported": supported,
        "found": found,
        "stub": false,
        "platform": std::env::consts::OS,
        "provider": if supported { "macos_keychain" } else { "unsupported_platform_stub" },
        "reason": prompt_reason,
        "reason_code": reason_code,
        "message": message,
        "key_id": key_id,
        "wrapped_key": wrapped_key_value,
        "code": code
    }))
}

#[tauri::command]
async fn native_global_passkey_clear_wrapped_key(
    app: tauri::AppHandle,
    key_id: String,
) -> Result<serde_json::Value, String> {
    let supported = cfg!(target_os = "macos");
    let reason_kind = native_passkey_reason::NativePasskeyReason::ClearWrappedKey;
    let prompt_reason = reason_kind.prompt();
    let reason_code = reason_kind.code();

    let (mut cleared, mut code, mut message) = if supported {
        #[cfg(target_os = "macos")]
        {
            use keyring::Entry;
            match Entry::new(VAULT_KEYCHAIN_SERVICE, &key_id) {
                Ok(entry) => match entry.delete_credential() {
                    Ok(()) => (
                        true,
                        "ok",
                        "Vault key removed from system keychain.".to_string(),
                    ),
                    Err(e) => (
                        false,
                        "keychain_error",
                        format!("Keychain clear failed: {}", e),
                    ),
                },
                Err(_) => (
                    false,
                    "keychain_error",
                    "Keychain entry not found.".to_string(),
                ),
            }
        }
        #[cfg(not(target_os = "macos"))]
        (
            false,
            "unsupported_platform",
            "Global Passkey clearing is currently available only on macOS.".to_string(),
        )
    } else {
        (
            false,
            "unsupported_platform",
            "Global Passkey wrapped-key clearing is currently available only on macOS.".to_string(),
        )
    };

    if let Ok(path) = vault_key_file_path(&app) {
        if path.exists() && fs::remove_file(&path).is_ok() {
            cleared = true;
        }
    }
    if let Some(path) = vault_key_fallback_path() {
        if path.exists() && fs::remove_file(&path).is_ok() {
            cleared = true;
        }
    }
    if cleared {
        code = "ok";
        message = "Vault key removed.".to_string();
    }

    Ok(serde_json::json!({
        "ok": cleared,
        "supported": supported,
        "cleared": cleared,
        "stub": false,
        "platform": std::env::consts::OS,
        "provider": if supported { "macos_keychain" } else { "unsupported_platform_stub" },
        "reason": prompt_reason,
        "reason_code": reason_code,
        "message": message,
        "key_id": key_id,
        "code": code
    }))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_biometry::init())
        .manage(trusted_folder_watcher::TrustedFolderAppState::default())
        .manage(phoenix_sidecar::PhoenixSidecarState::new())
        .manage(broker_sidecar::BrokerSidecarState::new())
        .manage(p2p::P2pAppState::default())
        .setup(|app| {
            let app_handle_for_p2p = app.handle().clone();
            thread::spawn(move || {
                if let Some(state) = app_handle_for_p2p.try_state::<p2p::P2pAppState>() {
                    if let Err(e) = state.sync.ensure_started_if_enabled(&app_handle_for_p2p) {
                        warn!("p2p lan sync auto-start skipped: {e}");
                    }
                }
            });

            let app_handle_for_nav = app.handle().clone();
            if let Some(state) = app.try_state::<trusted_folder_watcher::TrustedFolderAppState>() {
                if let Err(e) = state.try_auto_start_watcher(app.handle()) {
                    warn!("trusted folder watcher auto-start skipped: {e}");
                }
            }

            fn wait_for_server(url: &str, timeout_secs: u64) -> bool {
                let start = std::time::Instant::now();
                let timeout = Duration::from_secs(timeout_secs);

                while start.elapsed() < timeout {
                    if let Ok(response) = ureq::get(url).timeout(Duration::from_secs(2)).call() {
                        if response.status() == 200 || response.status() == 302 {
                            return true;
                        }
                    }
                    thread::sleep(Duration::from_millis(500));
                }
                false
            }

            // Set up drag-drop handler on the main window using window events
            if let Some(window) = app.get_webview_window("main") {
                let window_handle = window.clone();
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::DragDrop(drag_drop_event) = event {
                        match drag_drop_event {
                            tauri::DragDropEvent::Enter { paths, position: _ } => {
                                eprintln!("Drag enter with paths: {:?}", paths);
                                let _ = window_handle.emit("file-drop-hover", &paths);
                            }
                            tauri::DragDropEvent::Over { position: _ } => {
                                // Continuous hover, no need to emit repeatedly
                            }
                            tauri::DragDropEvent::Drop { paths, position: _ } => {
                                eprintln!("File drop with paths: {:?}", paths);
                                let path_strings: Vec<String> = paths
                                    .iter()
                                    .map(|p| p.to_string_lossy().to_string())
                                    .collect();
                                let _ = window_handle.emit("file-drop", &path_strings);
                            }
                            tauri::DragDropEvent::Leave => {
                                eprintln!("Drag leave");
                                let _ = window_handle.emit("file-drop-cancelled", ());
                            }
                            _ => {}
                        }
                    }
                });
                eprintln!("Drag-drop handler registered on main window");
            }

            thread::spawn(move || {
                let url_str = "http://localhost:4000";

                match phoenix_sidecar::ensure_started(&app_handle_for_nav) {
                    Ok(()) => {}
                    Err(e) => {
                        eprintln!("{e}");
                        if !cfg!(debug_assertions) {
                            return;
                        }
                    }
                }

                let timeout_secs = if cfg!(debug_assertions) { 120 } else { 90 };

                if wait_for_server(url_str, timeout_secs) {
                    if let Some(window) = app_handle_for_nav.get_webview_window("main") {
                        thread::sleep(Duration::from_millis(500));
                        match Url::parse(url_str) {
                            Ok(url) => {
                                if let Err(e) = window.navigate(url) {
                                    eprintln!("Failed to navigate to {}: {:?}", url_str, e);
                                } else {
                                    eprintln!("Successfully navigated to {}", url_str);
                                }
                            }
                            Err(e) => {
                                eprintln!("Failed to parse URL {}: {:?}", url_str, e);
                            }
                        }
                    } else {
                        eprintln!("Main window not found");
                    }
                } else {
                    eprintln!(
                        "Phoenix server failed to start within {} seconds",
                        timeout_secs
                    );
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            start_phoenix_server,
            select_file,
            select_csv_file,
            select_project_folder,
            select_jobs_folder,
            select_vault_export_folder,
            write_archive_export,
            save_job_files,
            remove_path,
            reveal_path_in_file_manager,
            read_project_files,
            read_file_content,
            get_app_info,
            save_file_dialog,
            native_global_passkey_availability,
            native_global_passkey_authenticate,
            native_global_passkey_store_wrapped_key,
            native_global_passkey_load_wrapped_key,
            native_global_passkey_clear_wrapped_key,
            linked_sync::write_linked_file,
            linked_sync::read_linked_file,
            linked_sync::read_linked_file_stat,
            linked_sync::watch_linked_project,
            linked_sync::unwatch_linked_project,
            trusted_folder_watcher::setup_trusted_folder,
            trusted_folder_watcher::get_trusted_folder,
            trusted_folder_watcher::verify_trusted_folder_integrity,
            trusted_folder::get_trusted_folder_path,
            trusted_folder::write_trusted_sync_archive,
            trusted_folder_watcher::force_sync_trusted_folder,
            trusted_folder_watcher::start_trusted_folder_watcher,
            trusted_folder_watcher::stop_trusted_folder_watcher,
            trusted_folder_watcher::trusted_folder_register_snapshot,
            trusted_folder_watcher::trusted_folder_notify_vault_updated,
            trusted_folder_watcher::trusted_folder_vault_changed,
            p2p::commands::p2p_get_local_device,
            p2p::commands::p2p_list_peers,
            p2p::commands::p2p_remove_peer,
            p2p::commands::p2p_start_pairing,
            p2p::commands::p2p_cancel_pairing,
            p2p::commands::p2p_submit_pairing_offer,
            p2p::commands::p2p_confirm_pairing_responder,
            p2p::commands::p2p_complete_pairing_initiator,
            p2p::commands::p2p_get_lan_sync_status,
            p2p::commands::p2p_set_lan_sync_enabled,
            p2p::commands::p2p_list_lan_peers,
            p2p::commands::p2p_connect_handoff,
            p2p::commands::p2p_send_handoff_bundles,
            p2p::commands::p2p_request_handoff,
            p2p::commands::p2p_push_deltas,
            p2p::commands::p2p_iroh_spike_echo,
            p2p::commands::p2p_get_item_frontier,
            p2p::commands::p2p_set_item_frontier,
            broker_sidecar::broker_start,
            broker_sidecar::broker_stop,
            broker_sidecar::broker_status,
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let tauri::RunEvent::Exit = event {
                phoenix_sidecar::stop_managed(&app_handle);
                broker_sidecar::stop_managed(&app_handle);
            }
        });
}
