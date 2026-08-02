use serde::{Deserialize, Serialize};
use tauri::command;
use reqwest::Client;

#[derive(Debug, Serialize, Deserialize)]
pub struct JWTResponse {
    pub header: serde_json::Value,
    pub payload: serde_json::Value,
    pub signature: Option<String>,
    pub analysis: Option<JWTAnalysis>,
    pub provider: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct JWTAnalysis {
    pub security_score: u32,
    pub recommendations: Vec<String>,
    pub potential_vulnerabilities: Vec<String>,
    pub best_practices: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BulkJwtResult {
    pub token: String,
    pub header: serde_json::Value,
    pub payload: serde_json::Value,
    pub signature: Option<String>,
    pub security_score: u32,
    pub vulnerabilities: Vec<String>,
    pub recommendations: Vec<String>,
    pub best_practices: Vec<String>,
    pub processing_time_ms: u64,
    pub success: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BulkJwtResponse {
    pub batch_id: String,
    pub results: Vec<BulkJwtResult>,
    pub stats: BulkStats,
    pub provider: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BulkStats {
    pub batch_size: usize,
    pub success_count: usize,
    pub failed_count: usize,
    pub total_processing_time_ms: u64,
    pub avg_processing_time_per_token_ms: f64,
    pub avg_security_score: f64,
    pub total_vulnerabilities_found: usize,
    pub tokens_per_second: f64,
    pub service_stats: Option<ServiceStats>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceStats {
    pub total_processed: usize,
    pub avg_processing_time_ms: f64,
    pub total_vulnerabilities_found: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub data: Option<T>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ApiConnectionResponse {
    pub success: bool,
}

const API_BASE_URL: &str = "https://api.suchconfig.io";

#[command]
pub async fn decode_jwt(token: String) -> Result<ApiResponse<JWTResponse>, String> {
    let client = Client::new();
    
    match call_python_api(&client, "api/v1/jwt/parse", &serde_json::json!({ "token": token })).await {
        Ok(response) => {
            match response.get("data") {
                Some(data) => {
                    let jwt_response: JWTResponse = serde_json::from_value(data.clone())
                        .map_err(|e| format!("Failed to parse JWT response: {}", e))?;
                    Ok(ApiResponse {
                        data: Some(jwt_response),
                        error: None,
                    })
                }
                None => {
                    let error_msg = response.get("error")
                        .and_then(|e| e.as_str())
                        .unwrap_or("Unknown API error");
                    Ok(ApiResponse {
                        data: None,
                        error: Some(error_msg.to_string()),
                    })
                }
            }
        }
        Err(e) => {
            // Fallback to local decoding if API call fails
            match decode_jwt_locally(&token) {
                Ok(jwt_response) => Ok(ApiResponse {
                    data: Some(jwt_response),
                    error: None,
                }),
                Err(local_error) => Ok(ApiResponse {
                    data: None,
                    error: Some(format!("API error: {}, Local error: {}", e, local_error)),
                }),
            }
        }
    }
}

#[command]
pub async fn process_bulk_jwts(tokens: Vec<String>, batch_id: String) -> Result<ApiResponse<BulkJwtResponse>, String> {
    let client = Client::new();
    
    let payload = serde_json::json!({
        "tokens": tokens,
        "batch_id": batch_id
    });
    
    match call_python_api(&client, "api/v1/jwt/bulk-parse", &payload).await {
        Ok(response) => {
            match response.get("data") {
                Some(data) => {
                    let bulk_response: BulkJwtResponse = serde_json::from_value(data.clone())
                        .map_err(|e| format!("Failed to parse bulk JWT response: {}", e))?;
                    Ok(ApiResponse {
                        data: Some(bulk_response),
                        error: None,
                    })
                }
                None => {
                    let error_msg = response.get("error")
                        .and_then(|e| e.as_str())
                        .unwrap_or("Unknown API error");
                    Ok(ApiResponse {
                        data: None,
                        error: Some(error_msg.to_string()),
                    })
                }
            }
        }
        Err(e) => {
            // Fallback to local processing if API call fails
            match process_bulk_jwts_locally(&tokens, &batch_id) {
                Ok(bulk_response) => Ok(ApiResponse {
                    data: Some(bulk_response),
                    error: None,
                }),
                Err(local_error) => Ok(ApiResponse {
                    data: None,
                    error: Some(format!("API error: {}, Local error: {}", e, local_error)),
                }),
            }
        }
    }
}

#[command]
pub async fn test_api_connection() -> Result<ApiConnectionResponse, String> {
    let client = Client::new();
    
    match call_python_api(&client, "health", &serde_json::Value::Null).await {
        Ok(_) => Ok(ApiConnectionResponse { success: true }),
        Err(_) => Ok(ApiConnectionResponse { success: false }),
    }
}

async fn call_python_api(
    client: &Client,
    endpoint: &str,
    payload: &serde_json::Value,
) -> Result<serde_json::Value, String> {
    let url = format!("{}/{}", API_BASE_URL, endpoint);
    
    let response = client
        .post(&url)
        .json(payload)
        .header("X-Dev-Mode", "true")
        .header("X-Public-Request", "true")
        .send()
        .await
        .map_err(|e| format!("Request failed: {}", e))?;
    
    if !response.status().is_success() {
        return Err(format!("API returned status: {}", response.status()));
    }
    
    let json_response: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse JSON response: {}", e))?;
    
    Ok(json_response)
}

fn decode_jwt_locally(token: &str) -> Result<JWTResponse, String> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return Err("Invalid JWT format - must have 3 parts".to_string());
    }
    
    let header = base64_decode(parts[0])?;
    let payload = base64_decode(parts[1])?;
    let signature = parts[2].to_string();
    
    let header_json: serde_json::Value = serde_json::from_str(&header)
        .map_err(|e| format!("Failed to parse header: {}", e))?;
    let payload_json: serde_json::Value = serde_json::from_str(&payload)
        .map_err(|e| format!("Failed to parse payload: {}", e))?;
    
    // Basic security analysis
    let analysis = analyze_jwt(&header_json, &payload_json);
    
    Ok(JWTResponse {
        header: header_json,
        payload: payload_json,
        signature: Some(signature),
        analysis: Some(analysis),
        provider: Some("local".to_string()),
    })
}

fn process_bulk_jwts_locally(tokens: &[String], batch_id: &str) -> Result<BulkJwtResponse, String> {
    let mut results = Vec::new();
    let mut success_count = 0;
    let mut failed_count = 0;
    let mut total_vulnerabilities = 0;
    let start_time = std::time::Instant::now();
    
    for token in tokens {
        let token_start = std::time::Instant::now();
        match decode_jwt_locally(token) {
            Ok(jwt_response) => {
                success_count += 1;
                let analysis = jwt_response.analysis.as_ref().unwrap();
                total_vulnerabilities += analysis.potential_vulnerabilities.len();
                
                results.push(BulkJwtResult {
                    token: token.clone(),
                    header: jwt_response.header,
                    payload: jwt_response.payload,
                    signature: jwt_response.signature,
                    security_score: analysis.security_score,
                    vulnerabilities: analysis.potential_vulnerabilities.clone(),
                    recommendations: analysis.recommendations.clone(),
                    best_practices: analysis.best_practices.clone(),
                    processing_time_ms: token_start.elapsed().as_millis() as u64,
                    success: Some(true),
                });
            }
            Err(e) => {
                failed_count += 1;
                results.push(BulkJwtResult {
                    token: token.clone(),
                    header: serde_json::Value::Null,
                    payload: serde_json::Value::Null,
                    signature: None,
                    security_score: 0,
                    vulnerabilities: vec![e.clone()],
                    recommendations: vec![],
                    best_practices: vec![],
                    processing_time_ms: token_start.elapsed().as_millis() as u64,
                    success: Some(false),
                });
            }
        }
    }
    
    let total_time = start_time.elapsed().as_millis() as u64;
    let avg_processing_time = total_time as f64 / tokens.len() as f64;
    let avg_security_score = if success_count > 0 {
        results.iter()
            .filter(|r| r.success.unwrap_or(false))
            .map(|r| r.security_score as f64)
            .sum::<f64>() / success_count as f64
    } else {
        0.0
    };
    
    Ok(BulkJwtResponse {
        batch_id: batch_id.to_string(),
        results,
        stats: BulkStats {
            batch_size: tokens.len(),
            success_count,
            failed_count,
            total_processing_time_ms: total_time,
            avg_processing_time_per_token_ms: avg_processing_time,
            avg_security_score,
            total_vulnerabilities_found: total_vulnerabilities,
            tokens_per_second: tokens.len() as f64 / (total_time as f64 / 1000.0),
            service_stats: Some(ServiceStats {
                total_processed: tokens.len(),
                avg_processing_time_ms: avg_processing_time,
                total_vulnerabilities_found: total_vulnerabilities,
            }),
        },
        provider: "local".to_string(),
    })
}

fn base64_decode(input: &str) -> Result<String, String> {
    use base64::{Engine as _, engine::general_purpose};
    
    // Add padding if needed
    let mut padded = input.to_string();
    while padded.len() % 4 != 0 {
        padded.push('=');
    }
    
    let decoded = general_purpose::STANDARD
        .decode(&padded)
        .map_err(|e| format!("Base64 decode error: {}", e))?;
    
    String::from_utf8(decoded)
        .map_err(|e| format!("UTF-8 decode error: {}", e))
}

fn analyze_jwt(header: &serde_json::Value, payload: &serde_json::Value) -> JWTAnalysis {
    let mut security_score = 100;
    let mut recommendations = Vec::new();
    let mut vulnerabilities = Vec::new();
    let mut best_practices = Vec::new();
    
    // Basic algorithm check
    if let Some(alg) = header.get("alg").and_then(|v| v.as_str()) {
        match alg {
            "none" => {
                security_score -= 50;
                vulnerabilities.push("Using 'none' algorithm - no signature verification".to_string());
                recommendations.push("Use a proper signing algorithm (HS256, HS384, HS512, RS256, RS384, RS512, ES256, ES384, ES512, PS256, PS384, PS512)".to_string());
            }
            "HS256" | "HS384" | "HS512" | "RS256" | "RS384" | "RS512" | "ES256" | "ES384" | "ES512" | "PS256" | "PS384" | "PS512" => {
                best_practices.push(format!("Using secure algorithm: {}", alg));
            }
            _ => {
                security_score -= 15;
                recommendations.push(format!("Consider using a more secure algorithm: {}", alg));
            }
        }
    }
    
    // Expiration check
    if let Some(exp) = payload.get("exp").and_then(|v| v.as_u64()) {
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        if exp < current_time {
            security_score -= 25;
            vulnerabilities.push("Token has expired".to_string());
        } else if exp - current_time > 86400 * 365 {
            security_score -= 15;
            vulnerabilities.push("Token expiration too long (over 1 year)".to_string());
            recommendations.push("Consider shorter token expiration (max 1 year recommended)".to_string());
        } else {
            best_practices.push("Token has reasonable expiration time".to_string());
        }
    } else {
        security_score -= 15;
        vulnerabilities.push("No expiration time specified".to_string());
        recommendations.push("Add expiration time (exp) to token".to_string());
    }
    
    // Check for critical claims
    if payload.get("iss").is_some() {
        best_practices.push("Token includes issuer claim (iss)".to_string());
    } else {
        security_score -= 3;
        recommendations.push("Consider adding issuer claim (iss) for better security".to_string());
    }
    
    if payload.get("aud").is_some() {
        best_practices.push("Token includes audience claim (aud)".to_string());
    } else {
        security_score -= 3;
        recommendations.push("Consider adding audience claim (aud) for better security".to_string());
    }
    
    if payload.get("sub").is_some() {
        best_practices.push("Token includes subject claim (sub)".to_string());
    } else {
        security_score -= 3;
        recommendations.push("Consider adding subject claim (sub) for better security".to_string());
    }
    
    if payload.get("iat").is_some() {
        best_practices.push("Token includes issued-at claim (iat)".to_string());
        security_score += 2;
    }
    
    if payload.get("nbf").is_some() {
        best_practices.push("Token includes not-before claim (nbf)".to_string());
        security_score += 2;
    } else {
        security_score -= 2;
        recommendations.push("Consider adding not-before claim (nbf) to prevent early token use".to_string());
    }
    
    if payload.get("jti").is_some() {
        best_practices.push("Token includes JWT ID claim (jti)".to_string());
        security_score += 2;
    } else {
        security_score -= 2;
        recommendations.push("Consider adding JWT ID claim (jti) for token uniqueness".to_string());
    }
    
    if header.get("typ").and_then(|v| v.as_str()) == Some("JWT") {
        best_practices.push("Token includes explicit type claim".to_string());
        security_score += 1;
    }
    
    security_score = security_score.max(0);
    
    JWTAnalysis {
        security_score,
        recommendations,
        potential_vulnerabilities: vulnerabilities,
        best_practices,
    }
}
