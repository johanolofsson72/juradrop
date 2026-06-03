# Implementation Plan: Study-method drop zones (9 → 12)

**Branch**: `main` (solo / direct-push) | **Date**: 2026-06-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/036-study-method-zones/spec.md`

## Summary

Add three transform/extract zones — `identifiera` (Identifiera rättsfrågorna), `strukturera` (Strukturera IRAC), `forklara` (Förklara begreppen) — growing the grid 9→12, following the spec-013 6→9 pattern exactly. Each reuses the existing DropZone state machine + dispatch pipeline; each is DATA-framed (spec 022), mirrors input format, carries a "granska …" disclaimer, and has a system prompt that forbids inventing/citing lagrum/SFS/rättsfall/NJA (Principle VIII). A fourth citation zone is deliberately rejected. The window grows 760→1000 so all four rows show (frontend-design decision). No new outbound, no new deps, no new state machine.

## Technical Context

**Language/Version**: Rust 2021 (`src-tauri`) + React 18/TypeScript (`src`).

**Primary Dependencies**: none new. Reuses ZoneId/prompts/framing/output_format/zone_help (Rust) + DropZone.identity (TS).

**Storage**: N/A.

**Testing**: `cargo test` (3 new `zone_pipeline_<slug>.rs` integration tests via the `run_zone_pipeline` mock-Ollama harness + the auto-parameterised drift tests + the zone-count assertion bumped 9→12) + `npm test` (vitest: DropZone.identity + help-strings-drift updated 9→12) + Playwright smoke (the twelve-zone render). `/tla` OUT OF SCOPE (reuses the existing per-zone state machine — light-track triviality gate).

**Target Platform**: macOS desktop (Tauri 2.x / WKWebView).

**Project Type**: Desktop app (Rust core + React frontend).

**Performance Goals**: none new (same per-drop inference latency).

**Constraints**: Principle I (no new outbound — same local Ollama), Principle VIII (no fabricated citations; honest disclaimers), Principle V (Swedish copy humanizer-reviewed). All 12 zones visible at launch without scrolling.

**Scale/Scope**: ~12 Rust touch-points (zone_id.rs enum + 8 exhaustive matches + ALL[;12] + test; 3 new prompts/*.rs + mod.rs; zone_help.rs [;12]+3; output_format/framing need NO new arm — `_` covers transform/data), TS (DropZone.identity.ts +3 ZONE_IDENTITIES +3 ZONE_ORDER), 2 JSON fixtures (+3 each), 3 binary `.docx` fixtures (via examples/generate_fixtures.rs), 3 new Rust pipeline tests, updated TS drift tests, tauri.conf.json (height), constitution.md (1.1.0→1.2.0).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment |
|---|---|
| **I. Privacy by Architecture** | ✅ Unaffected — the three zones run the SAME local-only drop→Ollama→sidecar pipeline; zero new outbound, zero telemetry. |
| **III. Local-Only Inference** | ✅ Same `127.0.0.1:11434` pipeline; no new model/host. |
| **VIII. Honest Failure States** | ✅ **Reinforced** — each zone's prompt forbids fabricated lagrum/case refs (the explicit anti-hallucination guard that replaces a rejected citation zone), and each carries a "granska …" disclaimer about model fallibility. |
| **V. Swedish-First UI, English-First Code** | ✅ All new copy Swedish + humanizer-reviewed (BLOCKING gate at impl); slugs/identifiers/comments English/ASCII. |
| **VI. Native macOS Feel** | ✅ Window grows to fit 4 rows; grid stays the existing dashed-tile aesthetic (frontend-design reviewed). |
| **Governance** | ⚠️ The constitution enumerates "nine zones in a 3×3 grid" as a governing fact → REQUIRES a version bump 1.1.0→1.2.0 + re-enumeration (FR-012). MINOR, no principle weakened (mirrors the spec-013 6→9 bump). |

**Result: PASS** (with the required constitution amendment, which is part of the deliverable). No principle weakened.

## Project Structure

### Documentation (this feature)

```text
specs/036-study-method-zones/
├── plan.md  spec.md  spec.allium
├── research.md       # frontend-design layout decision + zone semantics + DRAFT Swedish copy (→ humanizer at impl)
├── data-model.md     # the 3 zone identity rows + per-zone method values + suffixes
├── quickstart.md     # build + verify steps
└── checklists/requirements.md
```

### Source Code (repository root)

```text
src-tauri/src/zones/zone_id.rs
  - ZoneId: +3 variants (Identifiera/Strukturera/Forklara) w/ serde rename (identifiera/strukturera/forklara)
  - ALL: [ZoneId; 9] → [ZoneId; 12]; the 8 EXHAUSTIVE matches each +3 arms
    (slug, title, hint_copy, processing_hint, sidecar_suffix, header_paragraph_template,
     system_prompt, disclaimer_paragraph — all three RETURN Some(disclaimer))
  - test spec_013_has_exactly_nine_zones → twelve (+ index 9/10/11 assertions)
src-tauri/src/prompts/{identifiera,strukturera,forklara}.rs   # NEW — 1 Swedish const each
src-tauri/src/prompts/mod.rs                                   # +3 mod + re-exports
src-tauri/src/prompts/framing.rs                              # NO change (3 zones fall through `_` = DATA)
src-tauri/src/zones/output_format.rs                         # NO change (3 zones fall through `_` = mirror)
src-tauri/src/help/zone_help.rs                              # ZONE_HELP_STRINGS [;9]→[;12] +3 entries
src/components/DropZone.identity.ts                          # ZONE_IDENTITIES +3, ZONE_ORDER +3 (appended)
src/App.tsx                                                  # grid classes UNCHANGED (12 = clean 3×4)
src-tauri/tauri.conf.json                                    # window height 760 → 1000 (minHeight 500 unchanged)
src-tauri/tests/fixtures/zone-identity.json                 # +3 rows, _comment 9→12
src-tauri/tests/fixtures/zone-help-strings.json             # +3 rows, _comment 9→12
src-tauri/tests/fixtures/documents/{identifiera,strukturera,forklara}-input.docx  # NEW (generate_fixtures.rs)
src-tauri/examples/generate_fixtures.rs                      # +3 fixture generators
src-tauri/tests/zone_pipeline_{identifiera,strukturera,forklara}.rs  # NEW (run_zone_pipeline)
src/__tests__/DropZone.identity.test.tsx                     # EXPECTED_ZONE_IDS +3, fixture-key assertion 9→12
src/__tests__/help-strings-drift.test.ts                    # comment 9→12 (logic auto)
.specify/memory/constitution.md                             # 1.1.0→1.2.0, "nine/3×3" → "twelve/3×4", Sync Impact
```

**Structure Decision**: Pure additive expansion in the existing zone layers — no new module, no new component, no new state machine. The `framing.rs` and `output_format.rs` `_` arms already cover transform/data zones, so they need NO change (a quiet confirmation that the three zones are "ordinary" transform zones). The only genuinely new artifacts are 3 prompt files, 3 binary fixtures, 3 pipeline tests.

## Layout decision (frontend-design gate — RESOLVED)

- **Window height 760 → 1000** (`tauri.conf.json`; width 1160 unchanged — still 3 columns). 760 fit 3 rows; fixed chrome ≈176px leaves ~194px/tile-row, so a 4th row + gap ≈ +206px → ~966; 1000 gives a ~35px bottom margin so the 4th row never clips at the `lg` breakpoint.
- **`minHeight` 500 unchanged** — below `lg` the grid collapses to `sm:grid-cols-2`/`grid-cols-1` and scrolls (correct graceful degradation for a deliberately-shrunk window).
- **Grid classes unchanged** (`grid-cols-1 / sm:grid-cols-2 / lg:grid-cols-3`). 12 divides evenly by 1/2/3 → ZERO orphan tiles at any breakpoint (cleaner than 9, which orphaned 1 tile at the sm 2-col layout). No new breakpoint.

## Complexity Tracking

> Constitution amendment (1.1.0→1.2.0) is required but is the documented MINOR expansion pattern (spec 013 precedent), not a violation. No other entries.
