# Implementation Plan: Long-tail input formats (.rtf, .pages, .odt)

**Branch**: `main` (direct-to-main per `.claude/rules/spec-register.md`) | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/009-long-tail-formats/spec.md` plus the formal contract in [spec.allium](spec.allium).

## Summary

Add three new text extractors (`rtf_extract`, `pages_extract`, `odt_extract`) behind the existing `InputFormat` dispatch from spec 005, and three new format-named `ZoneFailure` variants (`RtfParseError`, `PagesParseError`, `OdtParseError`) wired into the existing error event channel. Extend the hint copy in every zone to list all seven supported formats in a slash-separated 67-char string. Extend the `InvalidFormat` Swedish copy. Extend the cross-language drift fixture (`zone-error-strings.json`) with the new keys plus the updated `invalid_format` value. The dispatch pipeline, ZoneId routing, system prompts, single-flight per-zone slot, Redacted prompt handling, atomic write, cancel affordance, disabled gate, and visible state machine from specs 003/004/005 are **UNCHANGED**. No new Tauri commands, no new event channels, no new states, no new outbound network surface. Output mirror rule extended: `.pages` → `.docx` always; `.rtf` and `.odt` mirror input only if a pure-Rust writer is available, else fall back to `.docx` (research below settles availability).

## Technical Context

**Language/Version**: Rust 1.95+, TypeScript 5.x. Same toolchain as spec 005/008.

**Primary Dependencies**: Existing — `docx-rs`, `pdf-extract = 0.7`, `encoding_rs = 0.8`, `zip = 0.6`, `open`, `tokio-util`, `uuid`, `chrono`, `reqwest`. **New** — `rtf-parser = 0.4` (pure-Rust RTF text extractor, MIT, no transitive HTTP), `quick-xml = 0.36` (pure-Rust XML pull-parser, MIT, used by 6M+ downstream crates, no network). The `zip = 0.6` crate from spec 005 is reused for both `.pages` and `.odt` bundle reading — no second zip dep. See `research.md` for the crate-selection decision log and license audit.

**Storage**: Filesystem (sidecar files next to source). No schema changes. The sidecar filename suffix per `ZoneId` from spec 004 is reused as-is — only the extension varies. For `.rtf` and `.odt` inputs without a pure-Rust writer, the sidecar extension is `.docx` (same fallback as `.pdf` → `.docx` from spec 005).

**Testing**:
- Rust: `cargo test` + new integration tests `tests/rtf_extract.rs`, `tests/pages_extract.rs`, `tests/odt_extract.rs`, `tests/long_tail_format_mirror.rs`, `tests/long_tail_drift.rs`. Existing spec 003/004/005/008 integration tests must stay green without modification — `.docx`, `.pdf`, `.txt`, `.md` behaviour is byte-identical.
- JS: vitest extension `src/__tests__/DropZone.longtail-formats.test.tsx` — asserts the seven-format hint copy renders, the three new Swedish error strings render, and the updated `InvalidFormat` copy renders. The existing T035 drift test (cross-language) is extended to cover the three new error keys + the updated `invalid_format` value.
- Light pipeline → **no `/tla`** (state machine unchanged from spec 005; the three new error variants map to the existing `error` visible state via the existing `ZoneFailureRaised` event channel — no new transitions, no new fairness conditions, no new safety invariants beyond the SwedishCopy-style content checks).
- Browser tests: Playwright smoke extended with one new scenario per format (drop a valid `.rtf`, `.pages`, `.odt` and assert sidecar appears). Destructive tests cover corrupt + password-protected + directory-form `.pages`.

**Target Platform**: macOS 12+ on Apple Silicon. Unchanged.

**Project Type**: Desktop app (Tauri 2.x). Unchanged.

**Performance Goals**:
- SC-001: 2-page `.rtf` → sidecar within `.docx` baseline ± 25 %. Extraction < 100 ms (RTF parsing is fast); model dominates.
- SC-002: 2-page `.pages` → `.docx` sidecar within `.docx` baseline ± 25 %. Extraction < 300 ms (zip extract + XML walk).
- SC-003: 100 % of corrupted long-tail fixtures surface the format-named Swedish error within 200 ms (pre-model detection).
- SC-004: 100 % of unsupported extensions still surface the updated `InvalidFormat` Swedish copy.

**Constraints**:
- Principle I (privacy): no new outbound surface. `rtf-parser` and `quick-xml` are pure-Rust, offline, audited (`quick-xml` is in every major Rust XML pipeline). Both have zero network calls and zero filesystem writes outside the explicit dispatch.
- Every extractor wraps its output in `Redacted<String>` end-to-end (the existing `ExtractedText` type — unchanged shape from spec 005).
- The 24,000-UTF-8-character truncation cap from spec 003 FR-019 applies to all seven formats; truncation happens after extraction on the raw text.

**Scale/Scope**: Seven input formats × six zones = 42 (input, zone) pairs. Documents up to ~50 pages (.rtf/.odt) or ~20 pages (.pages — Pages bundles are heavier per-page). Single user, in-process.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Privacy by Architecture | Both new deps (`rtf-parser`, `quick-xml`) are pure-Rust, offline. Every extracted text wrapped in `Redacted<String>`. Zero new outbound network calls (audited via the existing `grep -RInE "reqwest::Client\|ureq::\|surf::"` sweep — neither `rtf-parser` nor `quick-xml` carries an HTTP client transitively). | ✅ |
| II. Zero-CLI Install | Two new Cargo deps statically linked into the existing signed binary. No external binaries, no Homebrew, no `unoconv` / `pandoc` / `textutil` shell-out. | ✅ |
| III. Local-Only Inference | The new extractors only feed the existing `OllamaClient` at `127.0.0.1:11434`. No format introduces a new model route. | ✅ |
| IV. Single-User Desktop App | No new daemon, no menu-bar tray, no background service. The new extractors run inside the existing per-drop dispatch. | ✅ |
| V. Swedish-First UI, English-First Code | Three new Swedish error strings (`Kunde inte läsa .rtf-filen` etc.); updated `InvalidFormat` Swedish copy; updated zone hint copy in Swedish. All Rust identifiers (`rtf_extract`, `PagesParseError`, etc.) in English. | ✅ |
| VI. Native macOS Feel | Pure backend change; no UI components added. Drag-over affordance for the three new extensions reuses the existing green-border treatment. | ✅ |
| VII. Bundled Sidecar (Ollama internal) | Long-tail extractors never talk to Ollama directly — they hand `Redacted<String>` to the existing dispatch, which talks to Ollama. The user never sees "RTF parser failed" — they see the Swedish format-named copy. | ✅ |
| VIII. Honest Failure States | Format-named errors (`Kunde inte läsa .rtf-filen` etc.) name the format explicitly, no generic "Kunde inte läsa dokumentet" fallback. The directory-form `.pages` routes to `InvalidFormat` (not the format-named error) because there is nothing to attempt. Long-tail password-protected files collapse into the format-named error (not `PasswordProtected`) to keep the long-tail failure surface uniform. | ✅ |
| IX. Open Source, Free, No Lock-In | Both new deps are MIT-licensed (audited in `research.md`). Output formats are still standard (`.docx`, `.rtf`, `.odt`) — no JuraDrop-proprietary format introduced. | ✅ |

**Constitution gate: 9/9 ✅ — proceed to Phase 0.**

## Project Structure

### Documentation (this feature)

```text
specs/009-long-tail-formats/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 output — crate selection + license audit
├── data-model.md        # Phase 1 output — InputFormat/OutputFormat/ZoneFailure deltas + extractor shapes
├── quickstart.md        # Phase 1 output — manual + Playwright verification steps
├── contracts/           # Phase 1 output — extractor traits + fixture schema + drift contract
│   ├── extractor-trait.md
│   ├── zone-error-strings-schema.md
│   └── output-mirror-rule.md
├── spec.md              # Phase A — written
├── spec.allium          # Phase B — written
├── checklists/
│   └── requirements.md  # Validation
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
src-tauri/
├── Cargo.toml                           # +rtf-parser = 0.4, +quick-xml = 0.36
├── src/
│   ├── zones/
│   │   ├── input_format.rs              # MODIFY: extend enum + detect_from_path to 7 variants
│   │   ├── output_format.rs             # MODIFY (or create): extended mirror rule
│   │   ├── errors.rs                    # MODIFY: +RtfParseError, +PagesParseError, +OdtParseError, +invalid_format copy update
│   │   ├── rtf_extract.rs               # NEW: pure-Rust RTF text extraction
│   │   ├── pages_extract.rs             # NEW: zip+XML+IWA bundle reading
│   │   ├── odt_extract.rs               # NEW: zip+content.xml walk with accepted-view tracked-change resolver
│   │   └── dispatch.rs                  # MODIFY: route the three new InputFormat variants to the new extractors
│   └── ...
└── tests/
    ├── fixtures/
    │   └── zone-error-strings.json      # MODIFY: +3 keys, update invalid_format
    ├── rtf_extract.rs                   # NEW: happy + corrupt + embedded-objects + empty
    ├── pages_extract.rs                 # NEW: happy + password-protected + directory-form + corrupt
    ├── odt_extract.rs                   # NEW: happy + tracked-changes + missing-content + encrypted
    ├── long_tail_format_mirror.rs       # NEW: end-to-end (input, zone) pairs for the 3 new formats × 6 zones
    └── long_tail_drift.rs               # NEW: Rust-side assertion that the fixture matches the enum variants

src/
├── components/
│   ├── DropZone.errors.ts               # MODIFY: +3 keys, update invalid_format
│   ├── DropZone.identity.ts             # MODIFY: hint copy updated for all 6 zones, slash-separated 7-format list
│   └── DropZone.tsx                     # (no change — error rendering reads from the keyed Swedish strings)
└── __tests__/
    └── DropZone.longtail-formats.test.tsx  # NEW: drift assertion + hint copy assertion + invalid_format copy assertion
```

**Structure Decision**: Single Tauri 2.x desktop app, same as spec 005. Add three sibling extractor modules under `src-tauri/src/zones/`, three sibling integration test files under `src-tauri/tests/`, three new fixture keys, two TS files modified.

## Phase 0 — Research

See [research.md](research.md). Key decisions:
- **RTF parser**: `rtf-parser = 0.4` (MIT, pure-Rust, no transitive HTTP).
- **XML parser** (for ODT `content.xml` and Pages legacy `index.xml`): `quick-xml = 0.36` (MIT, pure-Rust, audited).
- **Pages IWA decoding**: best-effort only. Modern Pages (v5+) uses Snappy-compressed Protocol Buffers (IWA). No mature pure-Rust IWA decoder exists. The plan accepts that most modern `.pages` files will surface `Kunde inte läsa .pages-filen`. Legacy Pages files (rare) that include an `index.xml` member are extracted. This degraded-best-effort is consistent with the spec's "best-effort" framing and named-format error contract.
- **No pure-Rust RTF writer** exists with a stable enough API → `.rtf` input mirrors to `.docx` sidecar.
- **No pure-Rust ODT writer** exists with a stable enough API → `.odt` input mirrors to `.docx` sidecar.
- **License audit**: 100 % MIT or Apache-2.0; zero GPL/LGPL/AGPL.

## Phase 1 — Design & Contracts

See [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md).

Key shapes:
- `InputFormat` extended from 4 to 7 variants. `detect_from_path` extended. Test matrix extended.
- `OutputFormat` declares `docx`, `txt`, `md` always; `rtf`, `odt` only present if their writer crate is selected at plan time (this plan chooses to omit both — see research).
- `ZoneFailure` extended with three new variants. Swedish copy pinned. SwedishCopy invariants verified at test time (`< 80 chars`, no English `Error:` prefix, non-empty).
- New extractor module trait: `pub fn extract_text(path: &Path) -> Result<ExtractedText, ZoneFailure>` — same shape as `pdf_extract`, `txt_extract`, `md_extract` from spec 005. Returns `ExtractedText` with `was_partial = false` and `frontmatter = None` for all three long-tail formats (partial-PDF and md-frontmatter are spec-005-only concerns).
- Cross-language drift fixture (`src-tauri/tests/fixtures/zone-error-strings.json`) gains three keys (`rtf_parse_error`, `pages_parse_error`, `odt_parse_error`) and updates `invalid_format`. Both the Rust drift test and the TS drift test assert against this single fixture.

## Phase 2 — Tasks (deferred to `/speckit-tasks`)

`/speckit-tasks` will decompose the plan into:
1. Cargo manifest update + license audit verification step
2. `InputFormat` enum + detect extension (TDD: extend `input_format::tests` first)
3. `ZoneFailure` enum + Swedish strings + drift fixture update (TDD: extend `errors::tests` + fixture-drift test first)
4. RTF extractor module + integration tests
5. Pages extractor module + integration tests
6. ODT extractor module + integration tests
7. Dispatcher wiring for the three new InputFormat variants
8. Output mirror rule update (`.rtf`/`.odt`/`.pages` → `.docx`)
9. Hint copy update across all 6 zones + cross-language fixture parity
10. Playwright smoke for all three new happy paths
11. Vitest extension for hint + error copy + drift
12. Final constitution re-check + grep audit for outbound surface

## Complexity Tracking

No constitution violations. No simpler alternative was rejected — the design choices (skip `.pages` IWA decoding, fall back `.rtf`/`.odt` → `.docx` sidecar, collapse password-protected into format-named error) are all simplifications, not complications.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_  | _(none)_   | _(none)_                            |
