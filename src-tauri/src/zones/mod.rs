// Spec 035 — panic-site ratchet. Deny unwrap/expect/panic in PRODUCTION code of
// the whole zones tree (the document-processing surface where a panic becomes a
// user-visible WKWebView crash). `cfg_attr(not(test))` exempts `#[cfg(test)]`
// code so tests may use unwrap/expect freely. Benign sites carry `#[allow]` +
// justification; new sites fail `cargo clippy -D warnings` in CI (spec 031).
#![cfg_attr(
    not(test),
    deny(clippy::unwrap_used, clippy::expect_used, clippy::panic)
)]

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

// Spec 005 — additional input formats (.pdf, .txt, .md) + per-format writers.
pub mod extract;
pub mod input_format;
pub mod md_extract;
pub mod md_write;
pub mod output_format;
pub mod pdf_extract;
pub mod txt_extract;
pub mod txt_write;

// Spec 009 — long-tail input formats (.rtf, .odt). Spec 028 removed .pages.
pub mod odt_extract;
pub mod rtf_extract;

// Spec 014 — Anonymisera output-side PII-residue sweep.
pub mod pii_sweep;

// Spec 039 — Anonymisera input-side deterministic structured-PII replacement.
pub mod pii_scrub;

// Spec 044 — deterministic quote preservation for the translation zones.
pub mod quote_mask;

// Spec 038 — structure-aware chunking for long documents.
pub mod chunking;

pub use errors::ZoneFailure;
pub use extract::ExtractedText;
pub use input_format::InputFormat;
pub use job::DropJob;
pub use output_format::OutputFormat;
pub use snapshot::{JobOutcome, ZoneSnapshot, ZoneState};
pub use zone_id::ZoneId;
