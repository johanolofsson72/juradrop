# Feature Specification: Long-tail input formats (.rtf, .pages, .odt)

**Feature Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`)

**Created**: 2026-05-28

**Status**: Draft

**Input**: User description: Add best-effort input support for three long-tail Swedish/macOS document formats: .rtf, .pages (Apple Pages), and .odt (OpenDocument Text). These are NOT mainstream formats in the legal workflow but appear often enough that users will drag them onto JuraDrop and expect "something". Behavior: when a user drops one of these three formats onto any of the six zones, JuraDrop attempts best-effort text extraction. If extraction succeeds, processing continues as normal. If extraction fails, the zone surfaces a Swedish error message that names the format explicitly — never a generic "fel uppstod". The hint copy in each zone must be extended to list the new formats alongside the existing .docx, .pdf, .txt, .md. Any other extension still surfaces "Format inte stött: <ext>" (existing behavior from spec 003/005). Pure-Rust parser crates only; no shelling out; no new outbound network calls (Principle I).

## Clarifications

### Session 2026-05-28 (auto-picked recommendations per `.claude/settings.json`)

- Q: With seven formats in the list, the existing comma-separated hint copy `Släpp ett .docx, .pdf, .txt eller .md för engelsk översättning` (56 chars) becomes 82 chars when extended — over the 80-char invariant in FR-011 and the existing per-zone hint-copy cap test. What's the layout? → A: **Slash-separated, drop the `ett` article. Canonical hint copy: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för <suffix>` where `<suffix>` is the existing per-zone suffix (`sammanfattning`, `engelsk översättning`, `svensk översättning`, `punktlista`, `anonymisering`, `klarspråk`).** The longest resulting string (`engelsk översättning` suffix) is 67 chars — well under the 80-char cap with headroom for future formats. The format list reads as a single file-type group rather than a comma-separated enumeration; the slash makes it visually obvious that any one of these works. FR-011 updated below. The four spec 005 formats still come first to preserve user muscle memory; the three long-tail formats follow in `.rtf`, `.pages`, `.odt` order (lexicographic; matches the order they are introduced in FR-001/FR-003..FR-005).

- Q: RTF documents commonly carry `\pict` (embedded images) and `\object` (OLE blobs from Word) runs. "Best-effort" extraction needs a rule for what happens when the parser hits one. → A: **Skip the object/image run, continue extracting the surrounding plain text. The presence of one or more embedded objects in a `.rtf` does NOT trigger `RtfParseError` on its own.** Rationale: a 30-page legal brief that happens to include one embedded screenshot or one embedded Word equation should not fail wholesale — that defeats the "best-effort" framing of US-1 + US-2. The parser-level decision: when the RTF crate exposes the document as a stream of runs (text runs + object runs + control-word runs), the extractor takes only the text runs and the document-order-preserving whitespace between them. Tracked changes, headers, footers, and footnotes in `.rtf` follow the same "skip non-text runs" rule. FR-003 amended below to record this contract.

- Q: ODT files produced by LibreOffice and Word with collaborative editing carry `<text:change>` markup — insertions kept verbatim, deletions kept but marked. Translation / summary users see one of three views (accepted, rejected, all-text-flat). Which one does the extractor produce? → A: **Use the accepted/final view: insertions are present in the extracted text, deletions are removed.** Rationale: the user's mental model of "translate this document" or "summarise this document" is the document as it currently reads, not the editorial history. Producing the all-text-flat view would interleave deleted and inserted text and confuse the model; producing the rejected view would discard the user's most recent edits. The implementation skips any `<text:change-marker>` of kind `deletion` and includes any of kind `insertion` as plain text. FR-005 amended below.

- Q: Apple Pages supports sections (each with their own page setup and optional headers/footers). The extractor walks paragraph runs in document order — what's the join rule between sections? → A: **Double-newline between sections (`\n\n`); single-newline between paragraphs within a section (`\n`).** Rationale: matches how the existing `.docx` extractor handles page/section/paragraph boundaries (paragraphs joined with `\n`, section breaks rendered as a blank line) — keeps the model's input shape consistent across all seven input formats. The `.pages` extractor walks the bundled XML in document order, emits paragraph text joined with `\n`, and emits a blank line (effectively a second `\n`) whenever a `section` boundary is crossed. Headers, footers, and footnotes in `.pages` are extracted in document order at the location where they appear; they are NOT prefixed with `Sidhuvud:` / `Sidfot:` markers (model receives plain text). FR-004 amended below.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Drop a working .rtf into Sammanfatta (Priority: P1)

A Swedish law student has a course handout exported from TextEdit as `kursplan.rtf`. They drag it onto the **Sammanfatta** zone expecting the same flow they have for `.docx`. The zone extracts the text, sends it to the local model, and writes a sidecar result next to the source. Same state machine as spec 003 — `idle → dragover → processing → success` — no new states, no new modal, no new prompt.

**Why this priority**: This is the entire reason the spec exists. If a working `.rtf` does not "just work", the long-tail support adds zero user value and only adds maintenance cost.

**Independent Test**: Drop a 2-page `.rtf` file produced by macOS TextEdit onto the **Sammanfatta** zone. The zone transitions through `dragover → processing → success`, a sidecar result file appears next to the source, and the result opens automatically. No errors surface; no console warnings.

**Acceptance Scenarios**:

1. **Given** the model is `Klar` and the **Sammanfatta** zone is idle, **When** the user drops `kursplan.rtf` (extractable, ≤ 24,000 chars), **Then** the zone shows `Bearbetar dokumentet…`, the model receives the extracted plain text, and a sidecar result file is written and opened.
2. **Given** the model is `Klar` and any of the six zones is idle, **When** the user drops `case-notes.odt` (extractable, ≤ 24,000 chars), **Then** the zone behaves identically to the `.rtf` case above — same state machine, same success copy, same mirror-output rule.
3. **Given** the model is `Klar` and any of the six zones is idle, **When** the user drops `meeting.pages` (extractable Apple Pages bundle), **Then** the zone extracts the text from the bundled XML, the model receives the text, and a `.docx` sidecar is written (Pages is never written back).

---

### User Story 2 — Drop a corrupt or password-protected long-tail file (Priority: P1)

The same student drags `legacy.rtf` — a 1998-era RTF variant with control words `\rtf0` and embedded `\objemb` blobs the parser can't read — onto any zone. Or they drag a `.pages` bundle that's password-protected. Or they drag a corrupt `.odt` whose `content.xml` is missing. The zone must NOT show "Kunde inte läsa dokumentet" (the generic .docx error) and MUST NOT show "Filformatet stöds inte" (which would imply the user should give up). It MUST tell them the file's format explicitly — so they know it was tried, and so the error is searchable.

**Why this priority**: The whole "best-effort" framing depends on honest failure copy. A generic error makes the user think JuraDrop is broken; a named-format error makes the user understand "this `.pages` file in particular is the problem".

**Independent Test**: Drop a deliberately corrupt `legacy.rtf` file onto any zone. The zone transitions to `error` and shows the Swedish copy `Kunde inte läsa .rtf-filen` (or the format-specific equivalent for `.pages` / `.odt`). The model is NOT called; the sidecar Ollama process sees zero new HTTP traffic for this drop.

**Acceptance Scenarios**:

1. **Given** the model is `Klar` and any zone is idle, **When** the user drops a corrupt `.rtf` whose control-word parser raises, **Then** the zone shows `Kunde inte läsa .rtf-filen` and transitions back to `idle` after the standard error-display duration.
2. **Given** the model is `Klar` and any zone is idle, **When** the user drops a password-protected `.pages` bundle (zip-level encryption marker present), **Then** the zone shows `Kunde inte läsa .pages-filen` (and NOT the generic `Dokumentet är lösenordsskyddat` from FR-017 — the long-tail formats use the format-named error even for the password case, to keep the failure surface uniform across the long tail).
3. **Given** the model is `Klar` and any zone is idle, **When** the user drops an `.odt` whose `content.xml` is missing or malformed, **Then** the zone shows `Kunde inte läsa .odt-filen`.

---

### User Story 3 — Hint copy lists all seven formats (Priority: P2)

When the model is `Klar` and a zone is idle, the zone's hint copy lists every supported input format. Currently it reads `Släpp ett .docx, .pdf, .txt eller .md för …`. After spec 009 it must include `.rtf`, `.pages`, `.odt` too, so the user knows the long-tail formats are accepted without having to try them.

**Why this priority**: Discoverability. If the hint copy still says "docx, pdf, txt or md", the user assumes those four are the entire list and doesn't try the long-tail formats — and the spec's value is wasted.

**Independent Test**: With the model `Klar`, look at any of the six idle zones. The hint copy includes every one of the seven supported formats. The string fits within the existing zone visual budget (no horizontal overflow, no wrap-to-three-lines).

**Acceptance Scenarios**:

1. **Given** the model is `Klar`, **When** a zone is rendered in the `idle` state, **Then** the hint copy contains the substrings `.docx`, `.pdf`, `.txt`, `.md`, `.rtf`, `.pages`, `.odt`.
2. **Given** the spec 005 hint-copy contract (one hint per zone, Swedish-localised, ≤ 80 chars including punctuation), **When** the format list expands to seven items, **Then** every zone's hint copy still fits the 80-char cap.

---

### User Story 4 — Drop a non-supported extension (.doc, .epub, .html, .csv) (Priority: P3)

The user drags `old-format.doc` (legacy Word 97 — NOT `.docx`) onto a zone. Behavior must be **unchanged** from spec 005: the zone surfaces `Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt`. The long-tail spec must not silently widen the supported set, must not start guessing formats from content sniffing, and must not paper over real "no, we don't read that" cases with a format-named error.

**Why this priority**: Regression guard. The destructive tests in spec 003 + 005 verify that unsupported extensions fail closed. Spec 009 must keep that invariant.

**Independent Test**: Drop `legacy.doc` onto any zone. The zone shows the `InvalidFormat` Swedish copy, updated to list the seven supported formats. The format-named errors (`Kunde inte läsa .rtf-filen` etc.) are NOT triggered.

**Acceptance Scenarios**:

1. **Given** the model is `Klar`, **When** the user drops `report.doc` (Word 97 binary, not the supported `.docx`), **Then** the zone shows `Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt`.
2. **Given** the same precondition, **When** the user drops `mail.eml`, `book.epub`, `page.html`, or `data.csv`, **Then** the same `InvalidFormat` copy fires.

---

### Edge Cases

- **Empty extractable text**: an `.rtf`, `.pages`, or `.odt` parses cleanly but contains zero non-whitespace text → `EmptyText` (FR-018), not a format-named error. Same behavior as the existing `.docx` / `.pdf` empty-text path.
- **Text length > 24,000 chars**: same truncation rule as spec 005 — the first 24,000 chars are forwarded to the model; no error, no warning prefix beyond what spec 005 already injects.
- **`.pages` bundle that is actually a directory** (older macOS Pages versions saved Pages as a folder, not a zip): the dispatcher MUST detect this and treat it as `InvalidFormat` — JuraDrop only reads the modern single-file `.pages` bundle (zip with a `Index.zip` or `Index/Document.iwa` member). The directory-form `.pages` surfaces the standard "Filformatet stöds inte" message, NOT the format-named error, because there is nothing to attempt.
- **Mixed-case extensions** (`File.RTF`, `Notes.OdT`, `Letter.Pages`): all detected as their lowercase equivalent (per existing `detect_from_path` contract). No regression from spec 005.
- **`.rtf` produced by Microsoft Word 2003 (Windows-1252 encoded text inside RTF)**: must extract correctly. The RTF parser must respect the document's `\ansicpg` directive and use the existing `encoding_rs` cascade to decode high-byte text. Failure surfaces as `Kunde inte läsa .rtf-filen`.
- **`.odt` produced by LibreOffice with embedded fonts or macros**: the macros and fonts are ignored; the spec only extracts plain text from `content.xml` (`<text:p>` / `<text:h>` / `<text:span>` runs). No macro execution path; no font handling.
- **Password-protected `.pages` (iWork-encrypted)** and **password-protected `.odt`** (zip with encrypted `content.xml`): both fall under the format-named error per AS-2 — JuraDrop does NOT prompt for a password.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST extend `InputFormat` with three new variants: `Rtf`, `Pages`, `Odt`. The existing four variants (`Docx`, `Pdf`, `Txt`, `Md`) MUST remain unchanged in name, serde rename, and semantics.
- **FR-002**: System MUST detect `.rtf`, `.pages`, `.odt` from the lowercase file extension (mirror of existing `detect_from_path`). Mixed-case (`.RTF`, `.Pages`, `.ODT`) MUST be normalised before dispatch.
- **FR-003**: System MUST extract plain text from a well-formed `.rtf` file using a pure-Rust crate (no shelling out to `unoconv`, `pandoc`, `textutil`, or any system binary). License must be MIT or Apache-2.0. Per the auto-picked clarification: embedded `\pict` and `\object` runs (images, OLE blobs) MUST be skipped silently — their presence does NOT trigger `RtfParseError`. The extractor takes only the text runs in document order; headers, footers, footnotes, and tracked-change markup follow the same "skip non-text" rule.
- **FR-004**: System MUST extract plain text from a well-formed `.pages` file by reading the zip bundle (Apple Pages 5+ format — single-file zip with a `Index.zip` or `Index/Document.iwa` member). The existing `zip = "0.6"` dep from spec 005 MUST be reused — no second zip dep. Per the auto-picked clarification: the extractor MUST join paragraphs with `\n` and sections with `\n\n` (double-newline). Headers, footers, and footnotes are extracted in document order at their visual location without any `Sidhuvud:` / `Sidfot:` prefix — the model receives plain text only.
- **FR-005**: System MUST extract plain text from a well-formed `.odt` file by reading the zip bundle's `content.xml` and concatenating `<text:p>`, `<text:h>`, and `<text:span>` runs in document order. Pure-Rust XML parser only. Per the auto-picked clarification: tracked-change markup MUST be resolved to the accepted/final view — `<text:change-marker>` of kind `insertion` is included as plain text, `<text:change-marker>` of kind `deletion` is dropped. The extracted text reflects the document as it currently reads, not the editorial history.
- **FR-006**: System MUST emit `ZoneFailure::RtfParseError`, `ZoneFailure::PagesParseError`, `ZoneFailure::OdtParseError` (one variant per long-tail format) when extraction fails for any reason — corruption, encryption, exotic dialect, malformed XML, unreadable bundle, missing zip members. The Swedish copy MUST name the format explicitly.
- **FR-007**: The Swedish copy for the three new failure variants MUST follow the existing pattern (`Kunde inte läsa <ext>-filen`), each ≤ 80 chars, no English prefix, non-empty. Exact strings: `Kunde inte läsa .rtf-filen`, `Kunde inte läsa .pages-filen`, `Kunde inte läsa .odt-filen`.
- **FR-008**: For long-tail formats, the password-protected branch MUST NOT surface `ZoneFailure::PasswordProtected` (FR-017 from spec 003). Instead, the format-named parse-error variant MUST fire. Rationale: the long-tail formats are best-effort; collapsing every failure mode into one error per format keeps the user message uniform and avoids false promises ("if you remove the password it'll work").
- **FR-009**: Output mirror rule for long-tail formats:
  - `.rtf` input → `.rtf` sidecar output **if** a pure-Rust writer is available (see Assumptions). Otherwise → `.docx` sidecar (same fallback as PDF → DOCX from spec 005).
  - `.pages` input → `.docx` sidecar (always). JuraDrop MUST NOT write back to the proprietary Apple Pages bundle format under any circumstances.
  - `.odt` input → `.odt` sidecar **if** a pure-Rust writer is available. Otherwise → `.docx` sidecar.
- **FR-010**: The 24,000-char truncation cap from spec 005 (FR-006) MUST apply uniformly across all seven input formats — no special-casing for the long-tail set.
- **FR-011**: Hint copy in every zone MUST list all seven supported formats in the canonical order `.docx, .pdf, .txt, .md, .rtf, .pages, .odt`. Per the auto-picked clarification: the format list MUST be slash-separated (no commas, no `eller` connector inside the file-type group) and the `ett` article MUST be dropped. Canonical hint copy: `Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för <suffix>` where `<suffix>` is the existing per-zone suffix (`sammanfattning`, `engelsk översättning`, `svensk översättning`, `punktlista`, `anonymisering`, `klarspråk`). Every per-zone hint string MUST remain ≤ 80 chars (the longest suffix `engelsk översättning` yields 67 chars).
- **FR-012**: The `InvalidFormat` Swedish copy from `ZoneFailure::InvalidFormat` MUST be updated to list all seven supported formats, while remaining ≤ 80 chars: `Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt`.
- **FR-013**: Cross-language drift fixture (`src-tauri/tests/fixtures/zone-error-strings.json`) MUST gain three new keys (`rtf_parse_error`, `pages_parse_error`, `odt_parse_error`) and the updated `invalid_format` value. Both the Rust drift test and the TS drift test MUST assert against this single fixture.
- **FR-014**: NO new outbound network calls. Long-tail extraction is purely local. The Tauri allowlist for the network plugin MUST NOT gain any new origin.
- **FR-015**: NO new dependencies that pull in C/C++ via FFI, link to system libraries, or shell out to system binaries. Pure-Rust crates only. License audit (MIT / Apache-2.0 / dual) MUST be recorded in `plan.md` research notes.
- **FR-016**: Drag-over format-validity check (the brief preview when the user is mid-drag but hasn't released yet) MUST accept `.rtf`, `.pages`, `.odt` and show the same green-border affordance as `.docx`. Reject any other extension as today.
- **FR-017**: Telemetry surface remains zero — no counters, no log lines that include the file name, no spans that include the file path. The format-named parse-error variants MUST NOT include the source file's name in their `Display` impl (only the extension type).
- **FR-018**: All existing destructive-test invariants from spec 003/005 (multi-file drop, zone-busy, zone-disabled, model timeout, save-error) continue to hold for the three new formats — i.e. drop two `.rtf` files at once still fires `MultipleFiles`, not the format-named error.
- **FR-019**: The directory-form `.pages` bundle (legacy Apple Pages < v5 saved Pages as a folder, not a single file) MUST surface `InvalidFormat`, NOT the format-named error. Detection: if the dropped path is a directory and ends in `.pages`, route to `InvalidFormat` before any zip-extraction is attempted.
- **FR-020**: All seven format-detection branches MUST be unit-tested. Existing `input_format::tests` MUST gain `.rtf`, `.pages`, `.odt` rows in `detects_each_supported_lowercase_extension`, `detects_uppercase_and_mixed_case_extensions`, and `rejects_unsupported_extensions` (the third test gets new "still rejected" rows like `.doc`, `.epub`).

### Key Entities

- **InputFormat (extended)**: enum of supported input formats. Spec 009 extends from 4 variants to 7 (`Docx`, `Pdf`, `Txt`, `Md`, `Rtf`, `Pages`, `Odt`). Serde rename remains `lowercase`.
- **OutputFormat (extended)**: enum of writable output formats. Spec 009 extends to cover `.rtf` and `.odt` writers if available; `.docx` remains the universal fallback. Mirror rule from FR-009.
- **ZoneFailure (extended)**: enum of Swedish error categories. Spec 009 adds three variants (`RtfParseError`, `PagesParseError`, `OdtParseError`), each ≤ 80 chars, snake_case serde tag for TS mirror.
- **Long-tail extractor**: per-format module (`rtf_extract.rs`, `pages_extract.rs`, `odt_extract.rs`) that takes a file path and returns either `Ok(extracted_text: String)` or `Err(ZoneFailure)`. Mirrors spec 005's `pdf_extract`, `txt_extract`, `md_extract` shape.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A 2-page `.rtf` exported from TextEdit, dropped onto **Sammanfatta**, produces a sidecar result within the same wall-clock budget as a 2-page `.docx` ± 25 % (text-extraction cost should be negligible compared to model inference).
- **SC-002**: A 2-page `.pages` document, dropped onto any zone, produces a `.docx` sidecar within the same budget. (Wall-clock budget shared with SC-001; mirrors spec 005 SC-001.)
- **SC-003**: 100 % of corrupted long-tail files in the destructive test fixture set (`legacy.rtf`, `password.pages`, `missing-content.odt`, `truncated.odt`, `embedded-objects.rtf`) surface the format-named Swedish error variant and do NOT surface `Kunde inte läsa dokumentet`, `Dokumentet är lösenordsskyddat`, or any uncaught panic.
- **SC-004**: 100 % of unsupported extensions (`.doc`, `.epub`, `.html`, `.csv`, `.eml`) continue to surface `InvalidFormat` with the updated seven-format copy. No regression from spec 005.
- **SC-005**: Cross-language drift test (Rust ↔ TS) passes for all 13 `ZoneFailure` variants (existing 11 from spec 005 + the 3 new long-tail variants). Update to the `invalid_format` copy propagates atomically to both languages via the single fixture.
- **SC-006**: All zone hint-copy strings remain ≤ 80 chars after extending the format list to seven entries. The check runs in the existing hint-copy invariant test.
- **SC-007**: Zero new outbound network surface. Verified by re-running the Tauri allowlist audit and grepping for `reqwest::Client`, `ureq::`, `surf::`, or any new HTTP-client import outside the existing updater + sidecar modules.
- **SC-008**: License audit confirms every new crate is MIT, Apache-2.0, or dual. Recorded in `plan.md`. Zero GPL or copyleft dependencies.

## Assumptions

- A pure-Rust RTF parser exists with a stable enough API to extract plain text from common RTF dialects (TextEdit RTF, Word 2003 RTF, LibreOffice RTF). Candidates to evaluate in `research.md`: `rtf-parser`, `rtf-grimoire`, `rtfparse`. If none of them handles the three reference dialects, the spec's RTF support degrades to "always shows `Kunde inte läsa .rtf-filen`" — discoverable as a long-tail format in the hint copy, never succeeding in practice. The user has accepted this as best-effort.
- A pure-Rust ODT extractor strategy via the existing `zip = "0.6"` crate + `quick-xml` (or equivalent pure-Rust XML parser) is feasible without new C bindings. ODT's `content.xml` is well-documented OASIS standard; the implementation cost is in the XML walk, not the format.
- `.pages` files saved by Apple Pages v5 (2013) and later are single-file zip bundles. The directory-form `.pages` (pre-v5) is rare enough in 2026 to treat as `InvalidFormat` rather than write a second extractor for it.
- The existing 24,000-char truncation cap from spec 005 is the correct upper bound for the long-tail formats too. No format-specific tuning.
- No pure-Rust RTF *writer* with a stable API exists at acceptable quality. The implementation will likely fall back to `.docx` sidecar for `.rtf` input under FR-009; the writer-availability check happens in `research.md`. (If a writer turns up, FR-009 implementation switches to use it without a spec change.)
- No pure-Rust ODT *writer* with a stable API exists at acceptable quality. Same fallback to `.docx`.
- No new IPC channels, no new Tauri commands, no new front-end state — the existing per-zone `juradrop://zone/<slug>` event channels and the existing `DropZone` React component handle every state transition unchanged.
- The Allium drift baseline (`spec.allium`) needs three new `value` declarations (one per format-named error) and an updated `InputFormat` entity. No new state machine, so the existing `state_machine` block from spec 003 is unchanged.
- The light pipeline track is correct: this is a UI/parser feature, single actor, no concurrency, no new states. `/tla` will be skipped unless `/speckit.analyze` surfaces a state-machine concern.
