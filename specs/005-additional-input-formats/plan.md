# Implementation Plan: Additional input formats (.pdf, .txt, .md)

**Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`) | **Date**: 2026-05-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-additional-input-formats/spec.md` plus the formal contract in [spec.allium](spec.allium).

## Summary

Add three new text extractors (`.pdf` via `pdf-extract`, `.txt` and `.md` via direct read + encoding cascade) behind the existing `docx_extract::extract_text` interface, and add two new sidecar writers (`.txt`, `.md`) plus an output-format mirror rule that selects which writer the dispatch uses. The dispatch pipeline, ZoneId routing, system prompts, single-flight per-zone slot, Redacted prompt handling, atomic write, cancel affordance, disabled gate, and Swedish error states from specs 003/004 are UNCHANGED. Two new `ZoneFailure` variants (`NoExtractableText` for image-only PDFs, `UnsupportedEncoding` for UTF-16/UTF-32 text files) are wired into the existing error event channel — no new state-machine transitions. Per-zone idle hints are reworded to mention all four supported extensions, with the `zone-identity.json` fixture + Rust `hint_copy()` + TS `ZONE_IDENTITIES` table staying in lock-step (the T035 drift test from spec 004 must continue to pass).

## Technical Context

**Language/Version**: Rust 1.95+, TypeScript 5.x. Same toolchain as spec 003/004.

**Primary Dependencies**: Existing — `docx-rs`, `open`, `tokio-util`, `uuid`, `zip`, `chrono`, `reqwest`. **New** — `pdf-extract = "0.7"` (pure-Rust PDF text extraction, MIT-licensed, no external binaries), `encoding_rs = "0.8"` (Windows-1252 + BOM detection for the text-file encoding cascade). Both crates are already widely audited (Mozilla maintains `encoding_rs`; `pdf-extract` is on crates.io with > 800k downloads). Neither makes network calls, neither shells out.

**Storage**: Filesystem (sidecar files next to source). No schema changes. The sidecar filename suffix per ZoneId from spec 004 is reused as-is — only the extension varies (`<stem>.<suffix>.<ext>` where `<ext>` ∈ `{docx, txt, md}`).

**Testing**:
- Rust: `cargo test` + new integration tests `tests/pdf_extract.rs`, `tests/txt_extract.rs`, `tests/md_extract.rs`, `tests/format_mirror.rs`. Existing spec 003/004 integration tests (`zone_sammanfatta_lifecycle`, `zone_docx_robustness`, `zone_cancel`, `zone_parametric`) must stay green without modification — `.docx` behaviour is byte-identical.
- JS: vitest extension `src/__tests__/DropZone.formats.test.tsx` — asserts the updated hint copy mentions all four extensions + the T035 drift test (which already exists) stays green.
- Light pipeline → no `/tla` (state machine unchanged from spec 004; the two new error variants map to the existing `error` visible state via the existing event channel).
- E2E: Playwright stub stays as-is. Manual smoke verification via `npm run tauri dev` per the quickstart checklist.

**Target Platform**: macOS 12+ on Apple Silicon. Unchanged.

**Project Type**: Desktop app (Tauri 2.x). Unchanged.

**Performance Goals**:
- SC-001: 5-page text-based `.pdf` → `.docx` sidecar within 60 s (warm Ollama, `gemma3:4b`). Extraction is < 500 ms; model dominates.
- SC-002: 100-line `.txt` → `.txt` sidecar within 30 s. Extraction < 20 ms.
- SC-003: 100-line `.md` with five Markdown features → `.md` sidecar preserves every feature in a Markdown previewer.
- SC-005: Encrypted PDF / image-only PDF / UTF-16 `.txt` / unsupported extension all surface specific Swedish errors within 200 ms (pre-model detection).

**Constraints**:
- Principle I (privacy): no new outbound surface. `pdf-extract` is pure-Rust (`pdf-extract` itself depends on `lopdf` which is pure-Rust and offline). `encoding_rs` is pure-Rust. Both have zero network calls and zero filesystem writes outside the explicit dispatch.
- Every extractor wraps its output in `Redacted<String>` end-to-end (the existing `ExtractedText` type — extended with optional `frontmatter` and `was_partial` fields).
- The 24,000-UTF-8-character truncation cap from spec 003 FR-019 applies to all four formats; truncation happens after extraction on the raw text.

**Scale/Scope**: Four input formats × six zones = 24 (input, zone) pairs. Documents up to ~50 pages (PDF) or ~30,000 characters (txt/md before truncation). Single user, in-process.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Privacy by Architecture | Both new deps (`pdf-extract`, `encoding_rs`) are pure-Rust, offline. Every extracted text wrapped in `Redacted<String>`. Zero new outbound network calls (audited via the existing `grep -RInE "fetch\|reqwest::Client::\|tokio::net::"` sweep). | ✅ |
| II. Zero-CLI Install | Two new Cargo deps statically linked into the existing signed binary. No external binaries, no Homebrew, no Terminal step. | ✅ |
| III. Local-Only Inference | The new extractors only feed the existing OllamaClient at `127.0.0.1:11434`. No format introduces a new model route. | ✅ |
| IV. Single-User Desktop App | No backend, no accounts, no daemon. Format detection runs in-process inside the existing dispatch. | ✅ |
| V. Swedish-First UI, English-First Code | Two new Swedish error strings (`NoExtractableText`, `UnsupportedEncoding`). Updated hint copy in Swedish. One new Swedish partial-extraction notice. Code, comments, commits in English. | ✅ |
| VI. Native macOS Feel | Pure infrastructure change — no UI redesign. The existing dashed-border zone treatment, SF Pro typography, and motion are untouched. | ✅ |
| VII. Bundled Sidecar Internal | The user still sees one model. Format detection is invisible; the same model handles every prompt regardless of extracted-from format. | ✅ |
| VIII. Honest Failure States | Five distinct Swedish error variants now (was three for `.docx`): `PasswordProtected`, `UnsupportedFormat`, `EmptyText`, `NoExtractableText`, `UnsupportedEncoding`. Plus the FR-002a partial-PDF notice. Each maps to the existing `error` visible state with copy specific to the root cause. No generic fallback. | ✅ |
| IX. Open Source, Free, No Lock-In | Output extensions are `.docx`, `.txt`, `.md` — all open formats. `pdf-extract` is MIT. `encoding_rs` is Apache-2.0/MIT dual. Both compatible with the project's MIT licence. | ✅ |

**All gates pass.** No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/005-additional-input-formats/
├── spec.md                       # written + 5 auto-picked clarifications integrated
├── spec.allium                   # written + 0 errors
├── plan.md                       # this file
├── research.md                   # Phase 0 — pdf-extract vs alternatives, encoding cascade, frontmatter regex
├── data-model.md                 # Phase 1 — extended ExtractedText, InputFormat/OutputFormat enums, new ZoneFailure variants
├── quickstart.md                 # Phase 1 — 12 smoke flows (4 formats × 3 happy/error/edge)
├── contracts/                    # Phase 1
│   ├── extract-interface.md      # ExtractedText shape, per-format extractor contracts
│   ├── writer-interface.md       # Per-format sidecar writer contracts
│   └── error-vocabulary.md       # New ZoneFailure variants + Swedish copy + UI mapping
├── checklists/
│   └── requirements.md           # already passing
└── tasks.md                      # Phase 2 — produced by /speckit-tasks
```

### Source Code (repository root)

```text
src-tauri/
├── Cargo.toml                                       # MODIFIED — add pdf-extract + encoding_rs deps
├── src/
│   ├── zones/
│   │   ├── mod.rs                                   # MODIFIED — re-export InputFormat, OutputFormat
│   │   ├── input_format.rs                          # NEW — InputFormat enum + detect_from_extension()
│   │   ├── output_format.rs                         # NEW — OutputFormat enum + mirror_from(input)
│   │   ├── extract.rs                               # NEW — top-level extract_text(path, input_format) dispatcher
│   │   ├── docx_extract.rs                          # UNCHANGED (unless wrapper signature update)
│   │   ├── pdf_extract.rs                           # NEW — pdf-extract wrapper + partial-extraction tracking
│   │   ├── txt_extract.rs                           # NEW — BOM detection + UTF-8 / Windows-1252 cascade
│   │   ├── md_extract.rs                            # NEW — frontmatter capture + body extraction (shares txt cascade)
│   │   ├── docx_write.rs                            # MODIFIED — accept partial-extraction notice parameter (FR-002a)
│   │   ├── txt_write.rs                             # NEW — TXT sidecar writer (header + body + disclaimer)
│   │   ├── md_write.rs                              # NEW — MD sidecar writer (H1 + blockquote + body + disclaimer + frontmatter prepend)
│   │   ├── sidecar_path.rs                          # MODIFIED — accept input_format → resolve output extension via mirror rule
│   │   ├── sammanfatta.rs (generic DropZone)        # MODIFIED — dispatch reads input_format and calls the right extractor + writer
│   │   ├── errors.rs                                # MODIFIED — add NoExtractableText, UnsupportedEncoding variants + Swedish copy
│   │   └── zone_id.rs                               # MODIFIED — hint_copy() updated to mention all four formats
│   └── prompts/                                     # UNCHANGED (the six system prompts apply to every format)
├── tests/
│   ├── fixtures/
│   │   ├── zone-error-strings.json                  # MODIFIED — add NoExtractableText + UnsupportedEncoding Swedish strings
│   │   ├── zone-identity.json                       # MODIFIED — updated hint_copy per zone (all four extensions)
│   │   ├── sample.pdf                               # NEW — small text-based PDF for happy-path tests
│   │   ├── sample-encrypted.pdf                     # NEW — open-password-protected PDF
│   │   ├── sample-image-only.pdf                    # NEW — single page that is a scan (no text layer)
│   │   ├── sample-utf8.txt                          # NEW
│   │   ├── sample-utf8-bom.txt                      # NEW
│   │   ├── sample-windows-1252.txt                  # NEW — copyright sign 0xA9 etc.
│   │   ├── sample-utf16-le.txt                      # NEW — must error UnsupportedEncoding
│   │   ├── sample.md                                # NEW — five Markdown features, no frontmatter
│   │   └── sample-with-frontmatter.md               # NEW — YAML frontmatter + body
│   ├── pdf_extract.rs                               # NEW — happy path, encrypted, image-only, partial, truncation
│   ├── txt_extract.rs                               # NEW — BOM detection, UTF-8 strict, Windows-1252 fallback, UTF-16 reject
│   ├── md_extract.rs                                # NEW — frontmatter capture (YAML + TOML), body extraction
│   ├── format_mirror.rs                             # NEW — InputFormat → OutputFormat mirror rule + suffix construction
│   └── zone_parametric.rs                           # MODIFIED — hint_copy assertions updated for new copy

src/
├── components/
│   └── DropZone.identity.ts                         # MODIFIED — ZONE_IDENTITIES.hint_copy updated for all six zones
└── __tests__/
    ├── DropZone.identity.test.tsx                   # MODIFIED — hint assertions reflect new copy + T035 still passes
    └── DropZone.formats.test.tsx                    # NEW — vitest sanity for the updated copy

README.md                                            # MODIFIED — Swedish status updated to mention four input formats
```

**Structure Decision**: Pure additive refactor inside the existing `src-tauri/src/zones/` module. The `docx_extract` and `docx_write` modules from spec 003 stay in place — they become "the .docx implementation of the new generic Extractor/Writer interfaces". Two new dimensions (input format, output format) get their own files (`input_format.rs`, `output_format.rs`) for compile-time exhaustiveness via Rust match. The dispatch in `sammanfatta.rs` (the generic DropZone from spec 004) gets a single new branch at the extract step that switches over `InputFormat`, plus a single new branch at the write step that switches over `OutputFormat`. No new entry points, no new event channels, no React reorganisation — the existing zone UI is format-agnostic by design.
