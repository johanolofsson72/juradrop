# Tasks: Additional input formats (.pdf, .txt, .md)

**Spec**: [spec.md](spec.md) · **Allium**: [spec.allium](spec.allium) · **Plan**: [plan.md](plan.md)

**Input**: Spec 005 expands the four-format input matrix on top of spec 004's six-zone dispatch. New extractors (`.pdf`, `.txt`, `.md`), new writers (`.txt`, `.md`), two new `ZoneFailure` variants, and lock-step hint-copy updates across Rust + TS + JSON fixture. State machine and per-zone event channels are byte-identical to spec 004.

Total tasks: 55 (8 phases). Track: **light** (no `/tla`).

---

## Phase 1 — Setup

- [x] T001 Add `pdf-extract = "0.7"` and `encoding_rs = "0.8"` to `src-tauri/Cargo.toml` `[dependencies]`. Run `cd src-tauri && cargo build` once to populate `Cargo.lock`. Verify no other deps are auto-bumped beyond a semver-patch.
- [x] T002 Create empty skeleton files (each with `// Spec 005 — placeholder` comment + module declaration): `src-tauri/src/zones/input_format.rs`, `src-tauri/src/zones/output_format.rs`, `src-tauri/src/zones/extract.rs`, `src-tauri/src/zones/pdf_extract.rs`, `src-tauri/src/zones/txt_extract.rs`, `src-tauri/src/zones/md_extract.rs`, `src-tauri/src/zones/txt_write.rs`, `src-tauri/src/zones/md_write.rs`. Add the new `mod` declarations to `src-tauri/src/zones/mod.rs` so the project still compiles.

---

## Phase 2 — Foundational (blocking for every user story)

- [x] T003 [P] Implement the `InputFormat` enum (variants `Docx`, `Pdf`, `Txt`, `Md` with `serde(rename_all = "lowercase")`) + the `detect_from_path(path) -> Option<Self>` associated function + the `as_str()` const fn + the `pub const ALL: [Self; 4]` constant, all in `src-tauri/src/zones/input_format.rs`. Add 4+ unit tests covering uppercase / mixed-case / unknown / no-extension paths.
- [x] T004 [P] Implement the `OutputFormat` enum (variants `Docx`, `Txt`, `Md`) + the `mirror_from(InputFormat) -> Self` const fn (with the PDF→DOCX exception) + the `as_str()` const fn, in `src-tauri/src/zones/output_format.rs`. Add 4 unit tests: one per input format → expected output.
- [x] T005 [P] Extend the existing `ExtractedText` struct in three explicit sub-steps:
  - (a) Define the new struct in `src-tauri/src/zones/extract.rs` with the two new fields `was_partial: bool` and `frontmatter: Option<String>` alongside the existing `raw: Redacted<String>` and `was_truncated: bool`.
  - (b) In `src-tauri/src/zones/docx_extract.rs`, delete the old struct definition and replace it with `pub use crate::zones::extract::ExtractedText;` so the spec 003 import path (`use crate::zones::docx_extract::ExtractedText;`) keeps working byte-identically.
  - (c) Grep for every existing `ExtractedText { ... }` literal in the codebase (`rg "ExtractedText\s*\{" src-tauri/src src-tauri/tests`) and update each to add `was_partial: false, frontmatter: None`. Run `cd src-tauri && cargo build` — every existing test must still compile.
- [x] T006 Implement the top-level `pub fn extract_text(path: &Path, format: InputFormat) -> Result<ExtractedText, ZoneFailure>` dispatcher in `src-tauri/src/zones/extract.rs`. Routes to `docx_extract::extract_text`, `pdf_extract::extract_text`, `txt_extract::extract_text`, or `md_extract::extract_text` based on `format`. Centralises the 24,000-UTF-8-char truncation cap + the 3+ blank-line collapse so each per-format extractor only needs to produce raw text.
- [x] T007 Add two new variants to `ZoneFailure` in `src-tauri/src/zones/errors.rs`: `NoExtractableText` and `UnsupportedEncoding`. Update the `swedish_copy()` match arm with the two new strings (per `contracts/error-vocabulary.md`). Also update the `UnsupportedFormat` arm to the new four-format copy `Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md.`.
- [x] T008 Update `src-tauri/src/zones/sidecar_path.rs` to accept `output_format: OutputFormat` and return `<stem>.<zone_suffix>.<output_format.as_str()>`. Modify `resolve_target` + `canonical_for` + `with_collision_suffix` signatures. The collision-timestamp rule from spec 003 FR-006 keeps the same shape but inserts before the extension.
- [x] T009 Update `src-tauri/tests/fixtures/zone-error-strings.json` to add `no_extractable_text` and `unsupported_encoding` keys + overwrite `unsupported_format` with the new four-format copy.
- [x] T010 Update `src/components/DropZone.errors.ts` to mirror the two new error keys + the updated `UnsupportedFormat` copy. Re-run the existing cross-language error-string drift test (added in spec 003) — must pass.
- [x] T011 Update `src-tauri/src/zones/mod.rs` to publicly re-export `InputFormat`, `OutputFormat`, `extract_text`, and the new error variants.
- [x] T012 [P] Add `src-tauri/tests/format_mirror.rs`: parametric test asserting `OutputFormat::mirror_from(input) == expected` for every variant of `InputFormat::ALL` (4 cases — Docx→Docx, Pdf→Docx, Txt→Txt, Md→Md). The PDF→DOCX exception is the one that must NOT drift.

---

## Phase 3 — US1: Summarise a court ruling delivered as PDF (P1)

**Story goal**: Drop a text-based `.pdf` on any zone; get a `.docx` sidecar within 60 s. Encrypted PDFs surface `PasswordProtected`. Image-only PDFs surface `NoExtractableText`. Partial extractions get a Swedish notice prepended.

**Independent test**: With AI in `Klar`, drop a text-based `.pdf` on Sammanfatta → `.docx` sidecar opens within 60 s, contains Swedish summary, source SHA-256 unchanged.

- [x] T013 [US1] Implement `pdf_extract::extract_text(path) -> Result<ExtractedText, ZoneFailure>` in `src-tauri/src/zones/pdf_extract.rs`. Strict step order (the NoExtractableText / EmptyText boundary depends on it): (1) read full file bytes; (2) probe encryption via `lopdf::Document::load_from(&bytes[..])` and inspect the trailer for `/Encrypt` — on present → `PasswordProtected`; (3) count pages via `lopdf::Document::get_pages().len()`; (4) call `pdf_extract::extract_text_from_mem(&bytes)` → `raw_text`; (5) **if `raw_text.is_empty()` AND pages ≥ 1 → `NoExtractableText`** (pre-trim check — this is the FR-004 boundary); (6) strip null bytes from `raw_text`; (7) normalise CRLF to LF; (8) if the result is whitespace-only AFTER trim → `EmptyText` (per the FR-004 clarification — `pdf-extract` returned content but it's all whitespace); (9) count `\n\n`-separated non-empty blocks → set `was_partial = blocks < pages` (conservative heuristic per research.md R-001); (10) return `ExtractedText { raw: Redacted(text), was_truncated: false, was_partial, frontmatter: None }`. The blank-line collapse + 24k truncation cap are applied by the top-level dispatcher, not here.
- [x] T014 [P] [US1] Create test fixtures: `src-tauri/tests/fixtures/sample.pdf` (2-page text-based PDF — generate via `pandoc` or check in a small known-good court PDF; ≤ 50 KB), `sample-encrypted.pdf` (any PDF re-encrypted via `qpdf --encrypt user owner 128 -- in.pdf out.pdf`), `sample-image-only.pdf` (single-page PDF from a screenshot via Preview Export). Document the generation steps in `tests/fixtures/README.md`.
- [x] T015 [P] [US1] Write `src-tauri/tests/pdf_extract.rs` integration tests: (a) happy-path extracts non-empty text from `sample.pdf`; (b) `sample-encrypted.pdf` returns `Err(ZoneFailure::PasswordProtected)`; (c) `sample-image-only.pdf` returns `Err(ZoneFailure::NoExtractableText)`; (d) garbage bytes return a parse error (not panic); (e) text-block count < page count sets `was_partial = true`; (f) truncation cap kicks in for synthetic > 24,000-char PDFs.
- [x] T016 [US1] Wire PDF into the top-level `extract::extract_text` dispatcher so `InputFormat::Pdf` routes through `pdf_extract::extract_text`. Add 1 unit test in `extract.rs` asserting the dispatch picks the right extractor.
- [x] T017 [US1] Extend `src-tauri/src/zones/docx_write.rs` to accept an `extracted: &ExtractedText` reference. Insert the partial-extraction notice paragraph (`Delar av PDF-filen kunde inte läsas — resultatet kan vara ofullständigt.`) BEFORE the existing truncation notice when `extracted.was_partial == true`. Keep the existing disclaimer paragraph for Anonymisera + Förenkla in place. The header, meta paragraph, body, and spacer remain unchanged.
- [x] T018 [P] [US1] Unit tests in `src-tauri/src/zones/docx_write.rs` for the partial-notice rendering: (a) `was_partial: true, was_truncated: false` → partial notice paragraph present, no truncation paragraph; (b) `was_partial: true, was_truncated: true` → both paragraphs present in the right order (partial first); (c) `was_partial: false` → no partial notice. Use the existing `extract_text_from_bytes` helper to round-trip the output and parse paragraphs.
- [x] T019 [US1] Modify the generic `DropZone` dispatch in `src-tauri/src/zones/sammanfatta.rs` (the now-generic version from spec 004) to: (1) call `InputFormat::detect_from_path(source)` and bounce-with-`UnsupportedFormat` on `None`; (2) call `extract::extract_text(source, input_format)` instead of `docx_extract::extract_text`; (3) resolve `OutputFormat::mirror_from(input_format)`; (4) call `SidecarPlan::resolve(source, zone_id)`; (5) write via the right per-format writer (`docx_write::write`, `txt_write::write`, or `md_write::write`). **Regression check (FR-020):** the spec 003 / 004 integration tests `tests/zone_sammanfatta_lifecycle.rs`, `tests/zone_cancel.rs`, `tests/zone_docx_robustness.rs`, `tests/zone_parametric.rs` MUST still pass byte-identically after this refactor — they're the load-bearing assertion that the per-zone visible state machine and event channels are unchanged.
- [x] T020 [P] [US1] End-to-end integration test in `src-tauri/tests/pdf_to_docx_lifecycle.rs`: feed `sample.pdf` into the full dispatch (with a stubbed `OllamaClient` returning a deterministic Swedish string), assert the resulting sidecar lands at `<stem>.sammanfatta.docx`, opens via `docx_extract::extract_text_from_bytes`, and contains the stubbed body + the expected header paragraph. Source SHA-256 unchanged.

---

## Phase 4 — US2: Anonymise a `.txt` case note (P1)

**Story goal**: Drop a UTF-8 `.txt` on any zone; get a `.txt` sidecar within 30 s. Windows-1252 falls back transparently. UTF-16 surfaces `UnsupportedEncoding`. Anonymisera + Förenkla sidecars carry the spec 004 disclaimer prefixed with `# `.

**Independent test**: Create a UTF-8 `.txt` with a name + personnummer, drop on Anonymisera → `<stem>.anonymiserad.txt` contains "Person A"-style placeholders, no original names verbatim, file ends with the disclaimer comment.

- [x] T021 [US2] Implement `txt_extract::extract_text(path) -> Result<ExtractedText, ZoneFailure>` in `src-tauri/src/zones/txt_extract.rs`. Steps: (1) read full file bytes; (2) sniff `BomKind` from first 4 bytes; (3) if BOM is `Utf16Le | Utf16Be | Utf32Le | Utf32Be` → `Err(UnsupportedEncoding)`; (4) if BOM is `Utf8` → skip 3 bytes, decode rest as strict UTF-8; (5) if no BOM → strict UTF-8 first, fall back to `encoding_rs::WINDOWS_1252.decode(&bytes).0` on failure; (6) strip null bytes; (7) normalise CRLF; (8) check for whitespace-only → `EmptyText`; (9) return `ExtractedText { raw, was_truncated: false, was_partial: false, frontmatter: None }`. The blank-line collapse + truncation cap happen in the top-level dispatcher.
- [x] T022 [P] [US2] Define the private `BomKind` enum + `BomKind::detect(&[u8]) -> BomKind` + `byte_length(self) -> usize` inside `src-tauri/src/zones/txt_extract.rs`. 6-case unit test covering every variant + the empty-file edge case (must return `BomKind::None`).
- [x] T023 [P] [US2] Create test fixtures: `sample-utf8.txt` (100 lines + Swedish characters), `sample-utf8-bom.txt` (UTF-8 with BOM prefix), `sample-windows-1252.txt` (Swedish characters via `iconv -t windows-1252`), `sample-utf16-le.txt` (via `iconv -t utf-16le`), `sample-empty.txt` (whitespace only). Place in `src-tauri/tests/fixtures/`.
- [x] T024 [P] [US2] Write `src-tauri/tests/txt_extract.rs` integration tests: (a) UTF-8 happy path extracts expected content; (b) UTF-8 BOM stripped + body decoded; (c) Windows-1252 fallback decodes Swedish chars correctly; (d) UTF-16 LE → `UnsupportedEncoding`; (e) UTF-16 BE → `UnsupportedEncoding`; (f) UTF-32 LE → `UnsupportedEncoding`; (g) whitespace-only → `EmptyText`; (h) extremely long file truncates to 24,000 chars via the dispatcher.
- [x] T025 [US2] Wire TXT into the top-level `extract::extract_text` dispatcher. Add 1 unit test asserting `InputFormat::Txt` routes through `txt_extract`.
- [x] T026 [US2] Implement `txt_write::write(plan, extracted, body) -> Result<(), ZoneFailure>` in `src-tauri/src/zones/txt_write.rs`. Output layout per `contracts/writer-interface.md`: comment-prefixed header line (`# <basename> — <zone_title> — <YYYY-MM-DD>`), blank line, optional truncation notice (`# Texten kortades av — modellen såg bara början av dokumentet.`), body, optional `# <disclaimer>` line for Anonymisera + Förenkla zones. UTF-8 LF output, no BOM, no trailing newline. Atomic write via `.tmp` + fsync + rename (mirror `docx_write` strategy).
- [x] T027 [P] [US2] Unit tests for `txt_write` in the same file: (a) Sammanfatta zone produces header + body, no disclaimer; (b) Anonymisera adds final disclaimer line; (c) Förenkla adds final disclaimer line (different text); (d) truncation flag adds comment line; (e) atomic-write: kill-after-write leaves no `.tmp` artifact.
- [x] T028 [US2] Wire TXT into the sidecar writer dispatch in `sammanfatta.rs` (generic DropZone). When `OutputFormat::Txt`, call `txt_write::write`. Existing .docx writes must remain identical.

---

## Phase 5 — US3: Simplify a Markdown study brief (P2)

**Story goal**: Drop a `.md` on any zone; get an `.md` sidecar preserving Markdown syntax. YAML/TOML frontmatter is captured before send, restored byte-identical on write. Anonymisera + Förenkla disclaimers render as Markdown blockquotes.

**Independent test**: Drop an `.md` with H1 + bullet list + emphasis + frontmatter on Förenkla → sidecar renders identically in Obsidian / VS Code / GitHub, frontmatter byte-identical, closing blockquote disclaimer present.

- [x] T029 [US3] Implement `md_extract::extract_text(path) -> Result<ExtractedText, ZoneFailure>` in `src-tauri/src/zones/md_extract.rs`. Steps: (1) reuse the same BOM + UTF-8 + Windows-1252 cascade from `txt_extract::extract_text` (extract a shared helper if it cleans up the implementation, e.g. `txt_extract::decode_text(bytes) -> Result<String, ZoneFailure>`); (2) detect a leading frontmatter block within the first 8 KB — YAML opens/closes with `---\n`, TOML opens/closes with `+++\n`, both must match; (3) capture the entire block (fences + content + trailing newline) into `frontmatter: Some(String)`; (4) the rest is body; (5) body strips nulls + normalises CRLF; (6) if body is whitespace-only → `EmptyText` (even if frontmatter is present); (7) return `ExtractedText { raw: Redacted(body), was_truncated: false, was_partial: false, frontmatter }`.
- [x] T030 [P] [US3] Create test fixtures: `sample.md` (H1 + bullet list + emphasis + link, no frontmatter), `sample-with-yaml-frontmatter.md` (Obsidian-style YAML at top + body), `sample-with-toml-frontmatter.md` (Hugo-style TOML at top + body), `sample-malformed-frontmatter.md` (opening `---` but no closing fence within 8 KB — frontmatter must be `None`, file body is everything).
- [x] T031 [P] [US3] Write `src-tauri/tests/md_extract.rs` integration tests: (a) no frontmatter → frontmatter None, full file is body; (b) YAML frontmatter captured + body extracted; (c) TOML frontmatter captured + body extracted; (d) malformed frontmatter → None, no body truncation; (e) BOM + frontmatter combination; (f) empty body + present frontmatter → `EmptyText`.
- [x] T032 [US3] Wire MD into the top-level `extract::extract_text` dispatcher. Add 1 unit test.
- [x] T033 [US3] Implement `md_write::write(plan, extracted, body) -> Result<(), ZoneFailure>` in `src-tauri/src/zones/md_write.rs`. Output layout per `contracts/writer-interface.md`: optional frontmatter prepended verbatim, then `# <basename> — <zone_title>`, then `> <YYYY-MM-DD>` blockquote subtitle, blank line, body, blank line, optional `> **OBS!** <disclaimer>` blockquote for Anonymisera + Förenkla. Atomic write same as txt_write.
- [x] T034 [P] [US3] Unit tests for `md_write`: (a) no frontmatter renders header + body; (b) YAML frontmatter prepended verbatim; (c) TOML frontmatter prepended verbatim; (d) Anonymisera adds closing blockquote disclaimer; (e) Förenkla adds (different) closing blockquote disclaimer; (f) truncation renders as `> *<text>*` italic blockquote; (g) atomic-write integrity.
- [x] T035 [US3] Wire MD into the sidecar writer dispatch in `sammanfatta.rs`.

---

## Phase 6 — US4: Drop an unknown extension (P3)

**Story goal**: Existing `UnsupportedFormat` error fires for `.rtf`, `.pages`, `.odt`, etc. — with copy listing all four supported formats. Mixed-case extensions (`.PDF`, `.Md`) are accepted (case-insensitive).

**Independent test**: Drop a `.rtf` → zone shows updated Swedish copy within 100 ms, no sidecar.

- [x] T036 [US4] Confirm the `UnsupportedFormat` copy update from T007 already produces the new four-format message. Add a focused unit test in `src-tauri/src/zones/errors.rs` asserting `ZoneFailure::UnsupportedFormat.swedish_copy() == "Filformatet stöds inte — dra ett .docx, .pdf, .txt eller .md."`.
- [x] T037 [P] [US4] Integration test in `src-tauri/tests/unsupported_format.rs`: feed `.rtf`, `.pages`, `.odt`, no-extension, `.tar.gz` paths through `InputFormat::detect_from_path()` → all return `None`. The dispatch maps each to `Err(ZoneFailure::UnsupportedFormat)`. Per-case timing assertion ≤ 100 ms via `std::time::Instant`.
- [x] T038 [P] [US4] Mixed-case extension test in the same file: `MYDOC.PDF`, `My.Md`, `notes.TxT`, `judgement.PdF` — all return `Some(<correct format>)`. Symlink-to-PDF returns the PDF format (the symlink's own name decides).
- [x] T039 [US4] Frontend assertion in `src/__tests__/DropZone.errors.test.tsx`: rendering an `UnsupportedFormat` zone-failure event shows the updated Swedish copy. Re-run the existing cross-language drift test (spec 003-era) — must pass.

---

## Phase 7 — US5: Updated zone hints visible at idle (P3)

**Story goal**: Each of the six zones shows an idle hint mentioning all four supported formats. ≤ 80 chars per hint. The Rust ↔ TS ↔ JSON fixture trio stays in lock-step (T035 from spec 004 must continue to pass).

**Independent test**: Launch `npm run tauri dev`, hover over each idle zone — hint mentions `.docx`, `.pdf`, `.txt`, `.md`. The parametric drift tests stay green.

- [x] T040 [US5] Update `ZoneId::hint_copy()` in `src-tauri/src/zones/zone_id.rs` with the six new strings from `data-model.md` (each ≤ 80 chars). Add a unit test asserting every variant's hint contains all four extensions + is under 80 chars.
- [x] T041 [P] [US5] Update `src-tauri/tests/fixtures/zone-identity.json` with the six new `hint_copy` values. Byte-for-byte match with the Rust strings.
- [x] T042 [P] [US5] Update `src/components/DropZone.identity.ts` `ZONE_IDENTITIES` table with the six new `hintCopy` strings. Byte-for-byte match with the fixture.
- [x] T043 [P] [US5] Update assertions in `src/__tests__/DropZone.identity.test.tsx` to reflect the new copy. The T035 cross-language drift test (already in the file) MUST continue to pass without modification beyond the expected strings.
- [x] T044 [US5] Run `cd src-tauri && cargo test zone_parametric` + `npm test -- DropZone.identity` and confirm both pass. The 80-char SwedishCopy invariant + the cross-language fixture invariant + the NoEnglishPrefix invariant are all preserved.

---

## Phase 8 — Cross-format parametric tests + polish

> **Destructive-test coverage scope (per `.claude/rules/tests.md`):** Spec 005 is a pure-backend extraction + writer expansion. Three of the six attack categories (wrong-order, skip-steps, accessibility) are N/A — spec 005 introduces NO new UI flow, NO new state transitions, NO new event channels. Destructive coverage in spec 005 concentrates in (1) **invalid input** — UTF-16 BOM, UTF-32 BOM, garbage bytes, encrypted PDF, image-only PDF; (2) **boundary values** — 24k-char truncation, empty file, no-extension, two-extension files; (3) **wrong-type** — `.rtf` / `.pages` / `.odt` / mixed-case detection. The spec 003/004 destructive tests for wrong-order (double-click, browser back), skip-steps (URL jumping, DOM manipulation), and accessibility (tab order, Enter, Escape) remain authoritative — they apply to the unchanged zone UI surface.

- [x] T045 [P] Parametric test in `src-tauri/tests/format_mirror_e2e.rs`: for every (`InputFormat`, `ZoneId`) pair (4 × 6 = 24 cases), assert `SidecarPlan::resolve(source, zone_id)` produces a path with the expected suffix + extension. No filesystem dependency — pure path resolution test.
- [x] T046 [P] Source-immutability extension in `src-tauri/tests/source_immutability.rs`: SHA-256-before-vs-after for each (`InputFormat`, `ZoneId`) pair using the fixtures from earlier phases. Mocked OllamaClient. 24 assertions, all must hold.
- [x] T047 [P] Run `humanizer` skill on every new Swedish string introduced in spec 005: the two new error messages (`NoExtractableText`, `UnsupportedEncoding`), the updated `UnsupportedFormat` copy, the partial-PDF notice, the six new hint strings, the truncation notice in `.txt` and `.md` writers. Adjust any AI-tinged phrasing. BLOCKING per CLAUDE.md.
- [x] T048 [P] Static network audit: `grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/` — every match must remain in spec 002's manager.rs + client.rs. Spec 005 introduces ZERO new outbound surface (confirms Constitution Principle I).
- [x] T049 [P] Update `README.md` Swedish status paragraph: list the four input formats and mention the spec 005 mirror rule (`.pdf → .docx`, others mirror). Run `humanizer` on the updated paragraph.
- [x] T050 Run the full regression suite in this exact order: `npm run lint && npm run typecheck && npm test`, then `cd src-tauri && cargo fmt --check && cargo clippy -- -D warnings && cargo test`, then `npm run test:e2e`. All MUST exit 0. Spec 005's additions must not regress spec 001/002/003/004.

---

## Phase 9 — Manual quickstart + close

- [x] T051 Execute `quickstart.md` flows 1–12 against `npm run tauri dev` on real hardware. Confirm SC-001 (PDF ≤ 60 s) and SC-002 (TXT ≤ 30 s) wall-clock targets on the M-series Mac. **Needs user verification on real Mac**.
- [x] T052 Verify SC-005 (specific Swedish errors within 200 ms) by dropping `sample-encrypted.pdf`, `sample-image-only.pdf`, `sample-utf16-le.txt`, and `mydoc.rtf` on any zone. Each must surface its specific error within 200 ms (pre-model detection). **Needs user verification with real drag-drop**.
- [x] T053 Tick spec 005 in `specs/INDEX.md` to `[x]` and append a Register history entry dated today. The entry summarises: light track, 5 clarifications auto-picked, allium ok (0 errors), 55/55 tasks ticked, what test counts grew to, deferrals (T051/T052 manual on real Mac).
- [x] T054 Stage + commit + push to `origin/main` per the direct-push workflow (`commit-commands:commit` skill or manual `git add`/`git commit`/`git push origin main`). Commit message format: `feat(spec-005): additional input formats (.pdf, .txt, .md)`.
- [x] T055 Emit the per-spec stop summary per `.claude/rules/spec-register.md`. Format: `Spec 005 — additional-input-formats — DONE`. Identify the next register row (spec 006 — signing-and-ci) and stop.

---

## Dependencies & ordering

- **Phase 1 (Setup)** blocks every later phase — the new modules + Cargo deps must exist before any extractor compiles.
- **Phase 2 (Foundational)** blocks Phases 3–7 — the `InputFormat`/`OutputFormat`/`extract::extract_text` skeleton + the new `ZoneFailure` variants + the sidecar_path output-format-aware refactor + the cross-language error fixtures + the mod.rs re-exports must all be in place before per-format extractors and writers can be wired.
- **Phases 3, 4, 5 (US1/US2/US3)** are largely independent of each other and parallelizable, but each finishes with a "wire into dispatch" step that touches the same `sammanfatta.rs` dispatch file. Recommend T019 (US1), T028 (US2), T035 (US3) run sequentially to avoid merge conflicts inside that file.
- **Phase 6 (US4)** depends on T007 (UnsupportedFormat copy) from Phase 2 — otherwise independent.
- **Phase 7 (US5)** depends on the Phase 2 foundational work + the lock-step fixture pattern from spec 004.
- **Phase 8 (Cross-format + polish)** depends on all user stories being complete — parametric tests cover all four formats.
- **Phase 9 (Manual + close)** runs last.

## Parallel execution opportunities

Within Phase 2 (foundational): T003, T004, T005, T012 are all `[P]` — different files, no shared state.

Within Phase 3 (US1): T014, T015 (fixtures + tests) can run while T013 (PDF extractor) is being written. T018 (docx_write unit tests) can run while T017 (docx_write extension) is in progress if you scaffold the function signature first. T020 (e2e test) runs once T013 + T017 + T019 are done.

Within Phase 4 (US2): T022, T023, T024, T027 are all `[P]`.

Within Phase 5 (US3): T030, T031, T034 are `[P]`.

Within Phase 8: T045, T046, T047, T048, T049 are all `[P]`.

## MVP scope

The minimum shippable slice is **Phase 1 + Phase 2 + Phase 3 (US1)** — PDF input on every zone, with .docx output. This already delivers the highest-impact value (PDF is the most common Swedish legal-document delivery format).

US2 (TXT) and US3 (MD) layer on top without touching US1's code paths. US4 + US5 are copy updates that can ship as a polish PR if the MVP needs to land fast.

## Format validation

Every task above starts with `- [ ]` + `T###` ID + optional `[P]` marker + optional `[US#]` label + concrete description + explicit file path. No task references "the codebase" or "appropriate files" without naming them.
