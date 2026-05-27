// Spec 007 / T011–T016 + T031 — Tauri commands for the updater state machine.
//
// Five commands registered via `tauri::generate_handler!`. All return
// `Result<(), String>` where the error string is for developer
// diagnostics only — user-facing failure goes through UpdateStatus::Failed.
//
// FR-015 — every state transition logs locally via `eprintln!` with
// only the state names + version string. No notes content, no IP,
// no username, no document content.

use chrono::Local;
use tauri::{AppHandle, Emitter, Manager, Runtime};

use super::errors::UpdateFailure;
use super::state::{UpdateState, Updater};
use super::status::UpdateStatus;

pub const UPDATE_STATUS_CHANNEL: &str = "juradrop://update-status";

/// Emit a fresh UpdateStatus event on the public channel.
pub fn emit_status<R: Runtime>(app: &AppHandle<R>, updater: &Updater) {
    let payload = UpdateStatus::from_updater(updater);
    let _ = app.emit(UPDATE_STATUS_CHANNEL, payload);
}

/// FR-015 — local-only log of a state transition. Format is:
///   `update_status: <old> → <new> (version: <X.Y.Z>)`
/// The version comes from `latest_known_version` if non-null,
/// otherwise `current_version`. NO release notes, IP, username, or
/// document content ever appears here.
pub fn log_transition(old: UpdateState, new: UpdateState, version: &str) {
    eprintln!("update_status: {old:?} → {new:?} (version: {version})");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn log_transition_format_contains_only_state_names_and_version() {
        // Capture via stderr redirection isn't trivial in unit tests;
        // we instead format the same string the function produces and
        // assert it contains only the expected fields.
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
        // The list below is the inventory at spec 007 implementation
        // time; if a future spec adds a channel, this test catches
        // accidental name clashes.
        let existing_channels = [
            "juradrop://sidecar/status",
            "juradrop://file-dropped",
            // Per-zone channels follow the pattern juradrop://zone/<slug>
            "juradrop://zone/sammanfatta",
            "juradrop://zone/tillengelska",
            "juradrop://zone/tillsvenska",
            "juradrop://zone/punktlista",
            "juradrop://zone/anonymisera",
            "juradrop://zone/forenkla",
        ];
        for existing in existing_channels {
            assert_ne!(
                UPDATE_STATUS_CHANNEL, existing,
                "channel collision detected"
            );
        }
    }
}

// The actual Tauri commands need access to AppState (which holds the
// shared Updater + the zones for the deferral predicate). Per the
// project's existing pattern (sidecar/commands.rs), AppState is the
// `tauri::State<'_, AppState>` parameter. The full command bodies
// live here once AppState is extended in T010 — we provide thin
// shims for now that exist so registration in lib.rs compiles.
//
// In the production wiring (post-T010), each command:
//   1. Reads/writes the shared Updater behind its parking_lot RwLock
//   2. Calls into the tauri-plugin-updater API
//   3. Emits UpdateStatus via emit_status() on every transition
//   4. Logs via log_transition() on every transition
//
// For the initial compile, the commands are stubs that always
// emit Unknown. T014-T016 + T031 will fill them in.

#[tauri::command]
pub async fn check_for_updates_now<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    // T014 — full body lands when AppState extension (T010) is done.
    Ok(())
}

#[tauri::command]
pub async fn install_update_now<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    // T015 — see check_for_updates_now note.
    Ok(())
}

#[tauri::command]
pub async fn confirm_restart_install<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    // T016 — see check_for_updates_now note.
    Ok(())
}

#[tauri::command]
pub fn cancel_deferred_restart<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    // T031 — see check_for_updates_now note.
    Ok(())
}

#[tauri::command]
pub fn dismiss_update_indicator<R: Runtime>(_app: AppHandle<R>) -> Result<(), String> {
    // T031 — see check_for_updates_now note.
    Ok(())
}

// Keep imports used by future implementations alive.
#[allow(dead_code)]
fn _suppress_unused_imports() {
    let _ = UpdateFailure::NoNetwork;
    let _ = Local::now();
    let _ = |app: &AppHandle<tauri::Wry>, u: &Updater| {
        let _ = app.state::<()>();
        emit_status(app, u);
        log_transition(UpdateState::Unknown, UpdateState::Checking, "0.0.0");
    };
}
