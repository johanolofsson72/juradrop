# Data Model: Long-tail input formats (.rtf, .pages, .odt)

**Feature**: 009-long-tail-formats
**Date**: 2026-05-28
**Status**: Phase 1 — design complete

This document specifies the type-level deltas for spec 009. Every enum extension, every new function signature, every shared fixture key is pinned here so `/speckit-tasks` decomposes without invention.

## D-001 — `InputFormat` enum (extended)

**Location**: `src-tauri/src/zones/input_format.rs`

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InputFormat {
    Docx,   // spec 003
    Pdf,    // spec 005
    Txt,    // spec 005
    Md,     // spec 005
    Rtf,    // NEW — spec 009
    Pages,  // NEW — spec 009
    Odt,    // NEW — spec 009
}

impl InputFormat {
    pub const ALL: [Self; 7] = [
        Self::Docx, Self::Pdf, Self::Txt, Self::Md,
        Self::Rtf, Self::Pages, Self::Odt,
    ];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Docx => "docx",
            Self::Pdf => "pdf",
            Self::Txt => "txt",
            Self::Md => "md",
            Self::Rtf => "rtf",
            Self::Pages => "pages",
            Self::Odt => "odt",
        }
    }

    pub fn detect_from_path(path: &Path) -> Option<Self> {
        let ext = path.extension()?.to_str()?.to_lowercase();
        match ext.as_str() {
            "docx" => Some(Self::Docx),
            "pdf" => Some(Self::Pdf),
            "txt" => Some(Self::Txt),
            "md" => Some(Self::Md),
            "rtf" => Some(Self::Rtf),
            "pages" => Some(Self::Pages),
            "odt" => Some(Self::Odt),
            _ => None,
        }
    }
}
```

Existing unit tests in `input_format::tests` (5 tests) are extended:
- `detects_each_supported_lowercase_extension` gains three rows.
- `detects_uppercase_and_mixed_case_extensions` gains three rows.
- `rejects_unsupported_extensions` now includes `.doc`, `.epub`, `.html`, `.csv`, `.eml`, `.tar.gz` — long-tail formats removed from the rejected list.
- `all_constant_lists_every_variant_exactly_once` expects 7 unique entries.
- `as_str_matches_serde_lowercase_form` runs over `ALL` (7 entries).

## D-002 — `OutputFormat` enum (runtime variants)

**Location**: `src-tauri/src/zones/output_format.rs` (new file in spec 005 layout, extended here)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    Docx,   // spec 003
    Txt,    // spec 005
    Md,     // spec 005
    // Rtf and Odt variants are NOT added in spec 009.
    // See research.md R-005: no pure-Rust writer available, so
    // .rtf/.odt inputs fall back to .docx sidecar via mirror_from.
}

impl OutputFormat {
    pub const fn mirror_from(input: InputFormat) -> Self {
        match input {
            InputFormat::Docx => Self::Docx,
            InputFormat::Pdf => Self::Docx,    // spec 005 exception
            InputFormat::Txt => Self::Txt,
            InputFormat::Md => Self::Md,
            InputFormat::Rtf => Self::Docx,    // NEW — spec 009 fallback (no Rust RTF writer)
            InputFormat::Pages => Self::Docx,  // NEW — spec 009 always (.pages never written back)
            InputFormat::Odt => Self::Docx,    // NEW — spec 009 fallback (no Rust ODT writer)
        }
    }
}
```

The `mirror_from` function is total over `InputFormat`. Unit test (new): `output_format::tests::mirror_from_is_total` iterates `InputFormat::ALL` and asserts no panic + every variant maps to a defined `OutputFormat`.

## D-003 — `ZoneFailure` enum (extended)

**Location**: `src-tauri/src/zones/errors.rs`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum ZoneFailure {
    // Inherited from spec 003/004/005 — unchanged variants:
    #[error("Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt")]
    InvalidFormat,  // UPDATED COPY (was: "...ett .docx, .pdf, .txt eller .md")

    #[error("Ett dokument i taget")]
    MultipleFiles,

    #[error("Vänta tills föregående dokument är klart")]
    ZoneBusy,

    #[error("AI är inte redo ännu")]
    ZoneDisabled,

    #[error("Kunde inte läsa dokumentet")]
    ParseError,  // .docx-specific

    #[error("Dokumentet är lösenordsskyddat")]
    PasswordProtected,  // .docx + .pdf only — NOT raised for long-tail formats

    #[error("Dokumentet innehåller ingen text")]
    EmptyText,  // applies to all 7 formats

    #[error("AI-motorn svarade inte — försök igen")]
    ModelError,

    #[error("Kunde inte spara sammanfattningen")]
    SaveError,

    #[error("Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än")]
    NoExtractableText,  // .pdf-only

    #[error("Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen")]
    UnsupportedEncoding,  // .txt + .md only

    // NEW — spec 009 format-named long-tail variants:
    #[error("Kunde inte läsa .rtf-filen")]
    RtfParseError,

    #[error("Kunde inte läsa .pages-filen")]
    PagesParseError,

    #[error("Kunde inte läsa .odt-filen")]
    OdtParseError,
}
```

Existing tests in `errors::tests` are extended:
- `ALL_VARIANTS` constant gains 3 new entries (14 total).
- `no_variant_starts_with_english_error_prefix` runs over all 14 (still asserts no `Error:` start, no English `error` substring).
- `every_variant_is_at_most_80_chars` runs over all 14 (longest new variant is 30 chars — `Kunde inte läsa .pages-filen`).
- `every_variant_is_non_empty` runs over all 14.
- `snake_case_serialization_matches_ts_wire_format` extended:
  - `assert_eq!(serde_json::to_string(&ZoneFailure::RtfParseError).unwrap(), "\"rtf_parse_error\"")`
  - same for `pages_parse_error`, `odt_parse_error`
- `round_trips_through_serde` runs over all 14.

## D-004 — Cross-language drift fixture

**Location**: `src-tauri/tests/fixtures/zone-error-strings.json`

```json
{
  "_comment": "Spec 003 / T048 + spec 005 + spec 009 — single source of truth for the Swedish error strings emitted by the drop zones. Rust side (src-tauri/src/zones/errors.rs) and TS side (src/components/DropZone.errors.ts) both assert against this fixture in their drift-detection tests. Update all three together when changing a string. Spec 009 added three keys (rtf_parse_error, pages_parse_error, odt_parse_error) and updated invalid_format copy for the seven supported formats.",
  "invalid_format": "Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt",
  "multiple_files": "Ett dokument i taget",
  "zone_busy": "Vänta tills föregående dokument är klart",
  "zone_disabled": "AI är inte redo ännu",
  "parse_error": "Kunde inte läsa dokumentet",
  "password_protected": "Dokumentet är lösenordsskyddat",
  "empty_text": "Dokumentet innehåller ingen text",
  "model_error": "AI-motorn svarade inte — försök igen",
  "save_error": "Kunde inte spara sammanfattningen",
  "no_extractable_text": "Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än",
  "unsupported_encoding": "Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen",
  "rtf_parse_error": "Kunde inte läsa .rtf-filen",
  "pages_parse_error": "Kunde inte läsa .pages-filen",
  "odt_parse_error": "Kunde inte läsa .odt-filen"
}
```

The TS file `src/components/DropZone.errors.ts` gains three new keys mapped to the same values, plus the updated `invalid_format` value.

## D-005 — Long-tail extractor module shape (×3)

**Locations**:
- `src-tauri/src/zones/rtf_extract.rs`
- `src-tauri/src/zones/pages_extract.rs`
- `src-tauri/src/zones/odt_extract.rs`

Each module follows the spec 005 extractor pattern (mirrors `pdf_extract`, `txt_extract`, `md_extract`):

```rust
// src-tauri/src/zones/rtf_extract.rs
use std::path::Path;
use crate::zones::errors::ZoneFailure;
use crate::zones::extracted_text::ExtractedText;  // shared type from spec 005

/// Best-effort RTF text extraction (FR-003).
///
/// Skips embedded `\pict` and `\object` runs silently (per Q2 clarification).
/// Returns `Err(ZoneFailure::RtfParseError)` for any parse failure including
/// corruption, exotic dialects, and password-protected (FR-008 collapse rule).
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let bytes = std::fs::read(path).map_err(|_| ZoneFailure::RtfParseError)?;
    let doc = rtf_parser::RtfDocument::try_from(bytes.as_slice())
        .map_err(|_| ZoneFailure::RtfParseError)?;
    let raw = collect_text_runs_only(&doc);
    let raw = crate::zones::common::collapse_blank_lines(raw);
    if raw.trim().is_empty() {
        return Err(ZoneFailure::EmptyText);
    }
    Ok(ExtractedText {
        raw,
        was_truncated: raw.chars().count() > 24_000,
        was_partial: false,
        frontmatter: None,
    })
}
```

```rust
// src-tauri/src/zones/pages_extract.rs
use std::path::Path;
use crate::zones::errors::ZoneFailure;
use crate::zones::extracted_text::ExtractedText;

/// Best-effort Apple Pages text extraction (FR-004).
///
/// Modern IWA-based bundles surface as `Err(PagesParseError)` because no
/// pure-Rust IWA decoder exists (research R-003). Legacy bundles with an
/// `index.xml` member are walked with quick-xml, joining paragraphs with
/// `\n` and sections with `\n\n` per Q4 clarification.
///
/// Directory-form `.pages` (legacy macOS) is routed to `InvalidFormat`
/// at the dispatch layer (FR-019) before reaching this extractor.
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let file = std::fs::File::open(path).map_err(|_| ZoneFailure::PagesParseError)?;
    let mut zip = zip::ZipArchive::new(file).map_err(|_| ZoneFailure::PagesParseError)?;
    // Try legacy XML path first.
    if let Ok(mut xml_member) = zip.by_name("index.xml") {
        return extract_from_legacy_xml(&mut xml_member);
    }
    // Modern IWA-based Pages → format-named error.
    Err(ZoneFailure::PagesParseError)
}
```

```rust
// src-tauri/src/zones/odt_extract.rs
use std::path::Path;
use crate::zones::errors::ZoneFailure;
use crate::zones::extracted_text::ExtractedText;

/// ODT text extraction (FR-005).
///
/// Resolves tracked changes to the accepted/final view (Q3 clarification):
/// insertions kept, deletions dropped.
/// Encrypted ODTs and any other failure mode surface as
/// `Err(OdtParseError)` (FR-008 collapse rule).
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure> {
    let file = std::fs::File::open(path).map_err(|_| ZoneFailure::OdtParseError)?;
    let mut zip = zip::ZipArchive::new(file).map_err(|_| ZoneFailure::OdtParseError)?;
    verify_mimetype(&mut zip)?;
    verify_not_encrypted(&mut zip)?;
    let mut content = zip.by_name("content.xml").map_err(|_| ZoneFailure::OdtParseError)?;
    let raw = walk_content_xml_accepted_view(&mut content)?;
    let raw = crate::zones::common::collapse_blank_lines(raw);
    if raw.trim().is_empty() {
        return Err(ZoneFailure::EmptyText);
    }
    Ok(ExtractedText {
        raw,
        was_truncated: raw.chars().count() > 24_000,
        was_partial: false,
        frontmatter: None,
    })
}
```

All three return `ExtractedText` with `was_partial = false` and `frontmatter = None` (long-tail formats never set those fields — they remain spec-005 concerns).

## D-006 — Dispatcher wiring

**Location**: `src-tauri/src/zones/dispatch.rs` (existing)

The dispatcher's format-to-extractor match arm is extended:

```rust
let extracted = match input_format {
    InputFormat::Docx => docx_extract::extract_text(&path)?,
    InputFormat::Pdf => pdf_extract::extract_text(&path)?,
    InputFormat::Txt => txt_extract::extract_text(&path)?,
    InputFormat::Md => md_extract::extract_text(&path)?,
    InputFormat::Rtf => rtf_extract::extract_text(&path)?,    // NEW
    InputFormat::Pages => pages_extract::extract_text(&path)?, // NEW
    InputFormat::Odt => odt_extract::extract_text(&path)?,    // NEW
};
```

The directory-form `.pages` check (FR-019) runs BEFORE this match, in the input-format detection layer:

```rust
// In input_format.rs or the dispatcher's pre-detect step:
if path.extension().and_then(|e| e.to_str()).map(|e| e.to_lowercase()) == Some("pages".into())
    && path.is_dir()
{
    return Err(ZoneFailure::InvalidFormat);
}
```

## D-007 — Hint copy update (TS-side)

**Location**: `src/components/DropZone.identity.ts`

All six entries gain the slash-separated 7-format hint per FR-011:

```typescript
const hintCopyTemplate = "Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för ";

export const ZONE_IDENTITIES: ZoneIdentity[] = [
  { /* ... */ hintCopy: hintCopyTemplate + "sammanfattning" },
  { /* ... */ hintCopy: hintCopyTemplate + "engelsk översättning" },
  { /* ... */ hintCopy: hintCopyTemplate + "svensk översättning" },
  { /* ... */ hintCopy: hintCopyTemplate + "punktlista" },
  { /* ... */ hintCopy: hintCopyTemplate + "anonymisering" },
  { /* ... */ hintCopy: hintCopyTemplate + "klarspråk" },
];
```

The Rust mirror in `ZoneId::hint_copy()` is updated to the same strings. The shared `zone-identity.json` fixture is regenerated. The existing T035 drift test (spec 004) continues to assert byte-equality across all three sources.

## D-008 — Type-level invariants summary

| Invariant | Verified by |
|---|---|
| `InputFormat::ALL.len() == 7` | `input_format::tests::all_constant_lists_every_variant_exactly_once` |
| `OutputFormat::mirror_from` is total over `InputFormat` | `output_format::tests::mirror_from_is_total` (NEW) |
| Every `ZoneFailure` variant Swedish copy ≤ 80 chars | `errors::tests::every_variant_is_at_most_80_chars` (extended) |
| Every `ZoneFailure` snake_case serde tag matches its TS twin | `errors::tests::snake_case_serialization_matches_ts_wire_format` (extended) + `tests/long_tail_drift.rs` (NEW) |
| Long-tail extractors never panic on user input | `tests/rtf_extract.rs`, `tests/pages_extract.rs`, `tests/odt_extract.rs` (corrupt/empty/encrypted fixtures) |
| Hint copy lockstep across Rust + TS + fixture | inherited T035 drift test (extended) |
| Zero new outbound surface | research.md R-007 grep + cargo tree audit (CI step in tasks.md) |
