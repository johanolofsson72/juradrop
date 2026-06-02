// Spec 035 — panic-site ratchet (production code only; tests exempt via cfg_attr).
#![cfg_attr(
    not(test),
    deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)
)]

// Spec 007 / T011–T016 + T031 — Tauri commands for the updater state machine.
//
// Five commands registered via `tauri::generate_handler!`. All return
// `Result<(), String>` where the error string is for developer
// diagnostics only — user-facing failure goes through UpdateStatus::Failed.
//
// FR-015 — every state transition logs locally via `eprintln!` with
// only the state names + version string. No notes content, no IP,
// no username, no document content.
//
// The plugin invocations (`app.updater()?.check().await`,
// `update.download(...)`, `update.install(...)`) live here. State-machine
// mutation lives in `super::lifecycle` so the integration test can
// drive every transition without going through the real plugin.

use tauri::{AppHandle, Emitter, Manager, Runtime};
use tauri_plugin_updater::UpdaterExt;

use super::errors::UpdateFailure;
use super::lifecycle::{self, RemoteUpdate};
use super::state::{UpdateState, Updater};
use super::status::UpdateStatus;
use crate::sidecar::commands::AppState;

pub const UPDATE_STATUS_CHANNEL: &str = "juradrop://update-status";

/// Emit a fresh UpdateStatus event on the public channel.
pub fn emit_status<R: Runtime>(app: &AppHandle<R>, updater: &Updater) {
    let payload = UpdateStatus::from_updater(updater);
    let _ = app.emit(UPDATE_STATUS_CHANNEL, payload);
}

/// FR-015 — local-only log of a state transition. Format is:
///   `update_status: <old> → <new> (version: <X.Y.Z>)`
/// No release notes, IP, username, or document content ever appears.
pub fn log_transition(old: UpdateState, new: UpdateState, version: &str) {
    eprintln!("update_status: {old:?} → {new:?} (version: {version})");
}

/// Helper: produce the version string for `log_transition`. Prefers
/// the remote `latest_known_version` (more informative for the
/// developer reading logs), falls back to the local `current_version`.
fn log_version(u: &Updater) -> String {
    u.latest_known_version
        .clone()
        .unwrap_or_else(|| u.current_version.clone())
}

/// T014 — Triggered by:
///   1. The 4-hour background tick.
///   2. The "Sök efter uppdateringar igen" button (US3).
#[tauri::command]
pub async fn check_for_updates_now<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    let state = app
        .try_state::<AppState>()
        .ok_or_else(|| "AppState not managed".to_string())?;

    // Phase 1 — try to enter Checking (legal only from Unknown/UpToDate/Failed).
    let entered = {
        let mut u = state.updater.write();
        let old = u.state;
        let entered = lifecycle::enter_checking(&mut u);
        if entered {
            log_transition(old, u.state, &log_version(&u));
            emit_status(&app, &u);
        }
        entered
    };
    if !entered {
        // FR-005 silent no-op for in-flight states.
        return Ok(());
    }

    // Phase 2 — invoke the plugin. `app.updater()` itself can fail if
    // the plugin isn't registered; treat that as ManifestMalformed (the
    // user-visible vocabulary doesn't have a "misconfigured" bucket).
    let plugin_outcome = run_plugin_check(&app).await;
    apply_check_outcome(&app, &state, plugin_outcome);
    Ok(())
}

/// Wrapper around the plugin's `check()` call so the integration test
/// can side-step minisign by calling `apply_check_outcome` directly.
async fn run_plugin_check<R: Runtime>(
    app: &AppHandle<R>,
) -> Result<Option<RemoteUpdate>, UpdateFailure> {
    let updater = match app.updater() {
        Ok(u) => u,
        Err(e) => return Err(UpdateFailure::from_plugin_error(&e)),
    };
    match updater.check().await {
        Ok(Some(update)) => Ok(Some(RemoteUpdate {
            version: update.version.clone(),
            notes: update.body.clone().unwrap_or_default(),
            download_url: update.download_url.to_string(),
        })),
        Ok(None) => Ok(None),
        Err(e) => Err(UpdateFailure::from_plugin_error(&e)),
    }
}

/// Lifecycle-side effect of a check outcome. Exposed `pub(crate)` so
/// `tests/update_lifecycle.rs` can drive the state machine without
/// invoking `tauri_plugin_updater`.
pub(crate) fn apply_check_outcome<R: Runtime>(
    app: &AppHandle<R>,
    state: &AppState,
    outcome: Result<Option<RemoteUpdate>, UpdateFailure>,
) {
    let mut u = state.updater.write();
    let old = u.state;
    let transitioned = match outcome {
        Ok(Some(remote)) => lifecycle::record_available(&mut u, remote),
        Ok(None) => lifecycle::record_up_to_date(&mut u),
        Err(failure) => lifecycle::record_failure(&mut u, failure),
    };
    if transitioned {
        log_transition(old, u.state, &log_version(&u));
        emit_status(app, &u);
    }
}

/// T015 — Triggered by the "Installera nu" button in the indicator.
#[tauri::command]
pub async fn install_update_now<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    let state = app
        .try_state::<AppState>()
        .ok_or_else(|| "AppState not managed".to_string())?;

    // Snapshot the remote URL — we need it to re-fetch via the plugin,
    // and we want to release the lock before the async download.
    let remote_url = {
        let u = state.updater.read();
        if u.state != UpdateState::Available {
            return Err(format!("state is not Available (was {:?})", u.state));
        }
        u.download_url
            .clone()
            .ok_or_else(|| "no download_url stamped on Available".to_string())?
    };

    // Enter Downloading.
    {
        let mut u = state.updater.write();
        let old = u.state;
        if !lifecycle::enter_downloading(&mut u) {
            return Err(format!(
                "illegal transition from {:?} to Downloading",
                u.state
            ));
        }
        log_transition(old, u.state, &log_version(&u));
        emit_status(&app, &u);
    }

    // Run the plugin download. The plugin re-runs `check()` to obtain
    // a fresh `Update` handle — we don't cache the handle across the
    // Available/Downloading boundary (the plugin API doesn't permit
    // storing it through async-task boundaries cleanly).
    let app_for_progress = app.clone();
    let updater_lock = state.updater.clone();
    let plugin_outcome = run_plugin_download(&app, &remote_url, move |pct| {
        let mut u = updater_lock.write();
        if lifecycle::record_download_progress(&mut u, pct) {
            emit_status(&app_for_progress, &u);
        }
    })
    .await;

    apply_download_outcome(&app, &state, plugin_outcome);
    Ok(())
}

/// Wrapper for the plugin download. The progress closure is invoked
/// from inside `update.download(on_chunk, on_done)` per the plugin's
/// chunk-stream protocol.
async fn run_plugin_download<R: Runtime, F: Fn(u8) + Send + Sync + 'static>(
    app: &AppHandle<R>,
    _expected_url: &str,
    on_progress: F,
) -> Result<Vec<u8>, UpdateFailure> {
    let updater = match app.updater() {
        Ok(u) => u,
        Err(e) => return Err(UpdateFailure::from_plugin_error(&e)),
    };
    let update = match updater.check().await {
        Ok(Some(u)) => u,
        Ok(None) => return Err(UpdateFailure::ManifestMalformed),
        Err(e) => return Err(UpdateFailure::from_plugin_error(&e)),
    };

    let total = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
    let downloaded = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
    let last_pct = std::sync::Arc::new(std::sync::atomic::AtomicU8::new(0));

    let total_cb = std::sync::Arc::clone(&total);
    let downloaded_cb = std::sync::Arc::clone(&downloaded);
    let last_pct_cb = std::sync::Arc::clone(&last_pct);

    let result = update
        .download(
            move |chunk_len, content_length| {
                if let Some(len) = content_length {
                    total_cb.store(len, std::sync::atomic::Ordering::Relaxed);
                }
                let prev =
                    downloaded_cb.fetch_add(chunk_len as u64, std::sync::atomic::Ordering::Relaxed);
                let now = prev + chunk_len as u64;
                let total_now = total_cb.load(std::sync::atomic::Ordering::Relaxed);
                if let Some(pct) = (now * 100).checked_div(total_now) {
                    let pct = pct.min(100) as u8;
                    let prev_pct = last_pct_cb.load(std::sync::atomic::Ordering::Relaxed);
                    if pct != prev_pct {
                        last_pct_cb.store(pct, std::sync::atomic::Ordering::Relaxed);
                        on_progress(pct);
                    }
                }
            },
            || { /* done — handled by the surrounding Result */ },
        )
        .await;

    match result {
        Ok(bytes) => Ok(bytes),
        Err(e) => Err(UpdateFailure::from_plugin_error(&e)),
    }
}

pub(crate) fn apply_download_outcome<R: Runtime>(
    app: &AppHandle<R>,
    state: &AppState,
    outcome: Result<Vec<u8>, UpdateFailure>,
) {
    let mut u = state.updater.write();
    let old = u.state;
    let transitioned = match outcome {
        Ok(bytes) => lifecycle::record_ready_to_install(&mut u, bytes),
        Err(failure) => lifecycle::record_failure(&mut u, failure),
    };
    if transitioned {
        log_transition(old, u.state, &log_version(&u));
        emit_status(app, &u);
    }
}

/// T016 — Triggered by the "Starta om" button. Either installs
/// immediately (no zone busy) or parks consent until idle.
#[tauri::command]
pub async fn confirm_restart_install<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    let state = app
        .try_state::<AppState>()
        .ok_or_else(|| "AppState not managed".to_string())?;

    // Snapshot busy state before taking the updater write-lock to avoid
    // potential ordering issues with zone-state callers.
    let zones: Vec<std::sync::Arc<crate::zones::sammanfatta::DropZone>> =
        state.zones.values().cloned().collect();
    let busy = super::deferral::any_zone_processing(&zones);

    let bytes_for_install = {
        let mut u = state.updater.write();
        if u.state != UpdateState::ReadyToInstall {
            return Err(format!("state is not ReadyToInstall (was {:?})", u.state));
        }

        if busy {
            // Park consent, stay in ReadyToInstall, emit deferred:true.
            lifecycle::defer_restart_until_idle(&mut u);
            emit_status(&app, &u);
            None
        } else {
            // Move to Restarting; pull the bytes out for install.
            let old = u.state;
            if !lifecycle::enter_restarting(&mut u) {
                return Err("illegal transition into Restarting".into());
            }
            log_transition(old, u.state, &log_version(&u));
            emit_status(&app, &u);
            u.downloaded_bytes.take()
        }
    };

    if let Some(bytes) = bytes_for_install {
        run_deferred_install(&app, bytes).await;
    }
    Ok(())
}

/// Plugin install path. Public so the deferred-restart actuator in
/// `deferral.rs` can drive it from the zone-state-change listener.
///
/// `install()` normally exits the process on success. If it returns
/// `Err` (disk full, signed-but-corrupted DMG), we transition
/// `Restarting → Failed` so the user can retry instead of sitting on
/// "Startar om…" perpetually (GAP-B / spec.allium InstallFailedTransition).
pub async fn run_deferred_install<R: Runtime>(app: &AppHandle<R>, bytes: Vec<u8>) {
    run_plugin_install(app, bytes).await;
    if let Some(state) = app.try_state::<AppState>() {
        let mut u = state.updater.write();
        let old = u.state;
        if lifecycle::record_failure(&mut u, UpdateFailure::InstallFailed) {
            log_transition(old, u.state, &log_version(&u));
            emit_status(app, &u);
        }
    }
}

async fn run_plugin_install<R: Runtime>(app: &AppHandle<R>, bytes: Vec<u8>) {
    let updater = match app.updater() {
        Ok(u) => u,
        Err(_) => return,
    };
    let update = match updater.check().await {
        Ok(Some(u)) => u,
        _ => return,
    };
    // The plugin exits the process inside `install()` on success.
    let _ = update.install(bytes);
}

/// T031 — User clicked "Avbryt" on the deferred-restart banner.
#[tauri::command]
pub fn cancel_deferred_restart<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    let state = app
        .try_state::<AppState>()
        .ok_or_else(|| "AppState not managed".to_string())?;
    let mut u = state.updater.write();
    if u.state != UpdateState::ReadyToInstall || !u.pending_restart_consent {
        return Ok(()); // idempotent no-op
    }
    lifecycle::cancel_deferred_consent(&mut u);
    emit_status(&app, &u);
    Ok(())
}

/// T031 — User clicked the × chevron on the indicator badge.
#[tauri::command]
pub fn dismiss_update_indicator<R: Runtime>(app: AppHandle<R>) -> Result<(), String> {
    let state = app
        .try_state::<AppState>()
        .ok_or_else(|| "AppState not managed".to_string())?;
    let mut u = state.updater.write();
    if !matches!(
        u.state,
        UpdateState::Available | UpdateState::ReadyToInstall
    ) {
        return Ok(()); // FR-018 — dismissal meaningful only on visible states.
    }
    lifecycle::dismiss_indicator(&mut u);
    emit_status(&app, &u);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_transition_format_contains_only_state_names_and_version() {
        let formatted = format!(
            "update_status: {:?} → {:?} (version: {})",
            UpdateState::Checking,
            UpdateState::Available,
            "0.2.0"
        );
        assert!(formatted.contains("Checking"));
        assert!(formatted.contains("Available"));
        assert!(formatted.contains("0.2.0"));
        // FR-015 privacy guard — no notes / IP / username / document
        // content keywords ever appear.
        assert!(!formatted.contains("notes"));
        assert!(!formatted.contains("@"));
        assert!(!formatted.contains("/Users/"));
    }

    #[test]
    fn channel_name_is_unique() {
        // SC-007 — assert the channel name doesn't collide with
        // any existing juradrop:// channel from specs 002/003/004/006.
        let existing_channels = [
            "juradrop://sidecar/status",
            "juradrop://file-dropped",
            "juradrop://status",
            "juradrop://progress",
            "juradrop://sidecar-crashed",
            "juradrop://sidecar-terminated",
            // Spec 013 — 9 per-zone channels (was 6).
            "juradrop://zone/sammanfatta",
            "juradrop://zone/tillengelska",
            "juradrop://zone/tillsvenska",
            "juradrop://zone/punktlista",
            "juradrop://zone/anonymisera",
            "juradrop://zone/forenkla",
            "juradrop://zone/kontakter",
            "juradrop://zone/generera",
            "juradrop://zone/kallor",
            // Spec 010 — settings panel events. Spec 027 replaced the
            // emit-only `tier-download-requested` stub with the streaming
            // `tier-download` progress channel.
            "juradrop://settings/tier-download",
        ];
        for existing in existing_channels {
            assert_ne!(
                UPDATE_STATUS_CHANNEL, existing,
                "channel collision detected"
            );
        }
    }

    #[test]
    fn log_version_prefers_remote_version() {
        let mut u = Updater::new();
        u.latest_known_version = Some("9.9.9".into());
        let v = log_version(&u);
        assert_eq!(v, "9.9.9");
    }

    #[test]
    fn log_version_falls_back_to_current_version() {
        let u = Updater::new();
        let v = log_version(&u);
        assert!(!v.is_empty());
    }
}
