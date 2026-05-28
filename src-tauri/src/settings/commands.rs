// Spec 010 / T014-T018, T042 — Tauri commands exposed to the WebView.
//
// See contracts/settings-commands.md for the full surface. Four user
// commands + the `get_app_version` info command for the About row.
//
// `set_model_tier` writes synchronously (from the user's POV) to disk
// inside the same critical section that updates the in-memory snapshot.
// `trigger_tier_download` is a stub here that emits a Tauri event the
// frontend listens for — wiring into the spec 008 wizard's real pull
// path is intentionally minimal in this iteration: we surface the
// intent, the panel + store reacts, and the existing spec 008 download
// UI handles the rest. The auto-select-after-pull listener in
// `settings-store.ts` listens for the same `juradrop://status` event
// the wizard already emits.

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use super::file_io::{load_or_default, save, settings_file_path};
use super::snapshot::{SettingsSnapshot, SettingsState};
use super::tier_map::ModelTier;
use crate::sidecar::commands::AppState;
use crate::sidecar::status::ModelStatus;

#[derive(Debug, Serialize, Clone)]
pub struct TierPullState {
    pub snabb_pulled: bool,
    pub smart_pulled: bool,
    pub stor_pulled: bool,
}

#[tauri::command]
pub async fn get_settings(
    state: tauri::State<'_, SettingsState>,
) -> Result<SettingsSnapshot, String> {
    Ok(state.snapshot())
}

#[tauri::command]
pub async fn set_model_tier(
    app: AppHandle,
    state: tauri::State<'_, SettingsState>,
    sidecar: tauri::State<'_, AppState>,
    tier: ModelTier,
) -> Result<(), String> {
    // Principle III enforcement: refuse to commit a tier whose model
    // is not pulled. The frontend MUST gate the radio with TierRowMode,
    // but this is belt-and-braces against a buggy UI bypassing the
    // gate (e.g. via devtools-equivalent direct invoke).
    if !tier_is_pulled(&sidecar, tier).await {
        return Err(format!(
            "TierNotPulled: cannot select {tier:?} because its model is not on disk"
        ));
    }
    // Update in-memory snapshot first, then persist. If persistence
    // fails, roll back the in-memory state so a subsequent get_settings
    // returns the truth.
    let previous = {
        let mut guard = state.inner.write();
        let prev = guard.clone();
        guard.model_tier = tier;
        prev
    };
    let path = settings_file_path(&app)?;
    let new_snapshot = state.snapshot();
    if let Err(e) = save(&path, &new_snapshot) {
        *state.inner.write() = previous;
        return Err(format!("WriteFailed: {e}"));
    }
    Ok(())
}

#[tauri::command]
pub async fn get_tier_pull_state(
    sidecar: tauri::State<'_, AppState>,
) -> Result<TierPullState, String> {
    let snabb = tier_is_pulled(&sidecar, ModelTier::Snabb).await;
    let smart = tier_is_pulled(&sidecar, ModelTier::Smart).await;
    let stor = tier_is_pulled(&sidecar, ModelTier::Stor).await;
    Ok(TierPullState {
        snabb_pulled: snabb,
        smart_pulled: smart,
        stor_pulled: stor,
    })
}

/// Spec 010 / T017 — request that a not-yet-pulled tier's model be
/// downloaded. Emits `juradrop://settings/tier-download-requested`
/// with the target tier; the spec 008 wizard's existing model-pull
/// path is invoked separately by the frontend's existing flow. This
/// minimal implementation keeps the spec 008 wizard's call signature
/// unchanged (the X1 remediation is satisfied because we add NO new
/// fields to start_model_pull, and the panel-aware event surface is
/// additive — old callers see nothing).
#[tauri::command]
pub async fn trigger_tier_download(app: AppHandle, tier: ModelTier) -> Result<(), String> {
    app.emit(
        "juradrop://settings/tier-download-requested",
        TierDownloadRequest {
            tier,
            model_id: tier.model_id().to_string(),
        },
    )
    .map_err(|e| format!("emit failed: {e}"))?;
    Ok(())
}

#[derive(Debug, Clone, Serialize)]
pub struct TierDownloadRequest {
    pub tier: ModelTier,
    pub model_id: String,
}

#[tauri::command]
pub async fn get_app_version(app: AppHandle) -> Result<String, String> {
    Ok(app.package_info().version.to_string())
}

/// Check whether a tier's underlying Ollama model is on disk.
/// Smart (`gemma3:4b`) reuses the existing `ModelStatus::Ready` signal
/// because the spec 008 wizard is wired to track Smart specifically.
/// Snabb and Stor are checked via direct sidecar list_tags() because
/// the spec 008 status path only tracks the default model.
async fn tier_is_pulled(sidecar: &tauri::State<'_, AppState>, tier: ModelTier) -> bool {
    let target = tier.model_id();
    if target == "gemma3:4b" {
        // Fast path: spec 008 already tracks this one.
        return matches!(*sidecar.model_status.read(), ModelStatus::Ready);
    }
    // Slow path: ask the sidecar for its tag list. Failure (sidecar
    // not ready, network error inside Ollama) → assume not pulled
    // so the panel renders the Ladda ned affordance — the user can
    // try again once the sidecar is up.
    match sidecar.client.list_tags().await {
        Ok(tags) => tags.iter().any(|t| t == target),
        Err(_) => false,
    }
}

/// Spec 010 / T002 — called from the Tauri setup callback to load the
/// snapshot from disk and manage it in app state. Idempotent: if a
/// SettingsState is already managed, it is overwritten with the
/// freshly-loaded one.
pub fn init_settings_state(app: &AppHandle) {
    let path = match settings_file_path(app) {
        Ok(p) => p,
        Err(_) => {
            // path resolution failed → use defaults; the dispatch
            // path still works because the default tier is Smart.
            app.manage(SettingsState::new(SettingsSnapshot::default()));
            return;
        }
    };
    let snapshot = load_or_default(&path);
    app.manage(SettingsState::new(snapshot));
}
