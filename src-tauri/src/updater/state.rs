// Spec 007 / T003 — UpdateState enum + Updater struct.
//
// Eight-variant state machine owned in Rust; mirrored to React via the
// `juradrop://update-status` event. The transition graph + invariants
// are codified in specs/007-auto-updater/spec.allium.

use std::sync::Arc;

use chrono::{DateTime, Local};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;

use super::errors::UpdateFailure;

/// FR-002 — the eight-variant update lifecycle. Source of truth in
/// Rust. The transition graph is enforced by `Updater::transitions`.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateState {
    #[default]
    Unknown,
    Checking,
    UpToDate,
    Available,
    Downloading,
    ReadyToInstall,
    Restarting,
    Failed,
}

pub struct Updater {
    pub state: UpdateState,
    pub current_version: String,
    pub latest_known_version: Option<String>,
    pub release_notes: Option<String>,
    pub download_url: Option<String>,
    pub progress_pct: u8,
    pub last_emitted_pct: u8,
    pub pending_restart_consent: bool,
    pub indicator_dismissed: bool,
    pub last_checked_at: Option<DateTime<Local>>,
    pub last_failure: Option<UpdateFailure>,
    pub last_failure_at: Option<DateTime<Local>>,
    pub downloaded_bytes: Option<Vec<u8>>,
    pub cancel_token: CancellationToken,
}

impl Updater {
    pub fn new() -> Self {
        Self {
            state: UpdateState::Unknown,
            current_version: env!("CARGO_PKG_VERSION").to_string(),
            latest_known_version: None,
            release_notes: None,
            download_url: None,
            progress_pct: 0,
            last_emitted_pct: 0,
            pending_restart_consent: false,
            indicator_dismissed: false,
            last_checked_at: None,
            last_failure: None,
            last_failure_at: None,
            downloaded_bytes: None,
            cancel_token: CancellationToken::new(),
        }
    }

    /// Test whether a transition from the current state to `new_state`
    /// is legal per the transition graph in spec.allium. Returns
    /// `false` for illegal transitions; the caller MUST refuse them
    /// without mutating state.
    pub fn can_transition(&self, new_state: UpdateState) -> bool {
        use UpdateState::*;
        matches!(
            (self.state, new_state),
            (Unknown, Checking)
                | (UpToDate, Checking)
                | (Failed, Checking)
                | (Checking, UpToDate)
                | (Checking, Available)
                | (Checking, Failed)
                | (Available, Downloading)
                | (Available, Failed)
                | (Downloading, ReadyToInstall)
                | (Downloading, Failed)
                | (ReadyToInstall, Restarting)
                | (ReadyToInstall, Failed)
                // Spec 007 / GAP-B — InstallFailedTransition (spec.allium:349).
                // The plugin's `install(bytes)` normally exits the process; if
                // it returns `Err` (e.g. disk full, signed-but-corrupted DMG),
                // the defensive fallback in `confirm_restart_install` records
                // an InstallFailed failure and we transition Restarting → Failed
                // so the user can retry rather than sitting on "Startar om…".
                | (Restarting, Failed)
        )
    }

    /// Mutate the state if the transition is legal; clear ephemeral
    /// fields on every transition out of their owning state.
    ///
    /// Returns `Some(old_state)` on a legal transition, `None` on an
    /// illegal one (caller can log/skip).
    pub fn transition(&mut self, new_state: UpdateState) -> Option<UpdateState> {
        if !self.can_transition(new_state) {
            return None;
        }
        let old = self.state;

        // Clear fields whose meaning is tied to specific states.
        if old == UpdateState::ReadyToInstall && new_state != UpdateState::ReadyToInstall {
            self.pending_restart_consent = false;
        }
        if !matches!(
            new_state,
            UpdateState::ReadyToInstall | UpdateState::Restarting
        ) {
            self.downloaded_bytes = None;
        }
        if new_state == UpdateState::Downloading {
            self.progress_pct = 0;
            self.last_emitted_pct = 0;
        }

        self.state = new_state;
        Some(old)
    }
}

impl Default for Updater {
    fn default() -> Self {
        Self::new()
    }
}

pub type SharedUpdater = Arc<RwLock<Updater>>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_to_checking_is_legal() {
        let u = Updater::new();
        assert!(u.can_transition(UpdateState::Checking));
    }

    #[test]
    fn checking_to_restarting_is_illegal() {
        let mut u = Updater::new();
        u.state = UpdateState::Checking;
        assert!(!u.can_transition(UpdateState::Restarting));
    }

    #[test]
    fn ready_to_install_to_restarting_is_legal() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        assert!(u.can_transition(UpdateState::Restarting));
    }

    #[test]
    fn consent_flag_cleared_on_transition_out_of_ready_to_install() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        u.pending_restart_consent = true;
        u.transition(UpdateState::Restarting);
        assert!(!u.pending_restart_consent);
    }

    #[test]
    fn downloaded_bytes_kept_when_transitioning_to_restarting() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        u.downloaded_bytes = Some(vec![1, 2, 3]);
        u.transition(UpdateState::Restarting);
        // Restarting consumes the bytes in `install()`; we keep them
        // in the entity until that point so the install path has
        // access. Cleared by transitioning back to Failed (next test).
        assert!(u.downloaded_bytes.is_some());
    }

    #[test]
    fn downloaded_bytes_cleared_on_transition_to_failed() {
        let mut u = Updater::new();
        u.state = UpdateState::Downloading;
        u.downloaded_bytes = Some(vec![1, 2, 3]);
        u.transition(UpdateState::Failed);
        assert!(u.downloaded_bytes.is_none());
    }

    #[test]
    fn illegal_transition_returns_none_and_does_not_mutate() {
        let mut u = Updater::new();
        u.state = UpdateState::Checking;
        let result = u.transition(UpdateState::Restarting);
        assert!(result.is_none());
        assert_eq!(u.state, UpdateState::Checking);
    }

    #[test]
    fn restarting_to_failed_is_legal_for_install_error_recovery() {
        // GAP-B / TLA+ finding — without this edge, a failed
        // `update.install()` leaves the badge stuck on "Startar om…"
        // because record_failure silently no-ops.
        let mut u = Updater::new();
        u.state = UpdateState::Restarting;
        assert!(u.can_transition(UpdateState::Failed));
        let result = u.transition(UpdateState::Failed);
        assert_eq!(result, Some(UpdateState::Restarting));
        assert_eq!(u.state, UpdateState::Failed);
    }

    #[test]
    fn progress_pct_resets_on_entering_downloading() {
        let mut u = Updater::new();
        u.state = UpdateState::Available;
        u.progress_pct = 50;
        u.last_emitted_pct = 50;
        u.transition(UpdateState::Downloading);
        assert_eq!(u.progress_pct, 0);
        assert_eq!(u.last_emitted_pct, 0);
    }

    #[test]
    fn current_version_pulled_from_cargo_pkg() {
        let u = Updater::new();
        // env! resolves at compile time; we just check it's non-empty.
        assert!(!u.current_version.is_empty());
    }
}
