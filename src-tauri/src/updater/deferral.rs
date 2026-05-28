// Spec 007 / T017 — per-zone-busy predicate + deferred-restart logic.

use std::sync::Arc;

use tauri::{AppHandle, Runtime};

use crate::sidecar::commands::AppState;
use crate::updater::commands::{emit_status, log_transition};
use crate::updater::lifecycle;
use crate::updater::state::UpdateState;
use crate::zones::sammanfatta::DropZone;
use crate::zones::ZoneState;

/// FR-017 — the deferral predicate used by `confirm_restart_install`
/// and the fire-on-idle path. True iff ANY zone in `zones` is in
/// `Processing`. Other zone states (idle, dragover, success, error)
/// do NOT block restart (per spec 007 clarification 2).
pub fn any_zone_processing(zones: &[Arc<DropZone>]) -> bool {
    zones
        .iter()
        .any(|z| matches!(z.visible_state(), ZoneState::Processing))
}

/// GAP-A / TLA+ liveness finding — `DeferredRestartAutoFires` actuator.
/// Called from the zone-state-change listener wired in `lib.rs`. When
/// the user has previously parked consent (clicked "Starta om" while
/// a zone was busy) AND all zones are now idle, transition
/// `ReadyToInstall → Restarting` and invoke the plugin install.
///
/// The function is idempotent: it short-circuits if the consent flag
/// isn't set OR if any zone is still processing OR if the state has
/// drifted out of `ReadyToInstall` (e.g. the consent was cancelled).
pub fn try_fire_deferred_restart<R: Runtime>(
    app: &AppHandle<R>,
    state: &AppState,
) -> Option<Vec<u8>> {
    let zones: Vec<Arc<DropZone>> = state.zones.values().cloned().collect();
    if any_zone_processing(&zones) {
        return None;
    }

    let mut u = state.updater.write();
    if u.state != UpdateState::ReadyToInstall || !u.pending_restart_consent {
        return None;
    }
    let old = u.state;
    if !lifecycle::enter_restarting(&mut u) {
        return None;
    }
    log_transition(
        old,
        u.state,
        u.latest_known_version
            .as_deref()
            .unwrap_or(&u.current_version),
    );
    emit_status(app, &u);
    u.downloaded_bytes.take()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::zones::ZoneId;

    #[test]
    fn no_zones_means_no_processing() {
        let zones: Vec<Arc<DropZone>> = Vec::new();
        assert!(!any_zone_processing(&zones));
    }

    #[test]
    fn all_idle_zones_means_no_processing() {
        // Newly-constructed zones are in the Idle state (Default impl).
        let zones: Vec<Arc<DropZone>> = ZoneId::ALL.iter().map(|&id| DropZone::new(id)).collect();
        assert!(!any_zone_processing(&zones));
    }
}
