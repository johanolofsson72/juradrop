# Feature Specification: Hygiene Sweep (three carried observations)

**Feature Branch**: `043-hygiene-sweep`

**Created**: 2026-06-05

**Status**: Draft

**Track**: spec-only (no new entities, no new state transitions — fixes expressed as tests/copy)

**Input**: Register row 043 — the three observations carried in the register history since specs 040–042: (1) the spec-028 PAGES purge miss in the help panel's format badges; (2) the README's pre-036 nine-zone/3×3 copy; (3) the spec-017 concurrency_stress 20s-deadline flake.

## Clarifications

### Session 2026-06-05

- Q: How far does the README refresh go — only the flagged lines, or every stale claim found while in there? → A: Every stale claim in README.md (zone count/grid, the 9-row zone table, the frozen "Spec 013 (den här)" status narrative, the "playwright stub" note dead since 033, the docs-map "nine drop zones") — leaving known-stale text because it wasn't itemized would be hygiene theater (auto-picked recommended).
- Q: Flake remedy? → A: Raise the sidecar-settle deadline 20s → 60s with a comment reclassifying it as a hang-guard, not a performance assertion: 12 parallel zone pipelines under full-suite cargo contention legitimately exceed 20s by scheduler starvation; the test's assertions (isolation, contamination, source integrity) are unchanged (auto-picked recommended).
- Q: Should the PAGES fix get a regression pin? → A: Yes — a vitest assertion that the rendered format badges never include PAGES (the purge has now failed silently once; a pin makes the second time impossible) (auto-picked recommended).

## User Scenarios & Testing

### US1 — The help panel stops advertising a format the app refuses (P1)

A user opens the help panel and reads each zone's format badges. PAGES no longer appears — every other surface (hints, error copy, picker filter, README) already says `.pages` is unsupported; the badges were the last surface still lying.

**Acceptance**: badges render DOCX/PDF/TXT/MD/RTF/ODT (Generera: TXT/MD); a test pins PAGES out forever.

### US2 — The README describes the app that exists (P2)

A visitor reads README.md and sees: twelve zones in a 3×4 grid, the full 12-row zone table, six input formats, a status section describing the current state (not spec 013's), a docs map that says twelve zones, and a test-command list without the dead "stub" parenthesis.

**Acceptance**: zero remaining "nio zoner"/"3×3"/nine-drop-zones claims (the constitution's "nine governing principles" stays — that one is true).

### US3 — The full Rust suite passes repeatedly without the spec-017 flake (P2)

`cargo test` runs the entire suite with `concurrency_stress` green consistently — the sidecar-settle deadline tolerates full-suite scheduler contention while still failing fast on a genuine hang.

**Acceptance**: deadline 60s, comment explains the reclassification; full suite green in consecutive runs.

### Edge Cases

- The README zone-table additions (rows 10–12) must reuse the established one-line descriptions consistent with help copy — no new unreviewed Swedish marketing.
- The HelpPanel comment cites "spec-009 seven-format set" — also stale; the comment is corrected alongside the constant.
- The 60s deadline must not mask real regressions: it remains a per-zone bound inside a test that asserts content correctness, not timing.

## Requirements

- **FR-001**: `ALL_FORMATS` in the help panel MUST list exactly the six supported input formats; the stale comment corrected.
- **FR-002**: A test MUST pin that no rendered format badge says PAGES.
- **FR-003**: README.md MUST be consistent with the twelve-zone 3×4 reality everywhere, including the zone table (12 rows), intro, status narrative, docs map, and test-command notes.
- **FR-004**: The concurrency_stress settle deadline MUST be 60s with a hang-guard comment; no other test semantics change.
- **FR-005**: All gates green after the sweep; no behavior changes outside the badge text.

## Success Criteria

- **SC-001**: `grep -i "pages" src/components/HelpPanel.tsx` shows no badge entry; the pin test fails if it returns.
- **SC-002**: `grep -n "nio zoner\|3×3" README.md` returns nothing; the zone table has 12 rows.
- **SC-003**: Two consecutive full `cargo test` runs green (the flake fired ~3/8 before).
- **SC-004**: Existing suites unchanged otherwise: 571 Rust + 431 vitest + 44 Playwright stay green (± the new pin).

## Assumptions

- No `.allium`, no `/tla` (spec-only triage: zero new entities/states — constraints expressed as tests).
- Swedish copy added to the README zone table mirrors existing humanizer-reviewed help strings; no novel copy requiring a fresh humanizer pass beyond consistency checking.
