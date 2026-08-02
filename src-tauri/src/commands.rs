use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tauri::State;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    #[error("File error: {0}")]
    FileError(String),
    #[error("Parse error: {0}")]
    ParseError(String),
}

impl From<AppError> for String {
    fn from(error: AppError) -> Self {
        error.to_string()
    }
}

impl serde::Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct User {
    pub id: u32,
    pub name: String,
    pub email: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ParseResult {
    pub success: bool,
    pub data: Option<serde_json::Value>,
    pub error: Option<String>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FileInfo {
    pub name: String,
    pub size: u64,
    pub extension: String,
    pub modified: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AppState {
    pub users: Vec<User>,
    pub settings: HashMap<String, String>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            users: vec![
                User {
                    id: 1,
                    name: "John Doe".to_string(),
                    email: "john@example.com".to_string(),
                    created_at: "2024-01-01T00:00:00Z".to_string(),
                },
                User {
                    id: 2,
                    name: "Jane Smith".to_string(),
                    email: "jane@example.com".to_string(),
                    created_at: "2024-01-02T00:00:00Z".to_string(),
                },
            ],
            settings: HashMap::from([
                ("theme".to_string(), "dark".to_string()),
                ("language".to_string(), "en".to_string()),
            ]),
        }
    }
}

#[tauri::command]
pub async fn greet(name: &str) -> Result<String, AppError> {
    if name.is_empty() {
        return Err(AppError::InvalidInput("Name cannot be empty".to_string()));
    }
    Ok(format!("Hello, {}! You've been greeted from Rust!", name))
}

#[tauri::command]
pub async fn get_users(state: State<'_, AppState>) -> Result<Vec<User>, AppError> {
    Ok(state.users.clone())
}

#[tauri::command]
pub async fn add_user(
    name: String,
    email: String,
    state: State<'_, tokio::sync::Mutex<AppState>>,
) -> Result<User, AppError> {
    if name.is_empty() || email.is_empty() {
        return Err(AppError::InvalidInput("Name and email are required".to_string()));
    }
    
    if !email.contains('@') {
        return Err(AppError::InvalidInput("Invalid email format".to_string()));
    }

    let mut app_state = state.lock().await;
    let new_id = app_state.users.len() as u32 + 1;
    let user = User {
        id: new_id,
        name: name.clone(),
        email: email.clone(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };
    
    app_state.users.push(user.clone());
    Ok(user)
}

#[tauri::command]
pub async fn parse_text(text: String) -> Result<ParseResult, AppError> {
    if text.is_empty() {
        return Err(AppError::InvalidInput("Text cannot be empty".to_string()));
    }

    let word_count = text.split_whitespace().count();
    let char_count = text.chars().count();
    let line_count = text.lines().count();

    let mut metadata = HashMap::new();
    metadata.insert("word_count".to_string(), word_count.to_string());
    metadata.insert("char_count".to_string(), char_count.to_string());
    metadata.insert("line_count".to_string(), line_count.to_string());

    let parsed_data = serde_json::json!({
        "text": text,
        "statistics": {
            "words": word_count,
            "characters": char_count,
            "lines": line_count
        }
    });

    Ok(ParseResult {
        success: true,
        data: Some(parsed_data),
        error: None,
        metadata,
    })
}

#[tauri::command]
pub async fn get_file_info(path: String) -> Result<FileInfo, AppError> {
    use std::fs;
    use std::path::Path;

    let path = Path::new(&path);
    
    if !path.exists() {
        return Err(AppError::FileError("File does not exist".to_string()));
    }

    let metadata = fs::metadata(path)
        .map_err(|e| AppError::FileError(format!("Failed to read metadata: {}", e)))?;

    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string();

    let extension = path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or("")
        .to_string();

    let modified = metadata
        .modified()
        .map_err(|e| AppError::FileError(format!("Failed to get modified time: {}", e)))?
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| AppError::FileError(format!("Invalid time: {}", e)))?
        .as_secs();

    let modified_str = chrono::DateTime::from_timestamp(modified as i64, 0)
        .unwrap_or_default()
        .to_rfc3339();

    Ok(FileInfo {
        name,
        size: metadata.len(),
        extension,
        modified: modified_str,
    })
}

#[tauri::command]
pub async fn get_settings(state: State<'_, tokio::sync::Mutex<AppState>>) -> Result<HashMap<String, String>, AppError> {
    let app_state = state.lock().await;
    Ok(app_state.settings.clone())
}

#[tauri::command]
pub async fn update_setting(
    key: String,
    value: String,
    state: State<'_, tokio::sync::Mutex<AppState>>,
) -> Result<(), AppError> {
    if key.is_empty() {
        return Err(AppError::InvalidInput("Setting key cannot be empty".to_string()));
    }

    let mut app_state = state.lock().await;
    app_state.settings.insert(key, value);
    Ok(())
}

#[tauri::command]
pub async fn calculate_hash(text: String) -> Result<String, AppError> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    text.hash(&mut hasher);
    let hash = hasher.finish();
    Ok(format!("{:x}", hash))
}

#[tauri::command]
pub async fn validate_json(json_string: String) -> Result<serde_json::Value, AppError> {
    serde_json::from_str(&json_string)
        .map_err(|e| AppError::ParseError(format!("Invalid JSON: {}", e)))
}

#[tauri::command]
pub async fn process_large_file(file_path: String) -> Result<ProcessResult, AppError> {
    use std::time::Duration;
    use tokio::time::sleep;
    
    if file_path.is_empty() {
        return Err(AppError::InvalidInput("File path cannot be empty".to_string()));
    }

    let start_time = std::time::Instant::now();
    
    // Simulate processing stages with different delays
    let stages = vec![
        ("Reading file", 1000),
        ("Parsing content", 2000),
        ("Validating data", 1500),
        ("Generating report", 1000),
        ("Saving results", 500),
    ];

    let mut progress = Vec::new();
    
    for (stage_name, delay_ms) in stages {
        // Simulate work
        sleep(Duration::from_millis(delay_ms)).await;
        
        let elapsed = start_time.elapsed().as_millis();
        progress.push(ProcessingStage {
            stage: stage_name.to_string(),
            duration_ms: delay_ms,
            completed_at: elapsed,
        });
    }

    let total_time = start_time.elapsed().as_millis();
    
    Ok(ProcessResult {
        file_path: file_path,
        success: true,
        total_processing_time_ms: total_time,
        stages: progress,
        records_processed: 1000, // Simulated
        file_size_bytes: 1024 * 1024, // Simulated 1MB
    })
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProcessResult {
    pub file_path: String,
    pub success: bool,
    pub total_processing_time_ms: u128,
    pub stages: Vec<ProcessingStage>,
    pub records_processed: u32,
    pub file_size_bytes: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProcessingStage {
    pub stage: String,
    pub duration_ms: u64,
    pub completed_at: u128,
}

