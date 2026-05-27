// Spec 007 / T017 — per-zone-busy predicate + deferred-restart logic.

use std::sync::Arc;

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
        let zones: Vec<Arc<DropZone>> = ZoneId::ALL.iter().map(|&id| DropZone::new(id)).collect();
        // Newly-constructed zones are in the Idle state (Default impl).
        assert!(!any_zone_processing(&zones));
    }
}
