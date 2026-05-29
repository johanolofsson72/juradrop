// Spec 003 / T005 + spec 005 + spec 009 — ZoneFailure enum + Swedish-string mapping.
//
// Single source of truth for the Swedish error categories surfaced by
// the drop zones. The `#[error("…")]` strings are the user-visible
// Swedish phrases that the React layer mirrors in
// `src/components/DropZone.errors.ts`.
//
// Invariants (per Allium `value SwedishCopy`):
//   - NoEnglishPrefix: no variant starts with "Error:"
//   - LengthBounded:   every string ≤ 80 chars
//   - NonEmpty:        every string > 0 chars
//
// Spec 009 added three format-named long-tail variants
// (RtfParseError, PagesParseError, OdtParseError) and updated the
// InvalidFormat copy to list all seven supported formats.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum ZoneFailure {
    /// FR-013 — extension outside the supported set. Spec 009 updated
    /// the copy to list all seven supported formats.
    #[error("Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt")]
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

    /// FR-017 — password-protected document detected before any model call.
    /// Spec 009: this variant is exclusive to .docx and .pdf. Long-tail
    /// formats collapse their password-protected branch into the format-named
    /// parse-error variant per FR-008.
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

    /// Spec 005 FR-004 — PDF with ≥ 1 page but pdf-extract returned
    /// zero bytes of text (image-only / scanned, no embedded text layer).
    #[error("Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än")]
    NoExtractableText,

    /// Spec 005 FR-007 — `.txt` or `.md` file in an encoding other than
    /// UTF-8 or Windows-1252 (UTF-16 LE/BE, UTF-32 LE/BE).
    #[error("Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen")]
    UnsupportedEncoding,

    /// Spec 009 FR-006 + FR-007 — any failure reading a `.rtf`. Collapses
    /// the password-protected branch per FR-008.
    #[error("Kunde inte läsa .rtf-filen")]
    RtfParseError,

    /// Spec 009 FR-006 + FR-007 — any failure reading a `.pages`. Collapses
    /// the password-protected branch per FR-008.
    #[error("Kunde inte läsa .pages-filen")]
    PagesParseError,

    /// Spec 009 FR-006 + FR-007 — any failure reading a `.odt`. Collapses
    /// the password-protected branch per FR-008.
    #[error("Kunde inte läsa .odt-filen")]
    OdtParseError,

    /// Spec 024 — file exceeds `MAX_INPUT_FILE_BYTES` (50 MB). Rejected by
    /// a pre-read metadata check before the whole file is loaded into
    /// memory (OOM guard). Honest Swedish message instead of a crash.
    #[error("Filen är för stor — max 50 MB")]
    FileTooLarge,
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
        ZoneFailure::NoExtractableText,
        ZoneFailure::UnsupportedEncoding,
        // Spec 009 — format-named long-tail variants.
        ZoneFailure::RtfParseError,
        ZoneFailure::PagesParseError,
        ZoneFailure::OdtParseError,
        // Spec 024 — oversized-file guard.
        ZoneFailure::FileTooLarge,
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
        // The TS side (DropZone.errors.ts) keys off the snake_case
        // tag. This test catches a refactor that flips the rename attr.
        let json = serde_json::to_string(&ZoneFailure::InvalidFormat).unwrap();
        assert_eq!(json, "\"invalid_format\"");
        // Spec 009 — long-tail variants serialize to their snake_case tags.
        assert_eq!(
            serde_json::to_string(&ZoneFailure::RtfParseError).unwrap(),
            "\"rtf_parse_error\""
        );
        assert_eq!(
            serde_json::to_string(&ZoneFailure::PagesParseError).unwrap(),
            "\"pages_parse_error\""
        );
        assert_eq!(
            serde_json::to_string(&ZoneFailure::OdtParseError).unwrap(),
            "\"odt_parse_error\""
        );
    }

    #[test]
    fn round_trips_through_serde() {
        for v in ALL_VARIANTS {
            let json = serde_json::to_string(v).unwrap();
            let back: ZoneFailure = serde_json::from_str(&json).unwrap();
            assert_eq!(*v, back);
        }
    }

    #[test]
    fn long_tail_variants_name_their_format_explicitly() {
        // Spec 009 FR-007 — the format-named errors MUST name the
        // format explicitly in the Swedish copy. Catches a regression
        // where someone replaces the variant's copy with a generic
        // "Kunde inte läsa dokumentet".
        assert_eq!(
            ZoneFailure::RtfParseError.to_string(),
            "Kunde inte läsa .rtf-filen"
        );
        assert_eq!(
            ZoneFailure::PagesParseError.to_string(),
            "Kunde inte läsa .pages-filen"
        );
        assert_eq!(
            ZoneFailure::OdtParseError.to_string(),
            "Kunde inte läsa .odt-filen"
        );
    }

    #[test]
    fn invalid_format_copy_lists_all_seven_formats() {
        // Spec 009 FR-012 — InvalidFormat copy must mention every
        // supported extension. Catches a copy regression after adding
        // a new format.
        let copy = ZoneFailure::InvalidFormat.to_string();
        for ext in &[".docx", ".pdf", ".txt", ".md", ".rtf", ".pages", ".odt"] {
            assert!(
                copy.contains(ext),
                "InvalidFormat copy missing {ext}: {copy:?}"
            );
        }
        assert!(copy.chars().count() <= 80, "InvalidFormat copy > 80 chars");
    }
}
