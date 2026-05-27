# Feature Specification: Additional input formats (.pdf, .txt, .md)

**Feature Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`)

**Created**: 2026-05-27

**Status**: Draft

**Input**: User description: Extend the six drop zones (spec 004) to accept `.pdf`, `.txt`, and `.md` files in addition to `.docx`. The dispatch pipeline, ZoneId routing, system prompts, single-flight per-zone slot, Redacted prompt handling, atomic write, cancel affordance, disabled gate, and Swedish error states from specs 003 and 004 are UNCHANGED. Only two things change: (1) text extraction handles four input formats instead of one, and (2) the sidecar output mirrors the input format. Sidecar suffix per ZoneId (spec 004) is preserved; the extension follows the input (with the .pdf → .docx exception because writing a polished PDF is out of scope). Format detection is by lowercase extension only — no magic-byte sniffing. The 24,000-UTF-8-char truncation cap from spec 003 FR-019 applies to all four formats. Privacy invariant from spec 003 holds verbatim: no document content leaves the Mac, every prompt is wrapped in `Redacted<String>` end-to-end, the only outbound traffic remains the Ollama localhost call + initial model pull + Tauri updater.

## Clarifications

### Session 2026-05-27 (auto-picked recommendations per `.claude/settings.json`)

- Q: When pdf-extract returns text for some pages but fails on others (partial extraction — common for PDFs with mixed text + scanned regions), should the sidecar use the partial text, refuse, or include a Swedish notice? → A: **Partial text + Swedish notice paragraph.** The dispatch uses whatever text pdf-extract returned. If pdf-extract reported per-page errors OR if the extracted text comes from fewer than 100% of the source pages, the sidecar writer prepends a Swedish notice paragraph (separate from the FR-019 truncation notice) reading "Delar av PDF-filen kunde inte läsas — resultatet kan vara ofullständigt.". Honest failure state (Principle 7 from CLAUDE.md) — the user knows the output is partial and can decide whether to act on it. Refusing a mostly-good extraction is worse than surfacing the gap honestly.
- Q: When UTF-8 decoding of a `.txt` or `.md` file fails, how do we decide between Windows-1252 fallback and the `UnsupportedEncoding` error? → A: **BOM-first, then strict UTF-8, then Windows-1252.** Extraction reads the first 4 bytes and detects BOMs: UTF-8 BOM (0xEF BB BF) is stripped and the rest is decoded as UTF-8. UTF-16 LE/BE BOM (0xFF FE / 0xFE FF) maps directly to `UnsupportedEncoding` — no further attempt. UTF-32 BOMs same. If no BOM, attempt UTF-8 strict decode. If UTF-8 strict fails (any invalid byte sequence), fall back to Windows-1252 decode (which is total — every byte 0x00–0xFF maps to a character). Windows-1252 always succeeds, so no third error path is needed at v1. Predictable, two-pass, no heuristic thresholds. Files truly in GB18030/Shift-JIS will decode as Windows-1252 garbage — operator error documented in the edge cases.
- Q: What is the boundary between the new `NoExtractableText` error (image-only PDFs) and the existing spec 003 `EmptyText` error (whitespace-only documents)? → A: **`NoExtractableText` is PDF-only; `EmptyText` is whitespace-only across all formats.** `NoExtractableText` fires ONLY when the file is a `.pdf`, pdf-extract returned zero bytes (no text content stream at all), and the file has ≥ 1 page. `EmptyText` fires when extraction succeeded but the result is whitespace-only after trim — for any of the four formats. Different root causes → different errors → different recovery actions (re-export with text layer vs. add some text to the document). For PDFs that have a text content stream but it is whitespace-only, `EmptyText` wins.
- Q: pdf-extract synthesizes line breaks for column/page boundaries that don't correspond to logical paragraph breaks. Should the extracted PDF text be normalised before being passed to the model? → A: **Conservative whitespace collapse: 3+ consecutive blank lines → 2.** No paragraph-detection heuristics. No line-wrapping reflow. The extractor runs a single pass that collapses runs of three or more blank lines down to exactly two (preserving paragraph breaks while killing page-break noise). Single and double blank lines are passed through unchanged. Trailing whitespace per line is preserved (some legal documents use it for alignment). The model sees a slightly cleaner version of pdf-extract's output without losing structural signal. Same rule applies to all four input formats — Markdown's blank-line conventions survive.
- Q: How are YAML/TOML frontmatter blocks at the top of a `.md` file handled — passed into the prompt as raw, stripped before sending, restored on output? → A: **Strip before send, restore on write.** The extractor detects a leading frontmatter block (`---\n…\n---\n` for YAML, `+++\n…\n+++\n` for TOML), extracts it into a side variable, and feeds ONLY the body Markdown to the model. The `.md` writer prepends the original frontmatter block verbatim to the sidecar output (before the spec FR-014 H1 header). Rationale: the model is unreliable at preserving structured frontmatter (it drops fields, invents new ones, reformats keys). Strip + restore guarantees the user's Obsidian/Bear/Hugo tags survive the round-trip byte-identical. If the model accidentally produces its own frontmatter in the body, that is left as-is (treated as part of the model's content choice).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Summarise a court ruling delivered as PDF (Priority: P1)

A Swedish law student receives a 12-page tingsrätt judgment as a `.pdf` (the standard delivery format from Swedish courts). They drag the PDF onto the Sammanfatta zone. Within a minute a sidecar `<stem>.sammanfatta.docx` appears next to the original, opens in Word, and contains a faithful Swedish summary. The original PDF is byte-identical to before the drop.

**Why this priority**: PDF is the single most common format for Swedish legal documents — court rulings, prop. (regeringspropositioner), SOU reports, and Riksdagen documents are all PDFs. Without `.pdf` support, the student is forced to convert every document through a third-party tool before they can use JuraDrop, which defeats the zero-friction value proposition and pushes them back to the cloud-LLM workflow the app exists to replace.

**Independent Test**: With the AI in `Klar`, drop a multi-page text-based `.pdf` on the Sammanfatta zone. Confirm the sidecar appears as `<stem>.sammanfatta.docx`, contains a Swedish summary of the PDF's content, opens cleanly in Word, and the original `.pdf` is byte-identical (SHA-256 match).

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a text-based `.pdf` sits on disk, **When** the user drops it on any of the six zones, **Then** the zone enters Processing, the text is extracted from the PDF, the per-zone system prompt runs against `gemma3:4b`, and a `.docx` sidecar is written and opened within 60 s.
2. **Given** the PDF is password-protected (encrypted with an open password), **When** the user drops it on any zone, **Then** the zone transitions to Error with the existing Swedish `PasswordProtected` copy ("Filen är lösenordsskyddad — öppna och spara om utan lösenord."). No sidecar is written.
3. **Given** the PDF contains only scanned page images (no embedded text layer at all), **When** the user drops it on any zone, **Then** the zone transitions to Error with the new Swedish `NoExtractableText` copy ("Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än."). No sidecar is written.
4. **Given** the PDF has more than 24,000 UTF-8 characters of extractable text, **When** the user drops it on any zone, **Then** the extracted text is truncated to the cap, the sidecar is written with the existing spec 003 truncation notice paragraph, and the model still produces an output based on the truncated input.

---

### User Story 2 — Anonymise a `.txt` case note (Priority: P1)

The student types their case notes as plain `.txt` in TextEdit (Plain Text mode), with names, personnummer, and addresses. Before sharing the notes in a study chat, they drag the `.txt` onto the Anonymisera zone. Within seconds a sidecar `<stem>.anonymiserad.txt` appears next to the original, containing the same notes with every personal identifier replaced with a neutral placeholder. The original `.txt` is byte-identical.

**Why this priority**: Plain text is the lowest-friction input format and the natural choice for free-form case notes typed during lectures or while reading. Many Swedish law students use TextEdit/Notes/VS Code for ad-hoc note-taking. The anonymisation use case is the load-bearing privacy story for spec 005 — these notes contain real client information.

**Independent Test**: Create a `.txt` file with three made-up Swedish names + a personnummer. Drop it on Anonymisera. Confirm the sidecar `<stem>.anonymiserad.txt` contains "Person A" (or similar) where each name was, contains no occurrence of the original names, opens cleanly in any text editor, and the original `.txt` is byte-identical.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a UTF-8 `.txt` file sits on disk, **When** the user drops it on any zone, **Then** the file is read as UTF-8 (BOM stripped if present), the per-zone prompt runs, and a `.txt` sidecar is written and opened within 30 s for a small file (< 500 lines).
2. **Given** the `.txt` is saved in Windows-1252 (legacy Mac/PC encoding common in older legal documents), **When** the user drops it on any zone, **Then** the file is decoded with a Windows-1252 fallback, processed normally, and the sidecar is written.
3. **Given** the `.txt` is saved in UTF-16 (or any encoding that is neither UTF-8 nor Windows-1252), **When** the user drops it on any zone, **Then** the zone transitions to Error with the new Swedish `UnsupportedEncoding` copy ("Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen."). No sidecar is written.
4. **Given** the user dropped on Anonymisera, **When** the sidecar `.txt` is generated, **Then** the file starts with a single comment-style header line (`# <basename> — Anonymisera — <YYYY-MM-DD>`), followed by a blank line, the model body, a blank line, and the spec 004 FR-013 disclaimer prefixed with `# `.

---

### User Story 3 — Simplify a Markdown study brief (Priority: P2)

The student writes a study brief in Markdown for personal revision. They drop the `.md` onto Förenkla. Within a minute a sidecar `<stem>.forenkla.md` appears next to the original — same Markdown structure (headings, lists, blockquotes, emphasis), but with the legal jargon explained in plain Swedish. The original `.md` is byte-identical.

**Why this priority**: Markdown is becoming the dominant note format for students using Obsidian, Bear, or VS Code. Preserving the Markdown syntax on the way through Ollama means the student's notes stay editable in their existing workflow — they don't lose the structure they built. Lower priority than PDF and TXT because Markdown is currently used by a smaller (but rapidly growing) subset of the user base.

**Independent Test**: Create a `.md` file with a heading, a bullet list, an emphasised word, and a Swedish legal jargon term ("kärande", "svarande"). Drop it on Förenkla. Confirm the sidecar `<stem>.forenkla.md` keeps the heading + list + emphasis structure, opens cleanly in any Markdown previewer (Obsidian, GitHub, VS Code preview), and explains the jargon parenthetically in plain Swedish.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and a `.md` file sits on disk, **When** the user drops it on any zone, **Then** the file is read as UTF-8 (BOM stripped if present), the **raw Markdown syntax** (asterisks, hashes, lists, links) is passed into the prompt unchanged, the per-zone prompt runs, and a `.md` sidecar is written and opened within 60 s.
2. **Given** the user dropped on Förenkla, **When** the sidecar `.md` is generated, **Then** the file starts with a Markdown H1 (`# <basename> — Förenkla`) followed by a subtitle blockquote (`> <YYYY-MM-DD>`), the model body, and the spec 004 FR-014 disclaimer formatted as a Markdown blockquote (`> **OBS!** …`).
3. **Given** the user dropped on Punktlista, **When** the sidecar `.md` is generated, **Then** the model output preserves Markdown bullet syntax (`- ` or `* `) on every bullet line, so the file renders as a real bulleted list in any Markdown viewer.

---

### User Story 4 — Drop an unknown extension (Priority: P3)

The student drops a file with an extension JuraDrop doesn't recognise (`.rtf`, `.pages`, `.odt`, `.html`, anything else) on any zone. The zone shows the existing `UnsupportedFormat` Swedish error within 100 ms — with the message updated to list all four supported formats. The file is not touched.

**Why this priority**: Edge case for the existing error path. Already wired through the `UnsupportedFormat` variant from spec 003 — only the copy needs an update so the user sees the actual supported list (`.docx, .pdf, .txt, .md`) instead of just `.docx`. Adding to the spec for completeness and to surface a destructive test case.

**Independent Test**: Drop a `.rtf` (or any unsupported extension) on any zone. Confirm the zone transitions directly to Error with the updated Swedish copy listing all four supported formats. The original file is byte-identical.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar`, **When** the user drops a `.rtf` (or `.pages`, or any other unsupported extension) on any zone, **Then** the zone transitions to Error with the updated Swedish copy "Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md." within 100 ms.
2. **Given** the user drops a file with a recognised extension in the WRONG case (e.g. `MyDoc.PDF` instead of `mydoc.pdf`), **When** the user drops it, **Then** the file is accepted — extension matching is case-insensitive — and processed normally.

---

### User Story 5 — Updated zone hints visible at idle (Priority: P3)

When the AI is `Klar` and all zones are idle, each of the six zones shows an updated Swedish hint mentioning all four supported formats (e.g. "Släpp ett .docx, .pdf, .txt eller .md för sammanfattning"). The hints stay within the 80-character SwedishCopy invariant from spec 003 and remain in lock-step across the Rust `ZoneId::hint_copy()`, the TypeScript `ZONE_IDENTITIES` table, and the shared `zone-identity.json` fixture.

**Why this priority**: Without updated hints the user has no way to discover the new formats. The drag-drop happy path doesn't show an error for accepted formats, so the hint is the only discoverability surface. Low priority because the change is purely a string update, but the cross-language drift test (T035 from spec 004) MUST stay green.

**Independent Test**: Launch the app in `Klar` state. Confirm each of the six zone tiles displays a hint that mentions `.docx`, `.pdf`, `.txt`, and `.md` (in that order or equivalent). Confirm each hint is ≤ 80 characters. Run the parametric `zone_parametric.rs` + `DropZone.identity.test.tsx` tests — both must still pass.

**Acceptance Scenarios**:

1. **Given** the AI is `Klar` and all six zones are idle, **When** the user looks at any zone tile, **Then** the hint text mentions all four supported extensions (in one form or another) and remains under 80 characters.
2. **Given** the Rust ZoneId::hint_copy() returns the updated hint, **When** the Rust parametric test + the TS identity test run, **Then** both still match the shared fixture byte-for-byte (T035 drift detection from spec 004 stays green).

---

### Edge Cases

- **PDF with text + scanned images mixed**: the embedded text is extracted normally — the scanned regions are silently ignored. No special handling, no warning. The model gets whatever text the PDF parser found.
- **PDF with form fields filled in**: form values are NOT extracted (pdf-extract reads content streams, not AcroForm fields). The user sees only the static text. Documented as a known limitation; OCR + form support are out of scope.
- **`.txt` that is binary garbage** (random bytes, not actually text): UTF-8 decoding fails, Windows-1252 fallback succeeds (since Windows-1252 maps every byte 0x00–0xFF), but the resulting "text" is gibberish. The model produces gibberish back. Acceptable — the user dropped a binary file with a `.txt` extension, this is operator error.
- **`.txt` containing null bytes (0x00)**: null bytes are stripped during extraction (same way the PDF extractor strips them), since Ollama's HTTP body would otherwise truncate at the null.
- **Empty `.txt` or `.md`** (zero bytes or whitespace-only): mapped to the existing `EmptyText` error from spec 003 — "Dokumentet innehåller ingen text."
- **`.md` with frontmatter** (YAML between `---` lines, or TOML between `+++` lines, at the top): the extractor captures the frontmatter into a side variable BEFORE sending the body to the model (per FR-008a). The `.md` writer prepends the original frontmatter verbatim to the sidecar. The model never sees the frontmatter, which guarantees byte-identical round-trip preservation regardless of model behaviour.
- **Mixed-case extension** (`.PDF`, `.Md`, `.TxT`): lowercased before matching; treated identically to the lowercase form.
- **No extension at all** (the file is named `Dokument` with no dot): the zone transitions to Error with the `UnsupportedFormat` copy. No magic-byte sniffing.
- **Two extensions** (`mydoc.tar.gz`): only the last extension counts. `.gz` → `UnsupportedFormat`.
- **Symlinks pointing to a PDF/TXT/MD**: the symlink target is read. The sidecar is written next to the symlink (not next to the target). Matches spec 003's behaviour for `.docx`.
- **Filenames containing the zone suffix** (e.g. `mydoc.sammanfatta.docx` already on disk): the collision-suffix rule from spec 003 FR-006 applies — the new sidecar is named `mydoc.sammanfatta.YYYY-MM-DD-HHMMSS.docx`.
- **PDF saved with Adobe encryption but no actual open-password set** (permissions-only encryption): mapped to `PasswordProtected` to be safe — text extraction may still partially work but is unreliable; the conservative choice is to refuse and tell the user to re-export.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST continue to accept `.docx` input on every zone with byte-identical behaviour to spec 003 (no regression). The existing `.docx` extractor, writer, and tests remain untouched.
- **FR-002**: System MUST extract text from `.pdf` input using the pure-Rust `pdf-extract` crate (or equivalent pure-Rust extractor) that requires no external binaries, no network, and no shell-out. Null bytes are stripped from the extracted text; CRLF is normalised to LF. Runs of three or more consecutive blank lines are collapsed to exactly two blank lines (paragraph breaks preserved, page-break noise killed); single and double blank lines pass through unchanged. The same blank-line collapse rule applies to `.txt` and `.md` extractors for consistency.
- **FR-002a**: When pdf-extract reports per-page extraction errors OR the extraction recovers text from fewer than 100% of the source PDF pages, the dispatch MUST mark the `ExtractedText` as partial (new boolean field `was_partial`). The sidecar writer MUST prepend a Swedish partial-extraction notice paragraph reading "Delar av PDF-filen kunde inte läsas — resultatet kan vara ofullständigt." separate from (and in addition to) the FR-019 truncation notice when present.
- **FR-003**: System MUST detect encrypted PDFs at extraction time and map them to the existing `PasswordProtected` Swedish error from spec 003 ("Filen är lösenordsskyddad — öppna och spara om utan lösenord."). No sidecar is written.
- **FR-004**: System MUST detect PDFs where `pdf-extract` recovered **zero text from every page** (image-only scanned PDFs with no embedded text content stream on any page, despite having ≥ 1 page) and map them to a NEW `NoExtractableText` Swedish error: "Hittade ingen text att läsa i PDF-filen — skannade bilder stöds inte än." Detection uses `pdf_extract::extract_text_from_mem_by_pages` — when every entry in the returned `Vec<String>` is whitespace-only AND the source has ≥ 1 page → `NoExtractableText`. No sidecar is written. OCR is explicitly out of scope. `NoExtractableText` is PDF-only and fires BEFORE the FR-016 truncation cap — a PDF where SOME pages have text and others don't is NOT `NoExtractableText` (it's a partial extraction, tracked via `was_partial` per FR-002a). If `pdf-extract` recovered any text from any page but the joined result is whitespace-only after the full clean pass, that maps to the existing `EmptyText` error.
- **FR-005**: System MUST extract text from `.txt` input following a deterministic BOM-first, then-strict-UTF-8, then-Windows-1252 cascade: (a) read the first 4 bytes; if a UTF-8 BOM (`EF BB BF`) is present, strip it and decode the remainder as UTF-8; (b) if a UTF-16 LE/BE or UTF-32 LE/BE BOM is present, map to `UnsupportedEncoding` immediately — no further decode attempts; (c) otherwise, attempt strict UTF-8 decode; (d) if strict UTF-8 fails on any byte sequence, decode the original bytes as Windows-1252 (a total encoding — every byte 0x00–0xFF maps to a character, so this step always succeeds). Files truly in GB18030/Shift-JIS will decode as Windows-1252 garbage — operator error.
- **FR-006**: The Windows-1252 fallback from FR-005 covers legacy Swedish legal documents from older Mac/PC systems where UTF-8 was not the default. No heuristic threshold (replacement-character ratio, etc.) gates the fallback — the strict UTF-8 decode either succeeds or fails, and on failure Windows-1252 takes over.
- **FR-007**: System MUST map `.txt` and `.md` files that begin with a UTF-16 LE BOM (`FF FE`), UTF-16 BE BOM (`FE FF`), UTF-32 LE BOM (`FF FE 00 00`), or UTF-32 BE BOM (`00 00 FE FF`) to the NEW `UnsupportedEncoding` Swedish error: "Tecken-kodning stöds inte — spara filen som UTF-8 och försök igen." Detection happens before any decode attempt — BOMs are sniffed from the leading bytes. No sidecar is written.
- **FR-008**: System MUST extract text from `.md` input following the same BOM-first/UTF-8/Windows-1252 cascade as FR-005. The raw Markdown syntax (asterisks, hashes, list markers, links, blockquotes, emphasis) MUST be passed into the prompt unchanged — Markdown is NOT stripped to plain text before being sent to the model.
- **FR-008a**: When the `.md` input begins with a YAML frontmatter block (a `---` fence, content, and a closing `---` fence on its own line within the first 8 KB of the file) OR a TOML frontmatter block (`+++` fences), the extractor MUST: (a) capture the entire frontmatter block (including the fences and the trailing newline) into a side variable kept alongside the `ExtractedText`, and (b) feed ONLY the body Markdown (everything after the closing fence) to the model. The `.md` sidecar writer MUST prepend the captured frontmatter block verbatim to the output BEFORE the FR-014 H1 header. If no frontmatter block is detected, this rule is a no-op. The model is never instructed to preserve frontmatter, since strip-and-restore guarantees byte-identical preservation regardless of model behaviour.
- **FR-009**: System MUST detect the input format by lowercase file extension only. The extension `.pdf` (in any case) maps to PDF, `.txt` to text, `.md` to Markdown, `.docx` to Word. No magic-byte sniffing.
- **FR-010**: System MUST reject any other extension (or no extension) with the existing `UnsupportedFormat` error from spec 003, with the copy UPDATED to list all four supported formats: "Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md."
- **FR-011**: System MUST mirror the input extension to the output extension with one exception: `.pdf` input produces `.docx` output (because writing a polished PDF requires font embedding and layout that are out of scope). Specifically: `.docx` → `.docx`, `.pdf` → `.docx`, `.txt` → `.txt`, `.md` → `.md`.
- **FR-012**: System MUST construct the sidecar filename as `<stem>.<zone_suffix>.<ext>` where `<zone_suffix>` is the per-ZoneId suffix from spec 004 (e.g. `sammanfatta`, `anonymiserad`) and `<ext>` is the mirrored output extension from FR-011. The FR-006 timestamp-collision rule from spec 003 applies unchanged.
- **FR-013**: For `.txt` output, the sidecar MUST start with a single comment-style header line `# <basename> — <zone-title> — <YYYY-MM-DD>`, then a blank line, then the model body. For Anonymisera and Förenkla zones (FR-013/014 from spec 004), the sidecar MUST end with a blank line followed by the spec 004 disclaimer prefixed with `# `.
- **FR-014**: For `.md` output, the sidecar MUST start with a Markdown H1 header `# <basename> — <zone-title>` followed by a subtitle blockquote `> <YYYY-MM-DD>` and a blank line, then the model body. For Anonymisera and Förenkla zones, the sidecar MUST end with the spec 004 disclaimer formatted as a Markdown blockquote `> **OBS!** …`.
- **FR-015**: For `.docx` output (including `.pdf` → `.docx`), the sidecar MUST follow the existing spec 003/004 docx-writer behaviour unchanged: header paragraph, body paragraphs, truncation notice (if any), disclaimer paragraph (Anonymisera + Förenkla), spacer.
- **FR-016**: The 24,000-UTF-8-character truncation cap from spec 003 FR-019 MUST apply to all four input formats. Truncation happens after extraction on the raw text. For `.md` inputs the "raw text" being capped is the body AFTER the FR-008a frontmatter capture — the captured frontmatter block is preserved verbatim on the sidecar and is NOT counted against the 24,000-char cap. When truncation occurs, the existing Swedish truncation notice is written into the sidecar per the format's writer rules (paragraph for `.docx`, comment line for `.txt`, blockquote for `.md`).
- **FR-017**: System MUST update every zone's idle hint copy to mention all four supported formats. Hints remain ≤ 80 characters (SwedishCopy invariant from spec 003). Examples: "Släpp ett .docx, .pdf, .txt eller .md för sammanfattning"; "Släpp ett .docx, .pdf, .txt eller .md för anonymisering".
- **FR-018**: The shared `zone-identity.json` fixture, the Rust `ZoneId::hint_copy()` function, and the TypeScript `ZONE_IDENTITIES` table MUST stay in byte-for-byte lock-step. The T035 cross-language drift test from spec 004 MUST continue to pass after the hint copy update.
- **FR-019**: The privacy invariant from spec 003/004 MUST hold for every new format. Extracted text from `.pdf`, `.txt`, and `.md` MUST flow through the same `Redacted<String>` boundary as `.docx`. No new outbound network call, no telemetry of document content, no shell-out, no temp file containing extracted text that survives the dispatch.
- **FR-020**: The per-zone state machine, single-flight slot, cancel token, disabled gate (`UserVisibleStatus != Klar`), and event channel (`juradrop://zone/<slug>`) MUST remain byte-identical to spec 004 — the new formats only affect what `extract_text` does, not how the zone behaves.
- **FR-021**: All four input formats MUST honour the source-immutability invariant: SHA-256 of the input file before the drop MUST equal SHA-256 after the dispatch completes (success, error, or cancel). No format-specific code path is allowed to write back to the source.

### Key Entities *(include if feature involves data)*

- **InputFormat**: Discriminator for the four supported input formats (`docx`, `pdf`, `txt`, `md`). Resolved from the lowercase file extension. Drives which extractor and which writer are selected.
- **OutputFormat**: Discriminator for the three supported output formats (`docx`, `txt`, `md`). Derived from InputFormat via the FR-011 mirror rule (with the PDF→docx exception).
- **ExtractedText**: Extended from spec 003. New shape: `{ raw: Redacted<String>, was_truncated: bool, was_partial: bool, frontmatter: Option<String> }`. `was_partial` is true when pdf-extract recovered text from fewer than 100% of source pages (per FR-002a). `frontmatter` carries the captured YAML/TOML block for `.md` inputs (per FR-008a); None for every other format. The dispatch pipeline does not need to know which format produced the text — the writers consume the unified shape and act on the flags.
- **ZoneFailure** (extended): The existing variants from spec 003 (`PasswordProtected`, `UnsupportedFormat`, `EmptyText`, `Truncated`, `OllamaError`, `WriteFailure`, `Cancelled`) plus two NEW variants for spec 005: `NoExtractableText` (image-only PDF), `UnsupportedEncoding` (text file in an encoding other than UTF-8 or Windows-1252). Each new variant has its own Swedish copy and maps to the existing UI error state machine without state-machine changes.
- **MirroredHeader**: The per-format header that opens the sidecar (docx paragraph, txt comment line, md H1+blockquote). Same data points (basename, zone title, date) rendered three ways.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A 5-page text-based `.pdf` dropped on any of the six zones produces a `.docx` sidecar within 60 seconds (warm Ollama, `gemma3:4b`).
- **SC-002**: A 100-line `.txt` dropped on any zone produces a `.txt` sidecar within 30 seconds (warm Ollama, `gemma3:4b`). Smaller-than-docx files should be faster than docx because extraction is near-instant.
- **SC-003**: A 100-line `.md` with five Markdown features (headings, lists, emphasis, links, blockquotes) dropped on Förenkla produces a `.md` sidecar that preserves every Markdown feature when opened in a Markdown previewer (Obsidian, VS Code, GitHub).
- **SC-004**: 100% of dropped files matching the four supported extensions produce either a sidecar or a specific Swedish error from the existing error vocabulary (no generic "Ett fel uppstod" fallback).
- **SC-005**: Encrypted PDFs, image-only PDFs, UTF-16 `.txt` files, and `.rtf` / `.pages` / `.odt` files surface their specific Swedish error within 200 ms of the drop (detection is fast — no model round-trip required).
- **SC-006**: The spec 003 + spec 004 regression suites stay green after spec 005 ships — every test that passed before still passes. Source-immutability + privacy invariants hold for all four formats.
- **SC-007**: The cross-language drift test (T035 from spec 004) stays green after the hint copy update — Rust, TypeScript, and the shared fixture remain in lock-step.

## Assumptions

- Users drop files from local disk. Network-mounted files (SMB shares, iCloud Drive files that have not been downloaded) are handled by the OS — the path either resolves locally or the OS open-file call fails. JuraDrop does not need special handling for stub/placeholder iCloud files at v1.
- The 24,000-UTF-8-character truncation cap from spec 003 is sufficient for typical 5–15 page Swedish legal documents in all four formats. Longer documents will be truncated with the existing Swedish notice. Configurable per-format limits are deferred to spec 010 (settings panel).
- UTF-8 + Windows-1252 cover ≥ 99% of real-world Swedish `.txt` and `.md` files. Other encodings (UTF-16, ISO-8859-15, Mac Roman) are rare enough that surfacing a specific error and asking the user to re-save as UTF-8 is acceptable. Auto-detection of arbitrary encodings is not attempted at v1.
- `pdf-extract` (pure-Rust crate) is sufficient for text-based PDFs from Swedish courts, Riksdagen, and similar sources. OCR (for scanned PDFs without an embedded text layer) is explicitly out of scope and would require Tesseract or a similar binary — that is a separate spec if user demand exists.
- Markdown is consumed downstream by editors (Obsidian, VS Code, Bear, GitHub) that already understand standard CommonMark/GFM. JuraDrop does not need to render Markdown — only pass it through and embed a small header.
- `.rtf`, `.pages`, and `.odt` are long-tail formats listed in `.claude/docs/deployment.md`. They are deferred to spec 009 (long-tail-formats) where best-effort extractors will be added with degrade-to-Swedish-error behaviour. Spec 005 explicitly does NOT touch them.
- HTML, XML, JSON, and binary office formats (`.xls`, `.ppt`) are out of project scope at all — they are not legal-document delivery formats.
- The Ollama model (`gemma3:4b` default) accepts any UTF-8 prompt content, including raw Markdown syntax. The model is not instructed to "interpret" Markdown — it sees it as text and the user-facing system prompt for the zone is unchanged.
- The pdf-extract dependency's licence (MIT) is compatible with the project's MIT licence and is acceptable for distribution in the signed DMG.
- All four formats are read-only with respect to the source file. No format writes back to the source.

## Out of Scope

- OCR for scanned PDFs (a future "improve PDF support" spec if user demand exists)
- `.rtf`, `.pages`, `.odt` — deferred to spec 009 (long-tail-formats)
- HTML, XML, JSON, `.xls`, `.ppt`, `.key`, image formats — out of project scope
- User-configurable per-format truncation limits — spec 010 (settings panel)
- Two-way Markdown editor inside JuraDrop — out of project scope (the app stays drop-only)
- PDF authoring (writing `.pdf` output) — out of project scope; `.pdf` input always produces `.docx` output
- Magic-byte sniffing for format detection — extension is the contract
- Encoding auto-detection beyond UTF-8 → Windows-1252 fallback for text files
- Streaming extraction for very large files (> 24,000 UTF-8 chars) — truncation cap applies; full files are read into memory and truncated
- Per-format prompt customisation — the six zone prompts from spec 004 apply unchanged to every input format
