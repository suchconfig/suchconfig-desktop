use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

struct WatchState {
    watcher: RecommendedWatcher,
    root: PathBuf,
}

static WATCHERS: Mutex<Option<HashMap<i64, WatchState>>> = Mutex::new(None);

fn watchers() -> std::sync::MutexGuard<'static, Option<HashMap<i64, WatchState>>> {
    let mut guard = WATCHERS.lock().expect("watchers lock");
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
    guard
}

pub fn resolve_linked_file(root: &str, relative: &str) -> Result<PathBuf, String> {
    let root_path = PathBuf::from(root)
        .canonicalize()
        .map_err(|e| format!("Invalid linked root: {}", e))?;
    let rel = Path::new(relative);
    if rel.is_absolute() || rel.components().any(|c| matches!(c, Component::ParentDir)) {
        return Err("Invalid relative path".to_string());
    }
    let joined = root_path.join(rel);
    let canonical = joined
        .canonicalize()
        .map_err(|e| format!("File not found: {}", e))?;
    if !canonical.starts_with(&root_path) {
        return Err("Path escapes linked project root".to_string());
    }
    Ok(canonical)
}

#[tauri::command]
pub fn write_linked_file(
    root: String,
    relative_path: String,
    content: String,
) -> Result<(), String> {
    let path = resolve_linked_file(&root, &relative_path)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let tmp = path.with_extension("suchconfig.tmp");
    std::fs::write(&tmp, content.as_bytes()).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &path).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn read_linked_file(root: String, relative_path: String) -> Result<String, String> {
    let path = resolve_linked_file(&root, &relative_path)?;
    let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
    String::from_utf8(bytes).map_err(|_| "File is not valid UTF-8".to_string())
}

#[tauri::command]
pub fn read_linked_file_stat(
    root: String,
    relative_path: String,
) -> Result<serde_json::Value, String> {
    let path = resolve_linked_file(&root, &relative_path)?;
    let meta = std::fs::metadata(&path).map_err(|e| e.to_string())?;
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    Ok(serde_json::json!({ "mtime": mtime, "size": meta.len() }))
}

#[tauri::command]
pub fn watch_linked_project(app: AppHandle, folder_id: i64, root: String) -> Result<(), String> {
    let root_path = PathBuf::from(&root)
        .canonicalize()
        .map_err(|e| format!("Invalid linked root: {}", e))?;

    let _ = unwatch_linked_project(folder_id);

    let app_emit = app.clone();
    let root_for_filter = root_path.clone();
    let mut watcher = RecommendedWatcher::new(
        move |res: Result<Event, notify::Error>| {
            if let Ok(event) = res {
                if let Some(rel) = relative_path_from_event(&root_for_filter, &event.paths) {
                    let _ = app_emit.emit(
                        "linked_file_changed",
                        serde_json::json!({
                            "folder_id": folder_id,
                            "relative_path": rel
                        }),
                    );
                }
            }
        },
        Config::default().with_poll_interval(Duration::from_millis(400)),
    )
    .map_err(|e| e.to_string())?;

    watcher
        .watch(&root_path, RecursiveMode::NonRecursive)
        .map_err(|e| e.to_string())?;

    watchers().as_mut().unwrap().insert(
        folder_id,
        WatchState {
            watcher,
            root: root_path,
        },
    );

    Ok(())
}

#[tauri::command]
pub fn unwatch_linked_project(folder_id: i64) -> Result<(), String> {
    if let Some(map) = watchers().as_mut() {
        map.remove(&folder_id);
    }
    Ok(())
}

fn relative_path_from_event(root: &Path, paths: &[PathBuf]) -> Option<String> {
    for path in paths {
        let canonical = path.canonicalize().ok()?;
        if !canonical.starts_with(root) || !canonical.is_file() {
            continue;
        }
        let rel = canonical.strip_prefix(root).ok()?;
        let s = rel.to_string_lossy().trim_start_matches('/').to_string();
        if !s.is_empty() {
            return Some(s);
        }
    }
    None
}

impl Drop for WatchState {
    fn drop(&mut self) {
        let _ = self.watcher.unwatch(&self.root);
    }
}
