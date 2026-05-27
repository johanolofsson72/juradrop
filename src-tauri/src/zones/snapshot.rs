// Spec 003 / T006 — ZoneState, JobOutcome, ZoneSnapshot wire types.
//
// `ZoneSnapshot` is the payload emitted on `juradrop://sammanfatta` per
// `specs/003-first-zone-sammanfatta/contracts/tauri-events.md`. The React
// layer (`src/lib/status-store.ts`) holds the latest snapshot in its
// zustand store.

use serde::{Deserialize, Serialize};

use super::errors::ZoneFailure;

/// Visible state of the drop zone. Transitions follow the Allium
/// `transitions visible_state` block (idle → dragover → processing →
/// success | error → idle).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ZoneState {
    Idle,
    Dragover,
    Processing,
    Success,
    Error,
}

impl ZoneState {
    pub fn is_terminal(self) -> bool {
        matches!(self, ZoneState::Success | ZoneState::Error)
    }
}

/// Outcome of a `DropJob`. The Allium `transitions outcome` graph
/// permits `in_flight -> {success, failure, cancelled}`; terminal
/// states never transition back to `in_flight`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JobOutcome {
    InFlight,
    Success,
    Failure,
    Cancelled,
}

impl JobOutcome {
    pub fn is_terminal(self) -> bool {
        !matches!(self, JobOutcome::InFlight)
    }
}

/// Payload emitted to the WebView on every visible state transition.
/// `failure` is set iff `state == Error`. `progress_hint` carries the
/// pre-defined Swedish phrase for the current state — never document
/// content (Principle I privacy boundary).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZoneSnapshot {
    pub state: ZoneState,
    pub disabled: bool,
    pub failure: Option<ZoneFailure>,
    pub job_id: Option<String>, // uuid::Uuid stringified; TS treats as opaque string
    pub progress_hint: Option<String>,
}

impl ZoneSnapshot {
    /// Convenience constructor for the initial-load idle state.
    pub fn idle(disabled: bool) -> Self {
        Self {
            state: ZoneState::Idle,
            disabled,
            failure: None,
            job_id: None,
            progress_hint: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zone_state_serializes_as_snake_case() {
        assert_eq!(
            serde_json::to_string(&ZoneState::Dragover).unwrap(),
            "\"dragover\""
        );
        assert_eq!(
            serde_json::to_string(&ZoneState::Processing).unwrap(),
            "\"processing\""
        );
    }

    #[test]
    fn job_outcome_in_flight_is_not_terminal() {
        assert!(!JobOutcome::InFlight.is_terminal());
        assert!(JobOutcome::Success.is_terminal());
        assert!(JobOutcome::Failure.is_terminal());
        assert!(JobOutcome::Cancelled.is_terminal());
    }

    #[test]
    fn idle_snapshot_has_no_job_or_failure() {
        let s = ZoneSnapshot::idle(false);
        assert!(matches!(s.state, ZoneState::Idle));
        assert!(s.failure.is_none());
        assert!(s.job_id.is_none());
        assert!(s.progress_hint.is_none());
    }

    #[test]
    fn snapshot_round_trips_through_json() {
        let snap = ZoneSnapshot {
            state: ZoneState::Error,
            disabled: false,
            failure: Some(ZoneFailure::ParseError),
            job_id: Some("test-uuid".to_string()),
            progress_hint: None,
        };
        let json = serde_json::to_string(&snap).unwrap();
        let back: ZoneSnapshot = serde_json::from_str(&json).unwrap();
        assert!(matches!(back.state, ZoneState::Error));
        assert_eq!(back.failure, Some(ZoneFailure::ParseError));
        assert_eq!(back.job_id, Some("test-uuid".to_string()));
    }
}
