use tauri::{Manager, State};

use super::frontiers::FrontierStore;
use super::pairing::{
    cancel_pairing, complete_pairing_initiator, confirm_pairing_responder, list_peers,
    local_device_info, remove_peer, start_pairing, submit_pairing_offer,
};
use super::P2pAppState;

#[tauri::command]
pub fn p2p_get_local_device(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let info = local_device_info(&app).map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(info).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_list_peers(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    let peers = list_peers(&app).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({ "peers": peers }))
}

#[tauri::command]
pub fn p2p_remove_peer(app: tauri::AppHandle, device_id: String) -> Result<serde_json::Value, String> {
    let removed = remove_peer(&app, &device_id).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({ "removed": removed, "deviceId": device_id }))
}

#[tauri::command]
pub fn p2p_start_pairing(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
) -> Result<serde_json::Value, String> {
    let result = start_pairing(&app, &state.pairing).map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_cancel_pairing(state: State<'_, P2pAppState>, session_id: String) -> Result<(), String> {
    cancel_pairing(&state.pairing, &session_id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn p2p_submit_pairing_offer(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
    offer_json: String,
) -> Result<serde_json::Value, String> {
    let result = submit_pairing_offer(&app, &state.pairing, &offer_json).map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_confirm_pairing_responder(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
    session_id: String,
) -> Result<serde_json::Value, String> {
    let result =
        confirm_pairing_responder(&app, &state.pairing, &session_id).map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_complete_pairing_initiator(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
    response_json: String,
) -> Result<serde_json::Value, String> {
    let result =
        complete_pairing_initiator(&app, &state.pairing, &response_json).map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(result).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_get_lan_sync_status(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
) -> Result<serde_json::Value, String> {
    let status = state.sync.status(&app).map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(status).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_set_lan_sync_enabled(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
    enabled: bool,
) -> Result<serde_json::Value, String> {
    let status = state
        .sync
        .set_enabled(&app, enabled)
        .map_err(|e| e.to_string())?;
    Ok(serde_json::to_value(status).map_err(|e| e.to_string())?)
}

#[tauri::command]
pub fn p2p_list_lan_peers(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
) -> Result<serde_json::Value, String> {
    let peers = state
        .sync
        .list_lan_peers(&app)
        .map_err(|e| e.to_string())?;
    Ok(serde_json::json!({ "peers": peers }))
}

#[tauri::command]
pub async fn p2p_connect_handoff(
    app: tauri::AppHandle,
    device_id: String,
) -> Result<serde_json::Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<P2pAppState>();
        state
            .sync
            .connect_handoff(&app, &device_id)
            .map_err(|e| e.to_string())?;
        Ok(serde_json::json!({ "ok": true, "deviceId": device_id }))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn p2p_send_handoff_bundles(
    app: tauri::AppHandle,
    bundles: Vec<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    let parsed: Vec<(String, String)> = bundles
        .into_iter()
        .filter_map(|entry| {
            let vault = entry.get("vault").and_then(|v| v.as_str())?;
            let snapshot = entry
                .get("snapshot_base64")
                .or_else(|| entry.get("snapshotBase64"))
                .and_then(|v| v.as_str())?;
            Some((vault.to_string(), snapshot.to_string()))
        })
        .collect();

    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<P2pAppState>();
        state
            .sync
            .send_handoff_bundles(&app, parsed)
            .map_err(|e| e.to_string())?;
        Ok(serde_json::json!({ "ok": true }))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn p2p_request_handoff(
    app: tauri::AppHandle,
    device_id: String,
    bundles: Vec<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    let parsed: Vec<(String, String)> = bundles
        .into_iter()
        .filter_map(|entry| {
            let vault = entry.get("vault").and_then(|v| v.as_str())?;
            let snapshot = entry
                .get("snapshot_base64")
                .or_else(|| entry.get("snapshotBase64"))
                .and_then(|v| v.as_str())?;
            Some((vault.to_string(), snapshot.to_string()))
        })
        .collect();

    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<P2pAppState>();
        state
            .sync
            .request_handoff(&app, &device_id, parsed)
            .map_err(|e| e.to_string())?;
        Ok(serde_json::json!({ "ok": true, "deviceId": device_id }))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub fn p2p_push_deltas(
    app: tauri::AppHandle,
    state: State<'_, P2pAppState>,
    device_id: Option<String>,
    updates: Vec<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    let parsed: Vec<super::protocol::DeltaUpdate> = updates
        .into_iter()
        .filter_map(|entry| serde_json::from_value(entry).ok())
        .collect();

    if let Some(id) = device_id {
        state
            .sync
            .push_deltas(&app, &id, parsed)
            .map_err(|e| e.to_string())?;
    } else {
        state
            .sync
            .push_deltas_to_online_peers(&app, parsed)
            .map_err(|e| e.to_string())?;
    }

    Ok(serde_json::json!({ "ok": true }))
}

#[tauri::command]
pub async fn p2p_iroh_spike_echo(
    app: tauri::AppHandle,
    device_id: String,
) -> Result<serde_json::Value, String> {
    Ok(tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<P2pAppState>();
        let result = state
            .sync
            .iroh_spike_echo(&app, &device_id)
            .map_err(|e| e.to_string())?;
        serde_json::to_value(result).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())??)
}

#[tauri::command]
pub fn p2p_get_item_frontier(
    app: tauri::AppHandle,
    peer_device_id: String,
    item_key: String,
) -> Result<serde_json::Value, String> {
    let entry = FrontierStore::get(&app, &peer_device_id, &item_key).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({ "frontier": entry }))
}

#[tauri::command]
pub fn p2p_set_item_frontier(
    app: tauri::AppHandle,
    peer_device_id: String,
    item_key: String,
    snapshot_base64: String,
    snapshot_hash: String,
) -> Result<serde_json::Value, String> {
    FrontierStore::set(
        &app,
        &peer_device_id,
        &item_key,
        &snapshot_base64,
        &snapshot_hash,
    )
    .map_err(|e| e.to_string())?;
    Ok(serde_json::json!({ "ok": true }))
}
