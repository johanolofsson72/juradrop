// Spec 003 — drop-zone domain.
//
// Owns the "Sammanfatta" first drop zone (drag .docx → produce a Swedish
// summary .docx sidecar). Spec 004 will add the remaining five zones
// (TillEngelska, TillSvenska, Punktlista, Anonymisera, Förenkla) as
// siblings under this module.
//
// Module layout per `specs/003-first-zone-sammanfatta/plan.md`:
//   - errors      — ZoneFailure enum + Swedish-string mapping
//   - snapshot    — ZoneState / JobOutcome / ZoneSnapshot wire types
//   - job         — DropJob entity + cancel token plumbing
//   - prompts     — fixed Swedish summarization prompt (R-010)
//   - docx_extract — .docx → ExtractedText (truncation, password, empty)
//   - docx_write  — ExtractedText + model response → SummaryDoc bytes
//   - sidecar_path — canonical + timestamp-suffixed filename + atomic write
//   - sammanfatta — zone state machine + dispatch pipeline

pub mod docx_extract;
pub mod docx_write;
pub mod errors;
pub mod job;
// Spec 004 T004 — prompts moved to crate::prompts (one file per zone).
// The `zones/prompts.rs` shim is gone; old callers were inside this
// crate and have been migrated to `crate::prompts::...`.
pub mod sammanfatta;
pub mod sidecar_path;
pub mod snapshot;
pub mod zone_id;

pub use errors::ZoneFailure;
pub use job::DropJob;
pub use snapshot::{JobOutcome, ZoneSnapshot, ZoneState};
pub use zone_id::ZoneId;
