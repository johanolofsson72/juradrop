# Quickstart: Study-method drop zones

## Build & verify

```bash
# Rust: enum + matches compile (every exhaustive match must have the 3 new arms)
cd src-tauri && cargo build

# Regenerate the 3 new binary input fixtures, then run them through the pipeline
cd src-tauri && cargo run --example generate_fixtures   # writes *-input.docx
cd src-tauri && cargo test zone_pipeline_identifiera zone_pipeline_strukturera zone_pipeline_forklara

# Full Rust suite (zone-count assertion 9→12, drift tests, all pipeline tests)
cd src-tauri && cargo test
cd src-tauri && cargo clippy --all-targets -- -D warnings && cargo fmt --check

# Frontend: identity + drift + smoke
npm test                 # vitest — DropZone.identity (12), help-strings-drift (12)
npm run typecheck && npm run lint
npm run test:e2e         # Playwright smoke — asserts twelve data-zone-id tiles render
```

## What proves each requirement

| Req | Verification |
|---|---|
| FR-001 / SC-001 | `cargo test` zone-count assertion = 12; 3 new `zone_pipeline_*` tests each produce a sidecar (mirrored format) with the zone suffix + markers, source unchanged |
| FR-003 / SC-002 | each pipeline test asserts the citation-free mock output stays citation-free (no `SFS`/`NJA`/`§`/`kap.`); each system-prompt const contains the anti-fabrication clause |
| FR-005 | strukturera pipeline test asserts the four IRAC headings appear in order |
| FR-009 / SC-006 | `disclaimer_paragraph()` returns `Some` for all three; all new Swedish copy humanizer-reviewed before commit |
| FR-010 / SC-004 | Rust `help_strings_drift` + TS `DropZone.identity` / `help-strings-drift` tests pass with 12 zones (slugs/titles/hints/help agree across Rust ↔ JSON ↔ TS) |
| FR-011 / SC-003 | window height 1000 in tauri.conf.json; Playwright smoke renders 12 tiles; manual `npm run tauri dev` confirms all 4 rows show without scrolling |
| FR-012 | constitution.md bumped 1.1.0→1.2.0, re-enumerates twelve zones / 3×4 grid |
| FR-002 / SC-005 | existing no-outbound/privacy audit tests stay green; 0 new deps |

## Manual visual check (BLOCKING per CLAUDE.md "Definition of implemented")

`npm run tauri dev` → confirm: all 12 zones render in a 3×4 grid, all visible at the 1160×1000 launch size without scrolling, the 3 new tiles show their Swedish titles/hints, drag a real file onto one new zone and confirm a sidecar appears + opens. (Requires a Mac GUI session + a pulled model — if unavailable in the headless agent, the automated pipeline tests + Playwright smoke are the substitute, and the manual check is a documented deferral.)
