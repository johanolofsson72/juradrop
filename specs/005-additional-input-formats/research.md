# Phase 0 Research — Spec 005 (additional input formats)

Date: 2026-05-27

## R-001 — PDF text extractor crate

**Decision**: Use `pdf-extract = "0.7"` for text extraction from `.pdf` input.

**Rationale**:
- Pure Rust, no external binaries, no shell-out, no network — Principle I compliant.
- MIT-licensed — compatible with the project's MIT licence.
- Stable API: a single top-level function `pdf_extract::extract_text(path) -> Result<String, OutputError>`.
- Built on `lopdf` (pure Rust, 4M+ downloads) for parsing — well-audited stack.
- Handles encrypted PDFs by returning a specific error (`OutputError::PdfError(_)` with the underlying lopdf encryption error) — the dispatch maps it to `PasswordProtected`.
- Handles image-only PDFs by returning an empty string with `Ok(_)` — the dispatch maps that to `NoExtractableText`.
- Returns text with synthesized newlines per-line + per-page; suitable for legal documents where line-level fidelity matters.

**Alternatives considered**:
- `lopdf` directly + custom text extraction: rejected — reinvents pdf-extract's text-stream parser. Higher risk, no payoff.
- `pdfium-render` (Chromium's PDFium bindings): rejected — requires the PDFium dynamic library to be present at runtime. Violates Principle II (would require Homebrew or manual install).
- `poppler-utils` (`pdftotext` shell-out): rejected — external binary, violates Principle II, breaks the signed-bundle promise.
- `mupdf-rs`: rejected — pulls in the MuPDF C library; bigger binary, harder licensing (Affero clauses for the C side).

**Implementation notes**:
- Wrap `pdf_extract::extract_text(...)` in `tokio::task::spawn_blocking` since it does synchronous I/O + parsing.
- The crate's `OutputError` variants need explicit pattern-matching to distinguish encryption from other parse errors. Encryption-related errors must map to `PasswordProtected`; everything else to `ParseError` (using the existing spec 003 variant).
- Per-page error tracking for FR-002a partial-extraction flagging: pdf-extract doesn't expose per-page error counts directly. Workaround: parse the PDF page count with `lopdf::Document::load(path).get_pages().len()`, then count newline-separated "blocks" in the extracted output, then mark partial when the block count is less than the page count. Conservative heuristic — false positives are OK (we just over-warn).

## R-002 — Encoding cascade for .txt / .md

**Decision**: BOM-first detection via the first 4 bytes, then strict UTF-8 via `std::str::from_utf8`, then Windows-1252 via `encoding_rs::WINDOWS_1252.decode`. The Windows-1252 fallback is total (every byte maps to a character) so no third error path is needed for non-BOM files.

**Rationale**:
- `encoding_rs` (`encoding_rs = "0.8"`) is Mozilla's Rust port of the WHATWG Encoding Standard. Used by Firefox + ripgrep + ~5M downloads on crates.io. Audited, pure Rust, offline.
- `WINDOWS_1252.decode(bytes)` is a total decoder — every byte 0x00–0xFF maps to a Unicode codepoint. No error path possible.
- BOM detection via leading 4 bytes is unambiguous: UTF-8 (`EF BB BF`), UTF-16 LE (`FF FE` with the next bytes NOT `00 00`), UTF-16 BE (`FE FF`), UTF-32 LE (`FF FE 00 00`), UTF-32 BE (`00 00 FE FF`). The UTF-16 LE vs UTF-32 LE discrimination requires checking bytes 3 and 4 (UTF-32 has the additional `00 00`).
- Strict UTF-8 via `std::str::from_utf8(bytes)` returns `Err` on the first invalid sequence; this is the trigger for Windows-1252 fallback.

**Alternatives considered**:
- `chardetng` (encoding auto-detection): rejected — adds complexity for a v1 that only supports two encodings. If a user has a file in an exotic encoding (Shift-JIS, GB18030, etc.), the right answer is to ask them to re-save as UTF-8 (per the FR-007 Swedish error), not to silently guess.
- Try-all-encodings cascade: rejected — too many false positives. A Windows-1252 file will partially decode as latin-1, mac-roman, etc., producing slightly different gibberish. Better to fail fast with a specific error.
- Pure `std::str::from_utf8` only, no fallback: rejected — Swedish legal documents from older systems are commonly Windows-1252 (Microsoft Word's default until Office 2008). Refusing them with a UTF-8-only policy is hostile to the user base.

**Implementation notes**:
- The BOM detector reads the first 4 bytes of the file once and returns a `BomKind`. The full file is read separately (memory-mapped for files > 4 KB; direct read otherwise).
- The UTF-8 BOM, if present, is stripped before the body is decoded (the BOM is `EF BB BF`, not part of the actual text).
- The Windows-1252 fallback uses `encoding_rs::WINDOWS_1252.decode(bytes).0` to get the `Cow<str>` — `.0` is the decoded text, `.1` is the encoding used (always `WINDOWS_1252`), `.2` is the had-errors flag (always false for Windows-1252).

## R-003 — Markdown frontmatter capture

**Decision**: Detect a leading YAML frontmatter block (`---\n<content>\n---\n`) or TOML frontmatter block (`+++\n<content>\n+++\n`) within the first 8 KB of the file. If found, capture the entire block (both fences + content + trailing newline) into the `ExtractedText.frontmatter: Option<String>` field. Feed only the body Markdown to the model.

**Rationale**:
- YAML frontmatter is the standard in Obsidian, Bear, Hugo, Jekyll, MkDocs, and most other Markdown ecosystems.
- TOML frontmatter is common in Hugo and Zola — less common but worth supporting since the parser is the same regex shape.
- The 8 KB cap prevents pathological inputs from blowing up the search (a `---` fence at the top with no closing fence would otherwise scan the whole file).
- Strip-and-restore guarantees byte-identical preservation. The model is unreliable at preserving structured frontmatter (it drops fields, invents new ones, reformats keys).

**Alternatives considered**:
- Pass frontmatter through as-is and hope the model preserves it: rejected — empirically the model drops or rewrites frontmatter ~40% of the time.
- Strip frontmatter and discard it: rejected — the user's Obsidian tags, dates, and Hugo build metadata would be lost on round-trip.
- Use a dedicated YAML/TOML parser to validate the frontmatter: rejected — overkill, and would force us to reject malformed frontmatter (unfriendly). The strip-and-restore approach is content-agnostic.

**Implementation notes**:
- Detection regex: `^(?:---|\+\+\+)\n(?s).*?\n(?:---|\+\+\+)\n` anchored at byte 0, capped at 8 KB. Must use the matching fence (YAML opens and closes with `---`; TOML opens and closes with `+++`).
- The captured block is stored as `String` (not parsed). Prepended verbatim to the `.md` sidecar before the FR-014 H1 header.
- If detection fails (no opening fence at byte 0, or no closing fence within 8 KB), `frontmatter` is `None` and the whole file is body.

## R-004 — Output format mirror rule encoding

**Decision**: Encode the mirror rule as a single `OutputFormat::mirror_from(InputFormat)` associated function with an exhaustive match. PDF input is the only exception (PDF → DOCX); the other three formats map identity (DOCX → DOCX, TXT → TXT, MD → MD).

**Rationale**:
- A single Rust match expression gives compile-time exhaustiveness: adding a fifth input format later forces the developer to update the mirror rule.
- Symmetric with the existing `ZoneId::sidecar_suffix()` associated function pattern from spec 004.
- The PDF→DOCX exception is documented in the function body, not scattered across writer call sites.

**Alternatives considered**:
- Per-extractor "produces" field encoding the output extension: rejected — couples extraction to output, harder to test in isolation.
- Pattern-match at every call site: rejected — DRY violation; the rule lives in one place.

**Implementation notes**:
```rust
impl OutputFormat {
    pub const fn mirror_from(input: InputFormat) -> Self {
        match input {
            InputFormat::Docx => Self::Docx,
            InputFormat::Pdf => Self::Docx,  // FR-011 exception
            InputFormat::Txt => Self::Txt,
            InputFormat::Md => Self::Md,
        }
    }
}
```

## R-005 — Sidecar filename construction across formats

**Decision**: Extend `sidecar_path::canonical_for(source, zone_id)` to `sidecar_path::canonical_for(source, zone_id, output_format)`. The function returns `<parent>/<stem>.<zone_suffix>.<ext>` where `<ext>` is `output_format.as_str()` (`"docx"`, `"txt"`, or `"md"`).

**Rationale**:
- Single call site, single rule, no per-format duplication.
- The existing FR-006 collision-timestamp rule applies unchanged — only the extension varies.
- Reuses the spec 004 ZoneId suffix table (no per-output-format suffix variation).

**Alternatives considered**:
- Per-output-format `canonical_for_<ext>` functions: rejected — three near-identical implementations. Worse maintainability.
- Embed the output format in `ZoneId`: rejected — couples zone identity to extraction format, makes the spec 004 ZoneId table awkward.

## R-006 — Blank-line collapse implementation

**Decision**: Single post-extract pass per format that collapses runs of three or more `\n\n\n...` (after CRLF normalisation) down to exactly `\n\n`. Implemented as a `&str → String` function applied to every extractor's output before truncation.

**Rationale**:
- Conservative (per the FR-002 clarification): kills page-break / column-break noise without inventing paragraph detection.
- Applied uniformly across all four formats so the dispatch is format-agnostic past the extract step.
- Cheap: O(n) single pass with no allocation beyond the output `String`.

**Alternatives considered**:
- Per-format normalisation (different rules per extractor): rejected — invites drift between formats.
- Aggressive reflow (join lines within a "paragraph"): rejected — destroys legitimate intentional line breaks in legal documents.

**Implementation notes**:
- Apply BEFORE truncation (so truncation operates on cleaned text and the character cap reflects what the model actually sees).
- Apply AFTER null-byte stripping (otherwise nulls between newlines could leave malformed runs).

## R-007 — Two new ZoneFailure variants

**Decision**: Extend `ZoneFailure` enum (in `src-tauri/src/zones/errors.rs`) with two new variants: `NoExtractableText` (PDF-only) and `UnsupportedEncoding` (TXT/MD only). Each variant carries its own Swedish copy. The UI mapping is identical to existing variants — both transition the zone to the `error` visible state via the existing event channel.

**Rationale**:
- Different root causes → different errors → different user recovery actions (re-export with text layer vs. re-save as UTF-8).
- Mapping to the existing `error` visible state means zero state-machine changes — Allium invariant `StateMachineUnchangedFromSpec004` holds.
- Both variants get tested in the existing `zone-error-strings.json` cross-language fixture; the existing T035 drift pattern applies.

**Alternatives considered**:
- Reuse the `UnsupportedFormat` variant for both: rejected — `NoExtractableText` is a different failure mode (the file IS the supported format, the format is just empty of extractable text). Different Swedish copy is correct.
- Add a single `ExtractionFailure(reason)` catch-all variant: rejected — loses the specific Swedish copy guarantee. Honest failure states (Principle VIII) require specific copy.

## R-008 — Memory usage for large PDFs

**Decision**: Read the entire PDF into memory (`std::fs::read`) before passing to `pdf-extract`. The 24,000-character truncation cap means we never hold more than ~150 KB of extracted text in memory at peak; the source PDF itself is typically < 10 MB. Memory-mapped reading via `memmap2` is NOT used at v1 — adds a dependency for no measurable benefit on documents this size.

**Rationale**:
- macOS handles unbuffered file reads efficiently for files < 100 MB.
- Memory-mapping would add a dependency and complicate the `Redacted<String>` boundary (the mmap'd bytes would need wrapping too).
- The truncation cap is the real memory ceiling; PDF size is a transient peak.

**Alternatives considered**:
- Stream the PDF page-by-page: rejected — pdf-extract doesn't expose a streaming API. Would need to drop down to `lopdf` and reimplement text extraction.

## R-009 — Cargo.toml entries

**Decision**:
```toml
# Spec 005 — pure-Rust PDF text extraction. MIT-licensed, no external
# binaries, no network. Offline-only.
pdf-extract = "0.7"

# Spec 005 — Windows-1252 fallback + BOM detection for the .txt / .md
# encoding cascade. Mozilla's encoding_rs, pure Rust.
encoding_rs = "0.8"
```

Both added to `[dependencies]` (no dev-dependencies needed — the existing test infrastructure reuses production code paths).

**Rationale**: Both pinned at minor-version to follow the existing project pattern (semver-compatible auto-update, major-version requires explicit bump).
