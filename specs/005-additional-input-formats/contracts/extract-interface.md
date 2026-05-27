# Extract interface contract

## Top-level dispatcher

```rust
// src-tauri/src/zones/extract.rs
pub fn extract_text(path: &Path, format: InputFormat) -> Result<ExtractedText, ZoneFailure>;
```

Single entry point for every input format. Dispatches to the per-format extractor based on `InputFormat`. Wraps every successful result in the unified `ExtractedText { raw, was_truncated, was_partial, frontmatter }` shape.

**Required behaviour:**
- Reads the file from `path` synchronously. Caller is responsible for `spawn_blocking` wrapping if running in async context.
- Returns `Err(ZoneFailure::UnsupportedFormat)` if `format` doesn't match the actual file (mismatch is the caller's bug — the dispatch resolves `InputFormat` from the path itself).
- Returns `Err(ZoneFailure::EmptyText)` if extraction succeeded but the result is whitespace-only after trim — for ANY of the four formats (FR-004 boundary clarification).
- Applies the 24,000-UTF-8-character truncation cap from spec 003 FR-019 AFTER extraction. Sets `was_truncated = true` when truncation kicks in.
- Applies the FR-002 blank-line collapse rule (runs of ≥ 3 blank lines → exactly 2) to EVERY format's output before truncation.
- Wraps the final `raw` in `Redacted<String>` so it cannot leak via Debug / Display / log macros.

## Per-format extractors

### DOCX (unchanged from spec 003)

```rust
// src-tauri/src/zones/docx_extract.rs
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure>;
```

Behaviour byte-identical to spec 003. The top-level dispatcher calls this for `InputFormat::Docx`. `was_partial` is always false; `frontmatter` is always None.

### PDF (new)

```rust
// src-tauri/src/zones/pdf_extract.rs
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure>;
```

**Behaviour:**
1. Read the full file into memory (`std::fs::read(path)`).
2. Probe encryption: call `lopdf::Document::load_from(&bytes[..])` and inspect the trailer for an `/Encrypt` dict. If encrypted → `Err(ZoneFailure::PasswordProtected)`.
3. Count source pages via `lopdf::Document::get_pages().len()` — call this `pages_total`.
4. Call `pdf_extract::extract_text_from_mem(&bytes)` to get the text.
5. Strip null bytes (`text.replace('\0', "")`).
6. Normalise CRLF → LF (`text.replace("\r\n", "\n").replace('\r', "\n")`).
7. Collapse blank-line runs of ≥ 3 to exactly 2.
8. If the cleaned text is empty (zero bytes) AND `pages_total >= 1` → `Err(ZoneFailure::NoExtractableText)`.
9. If the cleaned text is whitespace-only after trim → `Err(ZoneFailure::EmptyText)`.
10. Count text blocks separated by double-newlines — call this `blocks_recovered`. Set `was_partial = blocks_recovered < pages_total` (conservative — false positives are acceptable).
11. Apply truncation cap; set `was_truncated`.
12. Wrap in `Redacted<String>`, return.

**Errors:**
- `PasswordProtected` — `/Encrypt` dict present.
- `NoExtractableText` — pdf-extract returned empty AND `pages_total >= 1`.
- `EmptyText` — extracted text is whitespace-only.
- `ZoneFailure::ParseError(detail)` — pdf-extract returned a non-encryption error.

### TXT (new)

```rust
// src-tauri/src/zones/txt_extract.rs
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure>;
```

**Behaviour:**
1. Read the full file into memory.
2. Sniff `BomKind` from the first 4 bytes.
3. If BOM is `Utf16Le | Utf16Be | Utf32Le | Utf32Be` → `Err(ZoneFailure::UnsupportedEncoding)`.
4. If BOM is `Utf8` → skip first 3 bytes, then decode the remainder as strict UTF-8 (`std::str::from_utf8(&bytes[3..])`).
5. If BOM is `None`:
   - Attempt strict UTF-8 decode of all bytes.
   - On success → use the decoded text.
   - On failure → fall back to `encoding_rs::WINDOWS_1252.decode(&bytes).0` (always succeeds).
6. Strip null bytes; normalise CRLF → LF.
7. Collapse blank-line runs of ≥ 3 to 2.
8. If the cleaned text is whitespace-only → `Err(ZoneFailure::EmptyText)`.
9. Apply truncation cap.
10. Wrap in `Redacted<String>`, return.

`was_partial = false`; `frontmatter = None`.

### MD (new)

```rust
// src-tauri/src/zones/md_extract.rs
pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure>;
```

**Behaviour:**
1. Read the full file into memory.
2. Same BOM cascade as `txt_extract` — UTF-16/UTF-32 → `UnsupportedEncoding`; UTF-8 BOM stripped; UTF-8 strict → Windows-1252 fallback.
3. Detect a leading frontmatter block within the first 8 KB:
   - YAML: `---\n<content>\n---\n` at byte 0.
   - TOML: `+++\n<content>\n+++\n` at byte 0.
   - If found, capture the entire block (both fences + content + trailing newline) into `frontmatter: Option<String>`; the body is everything after the closing fence.
   - If no opening fence at byte 0, or no closing fence within 8 KB, `frontmatter = None` and the whole file is body.
4. Apply null-byte stripping + CRLF normalisation + blank-line collapse to the BODY (not the frontmatter — frontmatter is preserved byte-identical).
5. If the body is whitespace-only → `Err(ZoneFailure::EmptyText)` (even if frontmatter is present).
6. Apply truncation cap to the BODY length; frontmatter is excluded from the cap (it's metadata, not content the model sees).
7. Wrap body in `Redacted<String>`, return.

## ExtractedText shape

```rust
pub struct ExtractedText {
    pub raw: Redacted<String>,         // body text, after truncation, wrapped
    pub was_truncated: bool,           // true ⇒ raw.chars().count() == 24_000
    pub was_partial: bool,             // true only for PDF with incomplete pages
    pub frontmatter: Option<String>,   // some only for MD with leading fenced block
}
```

**Postconditions:**
- `was_partial == true` ⇒ extractor was `pdf_extract`.
- `frontmatter.is_some()` ⇒ extractor was `md_extract`.
- `raw.as_inner().chars().count() <= 24_000`.
- `raw.as_inner()` contains no `\0` bytes, no `\r` bytes.
- Runs of 3+ consecutive `\n` in `raw` are collapsed to exactly 2.
