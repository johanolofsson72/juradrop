// Spec 003 / T005 — ZoneFailure enum + Swedish-string mapping.
//
// Single source of truth for the seven Swedish error categories from
// FR-013..FR-020 plus the two operational variants (zone_disabled, save_error).
// The `#[error("…")]` strings are the user-visible Swedish phrases that the
// React layer mirrors in `src/components/SammanfattaZone.errors.ts`.
//
// Invariants (per Allium `value SwedishCopy`):
//   - NoEnglishPrefix: no variant starts with "Error:"
//   - LengthBounded:   every string ≤ 80 chars
//   - NonEmpty:        every string > 0 chars

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum ZoneFailure {
    /// FR-013 — non-.docx drop.
    #[error("Endast .docx i denna version")]
    InvalidFormat,

    /// FR-014 — 2+ files dropped at once.
    #[error("Ett dokument i taget")]
    MultipleFiles,

    /// FR-015 — drop arrived while a previous job is still in flight.
    #[error("Vänta tills föregående dokument är klart")]
    ZoneBusy,

    /// FR-012 — zone is disabled because UserVisibleStatus != Klar.
    #[error("AI är inte redo ännu")]
    ZoneDisabled,

    /// FR-016 — corrupt zip / malformed XML inside the .docx.
    #[error("Kunde inte läsa dokumentet")]
    ParseError,

    /// FR-017 — password-protected .docx detected before any model call.
    #[error("Dokumentet är lösenordsskyddat")]
    PasswordProtected,

    /// FR-018 — extracted text is whitespace-only.
    #[error("Dokumentet innehåller ingen text")]
    EmptyText,

    /// FR-020 — model timeout, empty response, or transport error.
    #[error("AI-motorn svarade inte — försök igen")]
    ModelError,

    /// Edge case — filesystem rejected the sidecar write.
    #[error("Kunde inte spara sammanfattningen")]
    SaveError,
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL_VARIANTS: &[ZoneFailure] = &[
        ZoneFailure::InvalidFormat,
        ZoneFailure::MultipleFiles,
        ZoneFailure::ZoneBusy,
        ZoneFailure::ZoneDisabled,
        ZoneFailure::ParseError,
        ZoneFailure::PasswordProtected,
        ZoneFailure::EmptyText,
        ZoneFailure::ModelError,
        ZoneFailure::SaveError,
    ];

    #[test]
    fn no_variant_starts_with_english_error_prefix() {
        for v in ALL_VARIANTS {
            let s = v.to_string();
            assert!(
                !s.starts_with("Error:"),
                "ZoneFailure::{v:?} has English `Error:` prefix"
            );
            assert!(
                !s.to_lowercase().contains("error"),
                "ZoneFailure::{v:?} contains the English word 'error'"
            );
        }
    }

    #[test]
    fn every_variant_is_at_most_80_chars() {
        for v in ALL_VARIANTS {
            let len = v.to_string().chars().count();
            assert!(
                len <= 80,
                "ZoneFailure::{v:?} is {len} chars; spec FR-021 caps at 80"
            );
        }
    }

    #[test]
    fn every_variant_is_non_empty() {
        for v in ALL_VARIANTS {
            assert!(
                !v.to_string().is_empty(),
                "ZoneFailure::{v:?} produced empty string"
            );
        }
    }

    #[test]
    fn snake_case_serialization_matches_ts_wire_format() {
        // The TS side (SammanfattaZone.errors.ts) keys off the snake_case
        // tag. This test catches a refactor that flips the rename attr.
        let json = serde_json::to_string(&ZoneFailure::InvalidFormat).unwrap();
        assert_eq!(json, "\"invalid_format\"");
    }

    #[test]
    fn round_trips_through_serde() {
        for v in ALL_VARIANTS {
            let json = serde_json::to_string(v).unwrap();
            let back: ZoneFailure = serde_json::from_str(&json).unwrap();
            assert_eq!(*v, back);
        }
    }
}
