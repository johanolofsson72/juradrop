# Data Model — Spec 005

Date: 2026-05-27

## Enums

### InputFormat (new — `src-tauri/src/zones/input_format.rs`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InputFormat {
    Docx,
    Pdf,
    Txt,
    Md,
}

impl InputFormat {
    /// Detect the format from a file path's lowercase extension.
    /// Returns `None` for any extension outside the supported set
    /// (caller maps that to `ZoneFailure::UnsupportedFormat`).
    pub fn detect_from_path(path: &Path) -> Option<Self> {
        let ext = path.extension()?.to_str()?.to_lowercase();
        match ext.as_str() {
            "docx" => Some(Self::Docx),
            "pdf" => Some(Self::Pdf),
            "txt" => Some(Self::Txt),
            "md" => Some(Self::Md),
            _ => None,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Docx => "docx",
            Self::Pdf => "pdf",
            Self::Txt => "txt",
            Self::Md => "md",
        }
    }

    pub const ALL: [Self; 4] = [Self::Docx, Self::Pdf, Self::Txt, Self::Md];
}
```

### OutputFormat (new — `src-tauri/src/zones/output_format.rs`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutputFormat {
    Docx,
    Txt,
    Md,
}

impl OutputFormat {
    /// FR-011 — output format mirrors input with one exception: PDF → DOCX.
    pub const fn mirror_from(input: InputFormat) -> Self {
        match input {
            InputFormat::Docx => Self::Docx,
            InputFormat::Pdf => Self::Docx,
            InputFormat::Txt => Self::Txt,
            InputFormat::Md => Self::Md,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Docx => "docx",
            Self::Txt => "txt",
            Self::Md => "md",
        }
    }
}
```

### BomKind (new — internal to `txt_extract.rs`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BomKind {
    None,
    Utf8,
    Utf16Le,
    Utf16Be,
    Utf32Le,
    Utf32Be,
}

impl BomKind {
    /// Sniff the leading 4 bytes. Returns `None` if no BOM is present.
    fn detect(bytes: &[u8]) -> Self {
        match bytes {
            // UTF-32 LE must be checked BEFORE UTF-16 LE — the 4-byte
            // UTF-32 LE BOM has the same first two bytes as UTF-16 LE.
            [0xFF, 0xFE, 0x00, 0x00, ..] => Self::Utf32Le,
            [0x00, 0x00, 0xFE, 0xFF, ..] => Self::Utf32Be,
            [0xFF, 0xFE, ..] => Self::Utf16Le,
            [0xFE, 0xFF, ..] => Self::Utf16Be,
            [0xEF, 0xBB, 0xBF, ..] => Self::Utf8,
            _ => Self::None,
        }
    }

    fn byte_length(self) -> usize {
        match self {
            Self::Utf8 => 3,
            Self::Utf16Le | Self::Utf16Be => 2,
            Self::Utf32Le | Self::Utf32Be => 4,
            Self::None => 0,
        }
    }
}
```

## Values

### ExtractedText (extended — `src-tauri/src/zones/extract.rs`)

```rust
pub struct ExtractedText {
    /// The raw extracted text, wrapped in Redacted so it cannot leak
    /// via Debug / Display / accidental logging.
    pub raw: Redacted<String>,

    /// True when truncation kicked in — the model only saw the first
    /// 24,000 UTF-8 characters. Writer renders the spec 003 truncation
    /// notice when this is true.
    pub was_truncated: bool,

    /// (NEW in spec 005) True when PDF extraction recovered text from
    /// fewer than 100% of the source pages OR pdf-extract reported any
    /// per-page error. False for every other input format.
    pub was_partial: bool,

    /// (NEW in spec 005) Captured Markdown frontmatter block (YAML or
    /// TOML), if the input was `.md` and a leading fenced block was
    /// found within the first 8 KB. Stored verbatim including both
    /// fences and the trailing newline. None for every other format.
    pub frontmatter: Option<String>,
}
```

**Invariants** (enforced via type signatures + dispatch-level assertions):
- `was_partial == true` ⇒ the source's `InputFormat` was `Pdf`.
- `frontmatter.is_some()` ⇒ the source's `InputFormat` was `Md`.
- `raw.as_inner().chars().count() <= 24_000` always (truncation cap from spec 003 FR-019). When `was_truncated == true`, the raw length is exactly 24,000 chars.

### SidecarPlan (new — `src-tauri/src/zones/sidecar_path.rs`)

```rust
pub struct SidecarPlan {
    pub source_path: PathBuf,
    pub input_format: InputFormat,
    pub output_format: OutputFormat,
    pub zone_id: ZoneId,
    pub output_path: PathBuf,  // resolved via canonical_for + collision-suffix
}

impl SidecarPlan {
    pub fn resolve(source: &Path, zone_id: ZoneId) -> Result<Self, ZoneFailure> {
        let input_format = InputFormat::detect_from_path(source)
            .ok_or(ZoneFailure::UnsupportedFormat)?;
        let output_format = OutputFormat::mirror_from(input_format);
        let output_path = sidecar_path::resolve_target(source, zone_id, output_format);
        Ok(Self { source_path: source.into(), input_format, output_format, zone_id, output_path })
    }
}
```

## Errors

### ZoneFailure (extended — `src-tauri/src/zones/errors.rs`)

```rust
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ZoneFailure {
    // ===== Existing variants (spec 003) =====
    PasswordProtected,
    UnsupportedFormat,
    EmptyText,
    Truncated,                        // informational, paired with output
    OllamaError { detail: String },
    WriteFailure { detail: String },
    Cancelled,

    // ===== New variants (spec 005) =====
    /// PDF that has ≥ 1 page but no embedded text content stream at all.
    /// Surfaced via the new Swedish copy:
    /// "Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än."
    NoExtractableText,

    /// .txt or .md file in UTF-16 LE, UTF-16 BE, UTF-32 LE, or UTF-32 BE.
    /// Detected by leading BOM before any decode attempt.
    /// Surfaced via the new Swedish copy:
    /// "Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen."
    UnsupportedEncoding,
}

impl ZoneFailure {
    pub fn swedish_copy(&self) -> &'static str {
        match self {
            // ...existing arms unchanged from spec 003/004...
            Self::PasswordProtected =>
                "Filen är lösenordsskyddad — öppna och spara om utan lösenord.",
            Self::UnsupportedFormat =>
                "Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md.",   // UPDATED
            Self::EmptyText =>
                "Dokumentet innehåller ingen text.",
            // ... rest unchanged ...
            Self::NoExtractableText =>
                "Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än.",
            Self::UnsupportedEncoding =>
                "Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen.",
        }
    }
}
```

## Module shape

```text
src-tauri/src/zones/
├── mod.rs                          # re-exports: InputFormat, OutputFormat, ExtractedText, SidecarPlan, ZoneFailure
├── input_format.rs                 # NEW
├── output_format.rs                # NEW
├── extract.rs                      # NEW — pub fn extract_text(path, fmt) → Result<ExtractedText, ZoneFailure>
├── docx_extract.rs                 # EXISTING — extracted to be one branch of extract_text
├── pdf_extract.rs                  # NEW
├── txt_extract.rs                  # NEW — BOM detection + UTF-8 / Windows-1252 cascade
├── md_extract.rs                   # NEW — reuses txt cascade + adds frontmatter capture
├── docx_write.rs                   # MODIFIED — accept optional partial-extraction notice
├── txt_write.rs                    # NEW
├── md_write.rs                     # NEW
├── sidecar_path.rs                 # MODIFIED — SidecarPlan + output-format-aware filenames
├── sammanfatta.rs (generic DropZone) # MODIFIED — calls extract.rs + per-format writer
├── errors.rs                       # MODIFIED — new variants + Swedish copy updates
└── zone_id.rs                      # MODIFIED — hint_copy() updated per-zone for four formats
```

## Cross-language fixture changes

`src-tauri/tests/fixtures/zone-identity.json` — every zone's `hint_copy` is updated to mention all four formats. The T035 drift test asserts byte-identical match between this fixture, Rust `ZoneId::hint_copy()`, and TS `ZONE_IDENTITIES`.

New hint copy (each ≤ 80 chars, validated by `zone_parametric.rs`):

| Zone | New hint_copy |
|---|---|
| sammanfatta | `Släpp ett .docx, .pdf, .txt eller .md för sammanfattning` |
| tillengelska | `Släpp ett .docx, .pdf, .txt eller .md för engelsk översättning` |
| tillsvenska | `Släpp ett .docx, .pdf, .txt eller .md för svensk översättning` |
| punktlista | `Släpp ett .docx, .pdf, .txt eller .md för punktlista` |
| anonymisera | `Släpp ett .docx, .pdf, .txt eller .md för anonymisering` |
| forenkla | `Släpp ett .docx, .pdf, .txt eller .md för klarspråk` |

Lengths (chars): 56, 62, 61, 53, 55, 54 — all under the 80-char SwedishCopy invariant.

`src-tauri/tests/fixtures/zone-error-strings.json` — extended with two new keys:

```json
{
  // ...existing keys unchanged...
  "no_extractable_text": "Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än.",
  "unsupported_encoding": "Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen.",
  "unsupported_format": "Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md."  // OVERWRITTEN
}
```

The TS side mirrors this in `src/components/DropZone.errors.ts`. The existing spec 003 cross-language drift test catches drift in either direction.
