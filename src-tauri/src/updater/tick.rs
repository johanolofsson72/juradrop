// Spec 007 / T018 — 4-hour background tick task.
//
// Single tokio-spawned task per app instance. The first sleep is
// `LAUNCH_CHECK_DELAY` (5s) — the launch-time check. Subsequent
// sleeps are `BACKGROUND_INTERVAL` (4h). The task wakes, checks the
// gating predicate, and triggers a fresh check if allowed.
//
// FR-020 + FR-004 — single task, cancellable via the CancellationToken
// stored on the Updater entity.

use std::time::Duration;

use tokio_util::sync::CancellationToken;

pub const LAUNCH_CHECK_DELAY: Duration = Duration::from_secs(5);
pub const BACKGROUND_INTERVAL: Duration = Duration::from_secs(4 * 60 * 60);

/// FR-004 — the gating predicate. The tick triggers a check ONLY when
/// the current state is in this set. In-flight states block the tick
/// to avoid duplicate work or interrupting an active flow.
pub fn is_check_allowed(state: super::state::UpdateState) -> bool {
    use super::state::UpdateState::*;
    matches!(state, Unknown | UpToDate | Failed)
}

/// Single tokio task body. Sleeps `LAUNCH_CHECK_DELAY` first, then
/// loops with `BACKGROUND_INTERVAL`. Cancellation token short-circuits
/// every sleep. The caller (lib.rs setup) spawns this once at app
/// startup and stores the join-handle for shutdown cleanup.
pub async fn run_background_ticker(
    cancel: CancellationToken,
    on_tick: impl Fn() + Send + Sync + 'static,
) {
    // Launch-time check.
    tokio::select! {
        _ = tokio::time::sleep(LAUNCH_CHECK_DELAY) => {},
        _ = cancel.cancelled() => return,
    }
    on_tick();

    // Subsequent 4-hour ticks.
    loop {
        tokio::select! {
            _ = tokio::time::sleep(BACKGROUND_INTERVAL) => {},
            _ = cancel.cancelled() => return,
        }
        on_tick();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    #[test]
    fn is_check_allowed_for_unknown() {
        assert!(is_check_allowed(super::super::state::UpdateState::Unknown));
    }

    #[test]
    fn is_check_allowed_for_up_to_date() {
        assert!(is_check_allowed(super::super::state::UpdateState::UpToDate));
    }

    #[test]
    fn is_check_allowed_for_failed() {
        assert!(is_check_allowed(super::super::state::UpdateState::Failed));
    }

    #[test]
    fn is_check_not_allowed_for_in_flight_states() {
        use super::super::state::UpdateState::*;
        assert!(!is_check_allowed(Checking));
        assert!(!is_check_allowed(Available));
        assert!(!is_check_allowed(Downloading));
        assert!(!is_check_allowed(ReadyToInstall));
        assert!(!is_check_allowed(Restarting));
    }

    #[test]
    fn launch_check_delay_is_5_seconds() {
        assert_eq!(LAUNCH_CHECK_DELAY, Duration::from_secs(5));
    }

    #[test]
    fn background_interval_is_4_hours() {
        assert_eq!(BACKGROUND_INTERVAL, Duration::from_secs(14_400));
    }

    #[tokio::test]
    async fn cancel_token_short_circuits_immediately() {
        let cancel = CancellationToken::new();
        cancel.cancel(); // pre-cancelled

        let calls = Arc::new(AtomicUsize::new(0));
        let calls_clone = Arc::clone(&calls);

        let start = std::time::Instant::now();
        run_background_ticker(cancel, move || {
            calls_clone.fetch_add(1, Ordering::SeqCst);
        })
        .await;

        // Returns within a few ms because the cancel token was already
        // tripped before the first sleep started.
        assert!(start.elapsed() < Duration::from_millis(100));
        // No ticks fired because cancel won the race.
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }
}
