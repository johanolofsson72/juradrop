// Spec 003 / T007 — DropJob entity.
//
// One DropJob represents a single in-flight or terminal summarization.
// Per FR-015 single-flight, at most one DropJob is in_flight per zone at
// any time. The `cancel_token` is wired into the dispatch's `tokio::select!`
// so US5's `cancel_summary` command can abort the model call by signalling
// the token.

use std::path::PathBuf;

use chrono::{DateTime, Local};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use super::snapshot::JobOutcome;

#[derive(Debug)]
pub struct DropJob {
    pub id: Uuid,
    pub source_path: PathBuf,
    pub started_at: DateTime<Local>,
    pub outcome: JobOutcome,
    /// Whether the input text was truncated to fit the model's context (FR-019).
    /// Only meaningful when `outcome == Success`.
    pub truncated: bool,
    pub cancel_token: CancellationToken,
    pub finished_at: Option<DateTime<Local>>,
}

impl DropJob {
    /// Construct a fresh job in the `in_flight` state. Caller is responsible
    /// for storing the returned job in the zone's single-flight slot before
    /// kicking off the dispatch pipeline.
    pub fn new(source_path: PathBuf) -> Self {
        Self {
            id: Uuid::new_v4(),
            source_path,
            started_at: Local::now(),
            outcome: JobOutcome::InFlight,
            truncated: false,
            cancel_token: CancellationToken::new(),
            finished_at: None,
        }
    }

    /// Signal cancellation. Idempotent. The dispatch's `tokio::select!`
    /// observes the cancelled token and short-circuits before any sidecar
    /// write happens (per FR-027 + Allium `CancelledLeavesNoSidecar`).
    pub fn cancel(&self) {
        self.cancel_token.cancel();
    }

    /// Transition this job to a terminal outcome and stamp `finished_at`.
    /// Idempotent for the same terminal outcome; rejects re-transition to
    /// a different terminal state (would indicate a logic bug — the
    /// Allium graph permits exactly one terminal transition).
    pub fn complete(&mut self, outcome: JobOutcome) {
        debug_assert!(
            outcome.is_terminal(),
            "DropJob::complete called with non-terminal outcome {outcome:?}"
        );
        if self.outcome.is_terminal() {
            // Idempotent — a late model response after cancel hits this
            // path. Per Allium DiscardLateModelResponseAfterCancel rule.
            return;
        }
        self.outcome = outcome;
        self.finished_at = Some(Local::now());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_job_is_in_flight_with_fresh_uuid() {
        let a = DropJob::new(PathBuf::from("/tmp/a.docx"));
        let b = DropJob::new(PathBuf::from("/tmp/b.docx"));
        assert!(matches!(a.outcome, JobOutcome::InFlight));
        assert!(matches!(b.outcome, JobOutcome::InFlight));
        assert_ne!(a.id, b.id);
        assert!(a.finished_at.is_none());
    }

    #[test]
    fn complete_transitions_to_terminal_and_stamps_time() {
        let mut job = DropJob::new(PathBuf::from("/tmp/x.docx"));
        job.complete(JobOutcome::Success);
        assert!(matches!(job.outcome, JobOutcome::Success));
        assert!(job.finished_at.is_some());
    }

    #[test]
    fn second_complete_after_terminal_is_no_op_not_overwrite() {
        // Per Allium DiscardLateModelResponseAfterCancel — once
        // cancelled, a late success response must not flip the outcome.
        let mut job = DropJob::new(PathBuf::from("/tmp/x.docx"));
        job.complete(JobOutcome::Cancelled);
        let cancelled_at = job.finished_at;
        job.complete(JobOutcome::Success);
        assert!(matches!(job.outcome, JobOutcome::Cancelled));
        assert_eq!(job.finished_at, cancelled_at);
    }

    #[test]
    fn cancel_is_idempotent() {
        let job = DropJob::new(PathBuf::from("/tmp/x.docx"));
        job.cancel();
        job.cancel(); // second cancel must not panic
        assert!(job.cancel_token.is_cancelled());
    }
}
