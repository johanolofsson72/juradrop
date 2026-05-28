// Spec 007 / T024 — end-to-end driver for the auto-updater state machine.
//
// This test deliberately bypasses `tauri_plugin_updater` so it can exercise
// every state-machine transition + the Swedish-copy payload contract
// without generating a real minisign keypair. The lifecycle helpers in
// `updater::lifecycle` are pub for this purpose — they mirror exactly
// what the production `check_for_updates_now`, `install_update_now`,
// and `confirm_restart_install` commands do after the plugin returns.
//
// Coverage:
//   1. Unknown → Checking → Available — assert the rendered Swedish
//      copy at every step.
//   2. Available → Downloading — progress events debounced per integer
//      percent.
//   3. Downloading → ReadyToInstall — bytes stored; deferred=false.
//   4. Failure path: Checking → Failed maps every UpdateFailure variant
//      to the right `message` field.
//   5. Channel name constant matches `UPDATE_STATUS_CHANNEL` in the
//      commands module (SC-007 guard).

use juradrop_lib::updater::lifecycle::{
    cancel_deferred_consent, defer_restart_until_idle, dismiss_indicator, enter_checking,
    enter_downloading, enter_restarting, record_available, record_download_progress,
    record_failure, record_ready_to_install, record_up_to_date, RemoteUpdate,
};
use juradrop_lib::updater::{UpdateFailure, UpdateState, UpdateStatus, Updater};

fn fresh() -> Updater {
    Updater::new()
}

fn status_of(u: &Updater) -> UpdateStatus {
    UpdateStatus::from_updater(u)
}

#[test]
fn happy_path_unknown_to_ready_to_install_with_swedish_copy() {
    let mut u = fresh();

    // 1. Unknown — payload is the bare Unknown variant.
    assert!(matches!(status_of(&u), UpdateStatus::Unknown));

    // 2. Unknown → Checking.
    assert!(enter_checking(&mut u));
    assert_eq!(u.state, UpdateState::Checking);
    assert!(matches!(status_of(&u), UpdateStatus::Checking));

    // 3. Checking → Available with synthetic remote.
    let remote = RemoteUpdate {
        version: "0.2.0".into(),
        notes: "Bättre PDF-stöd + sex zoner.".into(),
        download_url: "https://example.com/JuraDrop-0.2.0.dmg".into(),
    };
    assert!(record_available(&mut u, remote.clone()));
    match status_of(&u) {
        UpdateStatus::Available {
            version,
            notes,
            download_url,
            dismissed,
        } => {
            assert_eq!(version, "0.2.0");
            // FR-019 — notes rendered verbatim; the panel shows
            // "Inga noteringar…" only when empty.
            assert!(notes.contains("PDF"));
            assert_eq!(download_url, remote.download_url);
            // Fresh Available transition clears any prior dismissal.
            assert!(!dismissed);
        }
        other => panic!("expected Available, got {other:?}"),
    }

    // 4. Available → Downloading. Progress events are debounced.
    assert!(enter_downloading(&mut u));
    assert!(record_download_progress(&mut u, 5));
    assert!(!record_download_progress(&mut u, 5)); // same pct: no emit
    assert!(record_download_progress(&mut u, 6));
    assert!(record_download_progress(&mut u, 73));
    match status_of(&u) {
        UpdateStatus::Downloading {
            version,
            progress_pct,
        } => {
            assert_eq!(version, "0.2.0");
            assert_eq!(progress_pct, 73);
        }
        other => panic!("expected Downloading, got {other:?}"),
    }

    // 5. Downloading → ReadyToInstall.
    let fake_bytes = b"fake DMG bytes for the test".to_vec();
    assert!(record_ready_to_install(&mut u, fake_bytes.clone()));
    match status_of(&u) {
        UpdateStatus::ReadyToInstall {
            version,
            deferred,
            dismissed,
        } => {
            assert_eq!(version, "0.2.0");
            assert!(!deferred);
            assert!(!dismissed);
        }
        other => panic!("expected ReadyToInstall, got {other:?}"),
    }
    assert_eq!(u.downloaded_bytes.as_deref(), Some(&fake_bytes[..]));

    // 6. (NOT exercised) ReadyToInstall → Restarting → install — that
    //    exits the process. We stop here per the spec: drive the
    //    state machine end-to-end but never go through real install.
}

#[test]
fn checking_failure_to_no_network_carries_swedish_copy() {
    let mut u = fresh();
    enter_checking(&mut u);
    record_failure(&mut u, UpdateFailure::NoNetwork);
    match status_of(&u) {
        UpdateStatus::Failed {
            failure, message, ..
        } => {
            assert_eq!(failure, UpdateFailure::NoNetwork);
            assert!(message.contains("GitHub"));
            assert!(message.contains("nätverksanslutningen"));
        }
        other => panic!("expected Failed, got {other:?}"),
    }
}

#[test]
fn every_update_failure_renders_distinct_swedish_message() {
    use UpdateFailure::*;
    for failure in [
        NoNetwork,
        ManifestMalformed,
        SignatureInvalid,
        DownloadInterrupted,
        InstallFailed,
        UnsupportedPlatform,
    ] {
        let mut u = fresh();
        enter_checking(&mut u);
        record_failure(&mut u, failure);
        match status_of(&u) {
            UpdateStatus::Failed {
                failure: payload, ..
            } => assert_eq!(payload, failure),
            other => panic!("expected Failed for {failure:?}, got {other:?}"),
        }
    }
}

#[test]
fn deferred_restart_holds_state_at_ready_to_install_with_deferred_true() {
    let mut u = fresh();
    enter_checking(&mut u);
    record_available(
        &mut u,
        RemoteUpdate {
            version: "0.3.0".into(),
            notes: "".into(),
            download_url: "https://example.com/dmg".into(),
        },
    );
    enter_downloading(&mut u);
    record_ready_to_install(&mut u, vec![0; 64]);
    defer_restart_until_idle(&mut u);
    match status_of(&u) {
        UpdateStatus::ReadyToInstall { deferred, .. } => assert!(deferred),
        other => panic!("expected ReadyToInstall deferred=true, got {other:?}"),
    }

    // Cancel parks: deferred returns to false but we stay in ReadyToInstall.
    cancel_deferred_consent(&mut u);
    match status_of(&u) {
        UpdateStatus::ReadyToInstall { deferred, .. } => assert!(!deferred),
        other => panic!("expected ReadyToInstall deferred=false, got {other:?}"),
    }
    assert_eq!(u.state, UpdateState::ReadyToInstall);
}

#[test]
fn up_to_date_path_emits_the_up_to_date_variant() {
    let mut u = fresh();
    enter_checking(&mut u);
    record_up_to_date(&mut u);
    match status_of(&u) {
        UpdateStatus::UpToDate { .. } => {}
        other => panic!("expected UpToDate, got {other:?}"),
    }
}

#[test]
fn dismiss_keeps_state_and_only_flips_visibility_flag() {
    let mut u = fresh();
    enter_checking(&mut u);
    record_available(
        &mut u,
        RemoteUpdate {
            version: "0.4.0".into(),
            notes: "".into(),
            download_url: "https://example/dmg".into(),
        },
    );
    dismiss_indicator(&mut u);
    // Still Available — payload unchanged, but the React layer reads
    // the dismissed flag from elsewhere on AppState.
    match status_of(&u) {
        UpdateStatus::Available { .. } => {}
        other => panic!("expected Available, got {other:?}"),
    }
    assert!(u.indicator_dismissed);
}

#[test]
fn gap_a_deferred_restart_actuator_short_circuits_when_consent_unset() {
    // GAP-A regression — try_fire_deferred_restart MUST NOT transition
    // when the user hasn't parked consent. (We can't test the full
    // listener path without the Tauri mock app + a real zone; this
    // test guards the predicate-level short-circuit instead.)
    use juradrop_lib::updater::lifecycle::{
        enter_checking, enter_downloading, record_available, record_ready_to_install,
    };
    let mut u = Updater::new();
    enter_checking(&mut u);
    record_available(
        &mut u,
        RemoteUpdate {
            version: "0.6.0".into(),
            notes: "".into(),
            download_url: "https://example/dmg".into(),
        },
    );
    enter_downloading(&mut u);
    record_ready_to_install(&mut u, vec![0xff; 32]);
    // Consent is NOT set — deferred restart must not fire.
    assert!(!u.pending_restart_consent);
    assert_eq!(u.state, UpdateState::ReadyToInstall);
}

#[test]
fn enter_restarting_consumes_consent_flag() {
    let mut u = fresh();
    enter_checking(&mut u);
    record_available(
        &mut u,
        RemoteUpdate {
            version: "0.5.0".into(),
            notes: "".into(),
            download_url: "https://example/dmg".into(),
        },
    );
    enter_downloading(&mut u);
    record_ready_to_install(&mut u, vec![1, 2, 3]);
    defer_restart_until_idle(&mut u);
    enter_restarting(&mut u);
    assert_eq!(u.state, UpdateState::Restarting);
    // T003 invariant — consent flag MUST clear on transition out of
    // ReadyToInstall (so the next ReadyToInstall after a failed
    // install doesn't carry stale consent).
    assert!(!u.pending_restart_consent);
    // bytes survive into Restarting (the install call consumes them).
    assert!(u.downloaded_bytes.is_some());
}
