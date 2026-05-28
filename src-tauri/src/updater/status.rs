// Spec 007 / T005 — UpdateStatus mirrored value.
//
// Tagged union emitted on the `juradrop://update-status` Tauri event.
// The TS consumer (src/lib/update-store.ts) pattern-matches on `state`.

use serde::{Deserialize, Serialize};

use super::errors::UpdateFailure;
use super::state::{UpdateState, Updater};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum UpdateStatus {
    Unknown,
    Checking,
    UpToDate {
        version: String,
        checked_at: String,
    },
    Available {
        version: String,
        notes: String,
        download_url: String,
        /// FR-018 — if the user dismissed the indicator, the React layer
        /// must hide the badge without losing the state itself. A fresh
        /// transition into `Available` (record_available) clears the flag.
        dismissed: bool,
    },
    Downloading {
        version: String,
        progress_pct: u8,
    },
    ReadyToInstall {
        version: String,
        deferred: bool,
        /// FR-018 — same dismissal contract as `Available`.
        dismissed: bool,
    },
    Restarting {
        version: String,
    },
    Failed {
        failure: UpdateFailure,
        message: String,
        checked_at: String,
    },
}

impl UpdateStatus {
    pub fn from_updater(u: &Updater) -> Self {
        match u.state {
            UpdateState::Unknown => Self::Unknown,
            UpdateState::Checking => Self::Checking,
            UpdateState::UpToDate => Self::UpToDate {
                version: u.current_version.clone(),
                checked_at: u
                    .last_checked_at
                    .as_ref()
                    .map(|t| t.to_rfc3339())
                    .unwrap_or_default(),
            },
            UpdateState::Available => Self::Available {
                version: u.latest_known_version.clone().unwrap_or_default(),
                notes: u.release_notes.clone().unwrap_or_default(),
                download_url: u.download_url.clone().unwrap_or_default(),
                dismissed: u.indicator_dismissed,
            },
            UpdateState::Downloading => Self::Downloading {
                version: u.latest_known_version.clone().unwrap_or_default(),
                progress_pct: u.progress_pct,
            },
            UpdateState::ReadyToInstall => Self::ReadyToInstall {
                version: u.latest_known_version.clone().unwrap_or_default(),
                deferred: u.pending_restart_consent,
                dismissed: u.indicator_dismissed,
            },
            UpdateState::Restarting => Self::Restarting {
                version: u.latest_known_version.clone().unwrap_or_default(),
            },
            UpdateState::Failed => {
                let failure = u.last_failure.unwrap_or(UpdateFailure::ManifestMalformed);
                Self::Failed {
                    failure,
                    message: failure.to_string(),
                    checked_at: u
                        .last_failure_at
                        .as_ref()
                        .map(|t| t.to_rfc3339())
                        .unwrap_or_default(),
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_state_produces_unknown_variant() {
        let u = Updater::new();
        assert!(matches!(
            UpdateStatus::from_updater(&u),
            UpdateStatus::Unknown
        ));
    }

    #[test]
    fn available_state_carries_version_notes_download_url() {
        let mut u = Updater::new();
        u.state = UpdateState::Available;
        u.latest_known_version = Some("0.2.0".into());
        u.release_notes = Some("Test notes".into());
        u.download_url = Some("https://example.com/dmg".into());
        match UpdateStatus::from_updater(&u) {
            UpdateStatus::Available {
                version,
                notes,
                download_url,
                dismissed,
            } => {
                assert_eq!(version, "0.2.0");
                assert_eq!(notes, "Test notes");
                assert_eq!(download_url, "https://example.com/dmg");
                assert!(!dismissed);
            }
            other => panic!("expected Available, got {other:?}"),
        }
    }

    #[test]
    fn available_state_carries_dismissed_flag_when_user_dismissed() {
        let mut u = Updater::new();
        u.state = UpdateState::Available;
        u.latest_known_version = Some("0.2.0".into());
        u.indicator_dismissed = true;
        match UpdateStatus::from_updater(&u) {
            UpdateStatus::Available { dismissed, .. } => assert!(dismissed),
            other => panic!("expected Available, got {other:?}"),
        }
    }

    #[test]
    fn downloading_state_carries_progress() {
        let mut u = Updater::new();
        u.state = UpdateState::Downloading;
        u.latest_known_version = Some("0.2.0".into());
        u.progress_pct = 73;
        match UpdateStatus::from_updater(&u) {
            UpdateStatus::Downloading { progress_pct, .. } => assert_eq!(progress_pct, 73),
            other => panic!("expected Downloading, got {other:?}"),
        }
    }

    #[test]
    fn ready_to_install_carries_deferred_flag() {
        let mut u = Updater::new();
        u.state = UpdateState::ReadyToInstall;
        u.latest_known_version = Some("0.2.0".into());
        u.pending_restart_consent = true;
        match UpdateStatus::from_updater(&u) {
            UpdateStatus::ReadyToInstall {
                deferred,
                dismissed,
                ..
            } => {
                assert!(deferred);
                assert!(!dismissed);
            }
            other => panic!("expected ReadyToInstall deferred, got {other:?}"),
        }
    }

    #[test]
    fn failed_state_carries_swedish_message() {
        let mut u = Updater::new();
        u.state = UpdateState::Failed;
        u.last_failure = Some(UpdateFailure::NoNetwork);
        u.last_failure_at = Some(chrono::Local::now());
        match UpdateStatus::from_updater(&u) {
            UpdateStatus::Failed {
                failure, message, ..
            } => {
                assert_eq!(failure, UpdateFailure::NoNetwork);
                assert!(message.contains("GitHub"));
            }
            other => panic!("expected Failed, got {other:?}"),
        }
    }

    #[test]
    fn serialization_uses_state_tag() {
        let s = UpdateStatus::Checking;
        let json = serde_json::to_string(&s).unwrap();
        assert_eq!(json, r#"{"state":"checking"}"#);
    }
}
