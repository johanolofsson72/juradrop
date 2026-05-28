// Spec 007 / T014–T016 + T024 — pure state-machine driving helpers.
//
// These functions are I/O-free: they take a `&mut Updater` and a plugin
// outcome, apply the legal transition, set the right fields, and clear
// the right ephemeral data. The Tauri commands call them after invoking
// `tauri_plugin_updater`. The end-to-end integration test in
// `tests/update_lifecycle.rs` calls them directly with synthetic plugin
// outcomes — so the state machine + UpdateStatus payload contract is
// exercised without going through real minisign / wiremock signing.

use chrono::Local;

use super::errors::UpdateFailure;
use super::state::{UpdateState, Updater};

/// Plugin-agnostic value object describing an available update. The
/// production `tauri_plugin_updater::Update` type carries more fields
/// (signature, body, content length); we lift out only the ones the
/// React surface needs to render.
#[derive(Clone, Debug)]
pub struct RemoteUpdate {
    pub version: String,
    pub notes: String,
    pub download_url: String,
}

/// Move `Unknown | UpToDate | Failed → Checking`. No-op on every other
/// state. Returns true iff a transition happened.
pub fn enter_checking(u: &mut Updater) -> bool {
    u.transition(UpdateState::Checking).is_some()
}

/// Plugin returned `Some(update)`. Stamp the remote-version fields and
/// move `Checking → Available`. Caller must guarantee current state is
/// `Checking` (commands enforce this via `enter_checking` first).
pub fn record_available(u: &mut Updater, remote: RemoteUpdate) -> bool {
    u.latest_known_version = Some(remote.version);
    u.release_notes = Some(remote.notes);
    u.download_url = Some(remote.download_url);
    u.last_checked_at = Some(Local::now());
    u.indicator_dismissed = false;
    u.transition(UpdateState::Available).is_some()
}

/// Plugin returned `None` — we're already on the latest version. Move
/// `Checking → UpToDate`.
pub fn record_up_to_date(u: &mut Updater) -> bool {
    u.last_checked_at = Some(Local::now());
    u.latest_known_version = None;
    u.release_notes = None;
    u.download_url = None;
    u.transition(UpdateState::UpToDate).is_some()
}

/// Plugin or pipeline error. Stamp the failure + timestamp and move to
/// `Failed`. Caller's responsibility to map the underlying plugin error
/// to a `UpdateFailure` variant via `UpdateFailure::from_plugin_error`.
pub fn record_failure(u: &mut Updater, failure: UpdateFailure) -> bool {
    u.last_failure = Some(failure);
    u.last_failure_at = Some(Local::now());
    u.transition(UpdateState::Failed).is_some()
}

/// Begin downloading. Caller must guarantee current state is
/// `Available`. Resets the progress counters via `Updater::transition`.
pub fn enter_downloading(u: &mut Updater) -> bool {
    u.transition(UpdateState::Downloading).is_some()
}

/// FR-007 — debounce-aware progress recorder. Stores the new pct and
/// returns `true` iff the integer percent changed since the last emit
/// (the command layer only emits a Tauri event when this returns true).
pub fn record_download_progress(u: &mut Updater, pct: u8) -> bool {
    let pct = pct.min(100);
    if pct == u.last_emitted_pct {
        u.progress_pct = pct;
        return false;
    }
    u.progress_pct = pct;
    u.last_emitted_pct = pct;
    true
}

/// Downloading completed successfully. Store the verified bytes and
/// transition `Downloading → ReadyToInstall`. Caller guarantees the
/// signature has already been verified by the plugin.
pub fn record_ready_to_install(u: &mut Updater, bytes: Vec<u8>) -> bool {
    u.downloaded_bytes = Some(bytes);
    u.progress_pct = 100;
    u.last_emitted_pct = 100;
    // FR-018 — transitioning into ReadyToInstall is a fresh user-facing
    // event (the badge text changes from "Hämtar…" to "Klar att…"); any
    // stale dismissal from the prior Available banner must be cleared.
    u.indicator_dismissed = false;
    u.transition(UpdateState::ReadyToInstall).is_some()
}

/// User confirmed (and no zone is busy). Move
/// `ReadyToInstall → Restarting`. The actual `update.install(...)` call
/// happens in the command layer immediately after this; that call exits
/// the process so no further transitions fire.
pub fn enter_restarting(u: &mut Updater) -> bool {
    u.transition(UpdateState::Restarting).is_some()
}

/// User confirmed but a zone is busy. Park consent for the fire-on-idle
/// handler in `deferral.rs`. Does NOT transition state — we remain in
/// `ReadyToInstall` with `pending_restart_consent = true`.
pub fn defer_restart_until_idle(u: &mut Updater) {
    u.pending_restart_consent = true;
}

/// User clicked "Avbryt" on the deferred-restart banner. Clear consent;
/// stay in `ReadyToInstall`.
pub fn cancel_deferred_consent(u: &mut Updater) {
    u.pending_restart_consent = false;
}

/// User dismissed the indicator via the chevron. Stay in the current
/// state; just flip the visibility flag.
pub fn dismiss_indicator(u: &mut Updater) {
    u.indicator_dismissed = true;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enter_checking_from_unknown_transitions() {
        let mut u = Updater::new();
        assert!(enter_checking(&mut u));
        assert_eq!(u.state, UpdateState::Checking);
    }

    #[test]
    fn enter_checking_from_available_is_a_no_op() {
        let mut u = Updater::new();
        u.state = UpdateState::Available;
        assert!(!enter_checking(&mut u));
        assert_eq!(u.state, UpdateState::Available);
    }

    #[test]
    fn record_available_stamps_version_notes_and_url() {
        let mut u = Updater::new();
        u.state = UpdateState::Checking;
        record_available(
            &mut u,
            RemoteUpdate {
                version: "0.2.0".into(),
                notes: "Bättre PDF-stöd".into(),
                download_url: "https://example/dmg".into(),
            },
        );
        assert_eq!(u.state, UpdateState::Available);
        assert_eq!(u.latest_known_version.as_deref(), Some("0.2.0"));
        assert_eq!(u.release_notes.as_deref(), Some("Bättre PDF-stöd"));
        assert_eq!(u.download_url.as_deref(), Some("https://example/dmg"));
        assert!(u.last_checked_at.is_some());
    }

    #[test]
    fn record_up_to_date_clears_stale_version_fields() {
        let mut u = Updater::new();
        u.state = UpdateState::Checking;
        u.latest_known_version = Some("0.2.0".into());
        u.release_notes = Some("stale".into());
        u.download_url = Some("stale".into());
        record_up_to_date(&mut u);
        assert_eq!(u.state, UpdateState::UpToDate);
        assert!(u.latest_known_version.is_none());
        assert!(u.release_notes.is_none());
        assert!(u.download_url.is_none());
    }

    #[test]
    fn record_failure_from_checking_stamps_failure_and_transitions() {
        let mut u = Updater::new();
        u.state = UpdateState::Checking;
        assert!(record_failure(&mut u, UpdateFailure::NoNetwork));
        assert_eq!(u.state, UpdateState::Failed);
        assert_eq!(u.last_failure, Some(UpdateFailure::NoNetwork));
        assert!(u.last_failure_at.is_some());
    }

    #[test]
    fn record_failure_from_downloading_clears_progress() {
        let mut u = Updater::new();
        u.state = UpdateState::Downloading;
        u.progress_pct = 73;
        record_failure(&mut u, UpdateFailure::DownloadInterrupted);
        assert_eq!(u.state, UpdateState::Failed);
        assert!(u.downloaded_bytes.is_none());
    }

    #[test]
    fn record_download_progress_debounces_repeats() {
        let mut u = Updater::new();
        u.state = UpdateState::Downloading;
        assert!(record_download_progress(&mut u, 5));
        assert!(!record_download_progress(&mut u, 5)); // same pct: no emit
        assert!(record_download_progress(&mut u, 6));
        assert_eq!(u.progress_pct, 6);
        assert_eq!(u.last_emitted_pct, 6);
    }

    #[test]
    fn record_ready_to_install_stores_bytes_and_transitions() {
        let mut u = Updater::new();
        u.state = UpdateState::Downloading;
        record_ready_to_install(&mut u, vec![1, 2, 3, 4]);
        assert_eq!(u.state, UpdateState::ReadyToInstall);
        assert_eq!(u.downloaded_bytes.as_deref(), Some(&[1, 2, 3, 4][..]));
        assert_eq!(u.progress_pct, 100);
    }

    #[test]
    fn enter_restarting_from_ready_to_install() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        u.downloaded_bytes = Some(vec![0, 1]);
        assert!(enter_restarting(&mut u));
        assert_eq!(u.state, UpdateState::Restarting);
        // T003 invariant — bytes kept across the boundary because the
        // install call needs them right after the transition.
        assert!(u.downloaded_bytes.is_some());
    }

    #[test]
    fn defer_restart_until_idle_does_not_transition() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        defer_restart_until_idle(&mut u);
        assert_eq!(u.state, UpdateState::ReadyToInstall);
        assert!(u.pending_restart_consent);
    }

    #[test]
    fn cancel_deferred_consent_clears_flag_only() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        u.pending_restart_consent = true;
        cancel_deferred_consent(&mut u);
        assert_eq!(u.state, UpdateState::ReadyToInstall);
        assert!(!u.pending_restart_consent);
    }

    #[test]
    fn dismiss_indicator_only_flips_flag() {
        let mut u = Updater::new();
        u.state = UpdateState::Available;
        dismiss_indicator(&mut u);
        assert_eq!(u.state, UpdateState::Available);
        assert!(u.indicator_dismissed);
    }

    #[test]
    fn record_available_clears_indicator_dismissed_on_fresh_arrival() {
        let mut u = Updater::new();
        u.state = UpdateState::Checking;
        u.indicator_dismissed = true; // user previously dismissed an older Available
        record_available(
            &mut u,
            RemoteUpdate {
                version: "0.3.0".into(),
                notes: "".into(),
                download_url: "https://example/dmg".into(),
            },
        );
        // Fresh Available means the badge MUST re-appear, even if the
        // user dismissed the previous one — per contract on
        // `dismiss_update_indicator`.
        assert!(!u.indicator_dismissed);
    }
}
