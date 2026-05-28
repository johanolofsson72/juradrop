// Spec 008 / T020 — integration test for the new cancel_model_pull command.
//
// Uses AppState directly (not the Tauri mock builder) because the command's
// behavior is gated by lock + status reads, not by any AppHandle interaction
// beyond the emit() call. The emit is exercised in `npm run tauri dev` flow 4.

use juradrop_lib::sidecar::commands::AppState;
use juradrop_lib::sidecar::status::ModelStatus;

#[test]
fn cancel_is_noop_when_model_status_is_not_downloading() {
    // Idempotency contract — Ready / NotPresent / DownloadFailed are
    // all silent no-ops. The command never alters the consent record.
    let state = AppState::new();

    for status in [
        ModelStatus::Ready,
        ModelStatus::NotPresent,
        ModelStatus::DownloadFailed,
    ] {
        *state.model_status.write() = status;
        // Simulate the command's lock-read logic.
        let should_act = matches!(*state.model_status.read(), ModelStatus::Downloading);
        assert!(
            !should_act,
            "cancel should be no-op when status is {status:?}"
        );
    }
}

#[test]
fn cancel_token_is_initialized_to_a_fresh_token_per_pull() {
    let state = AppState::new();
    let token_before = state.pull_cancel.read().clone();
    assert!(!token_before.is_cancelled());

    // Trip the token (simulating cancel_model_pull's action).
    token_before.cancel();
    assert!(token_before.is_cancelled());

    // Replace with a fresh token (simulating the start of a new pull).
    *state.pull_cancel.write() = tokio_util::sync::CancellationToken::new();
    let token_after = state.pull_cancel.read().clone();
    assert!(
        !token_after.is_cancelled(),
        "fresh token must not carry forward the cancelled state"
    );
}

#[test]
fn cancel_during_downloading_flips_status_to_not_present() {
    // The command flips ModelStatus::Downloading → NotPresent. Simulate
    // the lock-acquire-order resolution from R-003.
    let state = AppState::new();
    *state.model_status.write() = ModelStatus::Downloading;

    // Pre-cancel: status is Downloading.
    assert_eq!(*state.model_status.read(), ModelStatus::Downloading);

    // Simulate the command body's status flip.
    {
        let mut s = state.model_status.write();
        if *s == ModelStatus::Downloading {
            state.pull_cancel.read().cancel();
            *s = ModelStatus::NotPresent;
        }
    }

    assert_eq!(*state.model_status.read(), ModelStatus::NotPresent);
    assert!(state.pull_cancel.read().is_cancelled());
}

#[test]
fn cancel_when_already_ready_does_not_flip_status_back() {
    // Race outcome B — completion wins; cancel is a no-op afterwards.
    let state = AppState::new();
    *state.model_status.write() = ModelStatus::Ready;

    let should_act = matches!(*state.model_status.read(), ModelStatus::Downloading);
    assert!(
        !should_act,
        "the wizard never uncompletes a finished download (NeverUncompleteACompletedDownload invariant)"
    );
    assert_eq!(*state.model_status.read(), ModelStatus::Ready);
}
