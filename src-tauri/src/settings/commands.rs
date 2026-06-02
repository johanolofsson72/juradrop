// Spec 035 — panic-site ratchet (production code only; tests exempt via cfg_attr).
#![cfg_attr(
    not(test),
    deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)
)]

// Spec 010 / T014-T018, T042 — Tauri commands exposed to the WebView.
//
// See contracts/settings-commands.md for the full surface. Four user
// commands + the `get_app_version` info command for the About row.
//
// `set_model_tier` writes synchronously (from the user's POV) to disk
// inside the same critical section that updates the in-memory snapshot.
// Spec 027 — `start_tier_download` / `cancel_tier_download` /
// `get_tier_download_state` drive a REAL on-demand pull through
// `tier_download.rs` (its own backend-owned state + streaming
// `juradrop://settings/tier-download` channel), replacing the spec-010
// `trigger_tier_download` stub that emitted into a dead listener.

use std::sync::Arc;

use serde::Serialize;
use tauri::{AppHandle, Manager};

use super::file_io::{load_or_default, save, settings_file_path};
use super::snapshot::{SettingsSnapshot, SettingsState};
use super::tier_download;
use super::tier_map::ModelTier;
use crate::sidecar::commands::AppState;
use crate::sidecar::status::{ModelStatus, SidecarStatus};

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

/// Spec 027 — start a REAL on-demand pull of a non-bundled tier's model
/// (Snabb `llama3.2:1b`, Stor `gemma3:12b`). Replaces the spec-010 stub
/// (`trigger_tier_download`) whose event was wired to nothing. Refuses
/// honestly when the sidecar is not ready or a bundled first-run pull is
/// active (FR-010), or when another tier is already downloading (FR-009).
#[tauri::command]
pub async fn start_tier_download(
    app: AppHandle,
    sidecar: tauri::State<'_, AppState>,
    handle: tauri::State<'_, Arc<tier_download::TierDownloadHandle>>,
    tier: ModelTier,
) -> Result<(), String> {
    let already = tier_is_pulled(&sidecar, tier).await;
    // Ready to pull = Ollama reachable AND the spec-008 bundled pull is not
    // already running (no two pulls at once).
    let ready = matches!(sidecar.sidecar.status(), SidecarStatus::Ready)
        && !matches!(*sidecar.model_status.read(), ModelStatus::Downloading);
    let handle = handle.inner().clone();
    match tier_download::try_start(&handle, tier, ready, already) {
        tier_download::StartOutcome::Started => {
            tier_download::spawn_pull_task(app, handle, sidecar.client.clone(), tier);
            Ok(())
        }
        // Idempotent: a rapid double-click on a tier already downloading.
        tier_download::StartOutcome::AlreadyDownloadingThisTier => Ok(()),
        tier_download::StartOutcome::RefusedNotReady => Err("not_ready".into()),
        tier_download::StartOutcome::RefusedBusy => Err("busy".into()),
        tier_download::StartOutcome::RefusedAlreadyPulled => Err("already_pulled".into()),
    }
}

/// Spec 027 — cancel an in-flight tier download (FR-008). Trips the cancel
/// token, clears the slot, and emits a `cancelled` terminal event. The tier
/// is NOT reported pulled afterwards (a cancelled partial pull is not
/// installed). No-op if the given tier is not currently downloading.
#[tauri::command]
pub async fn cancel_tier_download(
    app: AppHandle,
    handle: tauri::State<'_, Arc<tier_download::TierDownloadHandle>>,
    tier: ModelTier,
) -> Result<(), String> {
    tier_download::cancel(&app, handle.inner(), tier);
    Ok(())
}

/// Spec 027 — current download state, for the panel to hydrate on open
/// (FR-011 — the pull is backend-owned and survives the panel closing).
#[tauri::command]
pub async fn get_tier_download_state(
    handle: tauri::State<'_, Arc<tier_download::TierDownloadHandle>>,
) -> Result<Option<tier_download::TierDownloadPayload>, String> {
    Ok(tier_download::current_payload(handle.inner()))
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
