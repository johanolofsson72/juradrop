# Implementation Plan: Nine zones + real-document fixtures + integration tests

**Branch**: `main` (solo direct-push) | **Date**: 2026-05-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/013-nine-zones-and-real-fixtures/spec.md`

**Track**: Full pipeline (constitution amendment + new behavior + state-machine impact). `.allium` baseline established ([spec.allium](./spec.allium)); `/tla` required.

## Summary

Expand the drop-zone set from 6 to 9 (`Kontakter`, `Generera`, `Kallor` — already landed in phase-1 commit `0f3381b`), add a two-tier Swedish help system (per-zone `(?)` popover + chrome-bar slide-in `HelpPanel`), close the nine-spec-old test-fixture gap with real binary documents and runnable zone-pipeline integration tests, and bump the constitution 1.0.0 → 1.1.0. Mocking reuses the existing `wiremock` + `tauri::test::mock_builder` pattern (already in the repo, already passing); a debug-only `JURADROP_OLLAMA_URL` seam is added per FR-015 and exercised by the e2e smoke.

## Technical Context

**Language/Version**: Rust 1.75+ (Tauri 2.x core) + TypeScript 5 / React 18 (frontend)
**Primary Dependencies**: Tauri 2, docx-rs, pdf-extract, rtf-parser, quick-xml (odt), lopdf; React, Tailwind, zustand, lucide-react. **Net new deps: 0.**
**Storage**: Local filesystem only — sidecar files written next to source; fixtures under `src-tauri/tests/fixtures/`.
**Testing**: `cargo test` (Rust unit + integration with wiremock + tauri mock), vitest (React), Playwright smoke (macOS WebDriver still unavailable — substituted by Rust integration tests per withdrawn earlier spec 013).
**Target Platform**: macOS 12+ (Apple Silicon + Intel), single signed DMG.
**Project Type**: Desktop app (Tauri: Rust core + WKWebView frontend).
**Performance Goals**: SC-008 — total `cargo test` runtime grows by ≤ 30s (measured baseline: the 6 un-ignored tests run in 0.28s).
**Constraints**: Principle I (no outbound beyond updater + model pull) — the debug-only env seam never weakens release posture (release ignores the env var). Help copy ≤ char budgets (short ≤ 80, long ≤ 300).
**Scale/Scope**: 9 zones, 18 help strings, 15 binary fixtures, 16 + 1 integration tests, ~6 un-ignored tests.

## Constitution Check

*GATE: Must pass before Phase 0. Re-check after Phase 1.*

| Principle | Status | Note |
|---|---|---|
| I. Privacy by Architecture | ✅ PASS | No new outbound calls. Env seam is `#[cfg(debug_assertions)]`-gated; release uses hardcoded localhost. Fixtures contain only fictitious data (`[TESTDATA]` marker, FR-008). |
| II. Zero-CLI Install | ✅ PASS | No install-path change. Help system is in-app GUI. |
| III. Local-Only Inference | ✅ PASS | Seam overrides only the localhost base URL in debug; release pins `http://127.0.0.1:11434`. Invariant `ReleaseUsesLocalhostOnly`. |
| IV. Single-User Desktop App | ✅ PASS | No backend, no accounts. |
| V. Swedish-First UI | ✅ PASS | All 18 help strings Swedish, run through `humanizer` (FR-024). Code/comments English. |
| VI. Native macOS Feel | ✅ PASS | HelpPanel mirrors spec 010 SettingsPanel mechanics (SF Pro, 200ms ease-out slide, scrim). |
| VII. Bundled Sidecar | ✅ PASS | No sidecar lifecycle change. |
| VIII. Honest Failure States | ✅ PASS | `.pages` probe asserts the named-format Swedish error (FR-012a), no stack traces. |
| IX. Open Source, Free | ✅ PASS | No license change. |

**Amendment**: This spec itself triggers the 1.0.0 → 1.1.0 MINOR bump (material expansion: 6→9 zones). No principle is weakened. The constitution has no existing zone-count text to edit (verified by grep) — the amendment adds one enumerating sentence + a Sync Impact Report entry.

**Gate result: PASS. No violations. Complexity Tracking table not needed.**

## Project Structure

### Documentation (this feature)

```text
specs/013-nine-zones-and-real-fixtures/
├── plan.md              # This file
├── spec.md              # Feature spec (clarified + amended)
├── spec.allium          # Formal baseline (validated, 0 errors)
├── research.md          # Phase 0 — decisions + corrected premises
├── data-model.md        # Phase 1 — entities + state machines
├── quickstart.md        # Phase 1 — manual verification flows
├── contracts/
│   ├── help-system.md          # popover + panel + mutual-exclusion + modal-gating
│   ├── zone-pipeline.md        # drop → extract → prompt → generate → write
│   └── test-seam.md            # JURADROP_OLLAMA_URL + wiremock harness
├── checklists/requirements.md  # (exists from phase 1)
└── tasks.md             # Phase 2 — /speckit-tasks output
```

### Source Code (repository root)

```text
src-tauri/src/
├── zones/zone_id.rs               # [DONE phase 1] 9 variants
├── prompts/{kontakter,generera,kallor}.rs  # [DONE phase 1] 3 prompts
├── sidecar/client.rs              # [phase 3] + JURADROP_OLLAMA_URL debug seam (FR-015)
└── help/                          # [phase 2] NEW — zone_help.rs (ZONE_HELP_STRINGS const)

src/
├── components/
│   ├── DropZone.tsx               # [phase 2] + per-zone (?) popover (FR-018)
│   ├── ZoneHelpPopover.tsx        # [phase 2] NEW
│   ├── HelpIcon.tsx               # [phase 2] NEW — chrome-bar (?) (FR-019)
│   └── HelpPanel.tsx              # [phase 2] NEW — slide-in, mirrors SettingsPanel
├── lib/
│   ├── help-strings.ts            # [phase 2] NEW — ZONE_HELP_STRINGS TS mirror
│   ├── use-help-panel.ts          # [phase 2] NEW — mirrors use-settings-panel
│   └── DropZone.identity.ts       # [DONE phase 1] 9 entries
└── App.tsx                        # [phase 2] mount HelpIcon + HelpPanel + mutual-exclusion wiring

src-tauri/tests/
├── fixtures/
│   ├── documents/<zone>-input.{docx,txt}   # [phase 4] 9 zone fixtures
│   ├── extraction-probe/extraction-probe.<ext>  # [phase 4] 6 + malformed .pages
│   ├── zone-identity.json         # [DONE phase 1] 9 entries
│   └── zone-help-strings.json     # [phase 2] NEW — 18-string drift fixture
├── zone_pipeline_<zone>.rs        # [phase 5] 9 NEW integration tests
├── extraction_probe.rs            # [phase 5] NEW — 6 + 1 pages-failure tests
├── zone_pipeline_e2e_smoke.rs     # [phase 5] NEW — exercises the env seam
├── zone_sammanfatta_lifecycle.rs  # [phase 5] un-ignore (verified passing)
└── zone_cancel.rs                 # [phase 5] un-ignore audit

.specify/memory/constitution.md    # [phase 6] 1.0.0 → 1.1.0
README.md, CHANGELOG.md            # [phase 6]
```

**Structure Decision**: Existing JuraDrop layout. Help system follows the spec 010 settings-panel module shape exactly (component + hook + strings-const + drift-fixture). Test infrastructure reuses spec 003's wiremock+mock_builder harness verbatim.

## Phase ordering (implementation)

Phase 1 (zones data+type layer) is **DONE** (commit `0f3381b`). Remaining:

- **Phase 2 — Help system** (UI; `frontend-design` + `humanizer` skills BLOCKING before code).
- **Phase 3 — Test seam**: `JURADROP_OLLAMA_URL` debug-only override in `client.rs` (FR-015). No hand-rolled mock (superseded — wiremock already present).
- **Phase 4 — Fixtures**: generate 9 zone docs + 6 probes + malformed `.pages` programmatically (docx-rs for `.docx`, format-specific writers/byte-templates for the rest).
- **Phase 5 — Integration tests**: 9 zone-pipeline + 6+1 probe + e2e smoke; un-ignore audit.
- **Phase 6 — Constitution + docs + verification**: bump 1.1.0, README, CHANGELOG, vitest/cargo full suite, `/tla`.

Per `continuous-execution.md` these run as one task. `/speckit.analyze` runs between `/tasks` and implementation; `/tla` after tests.

## Complexity Tracking

No constitution violations — table intentionally empty.
