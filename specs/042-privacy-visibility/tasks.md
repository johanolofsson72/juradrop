# Tasks: Privacy Visibility

**Input**: spec.md (3 user stories), plan.md, research.md (R1–R7), data-model.md, contracts/privacy-copy.md (P-1…P-10)

**Tests**: REQUIRED by project constitution. Included.

## Phase 1: Setup

- [ ] T001 Invoke the `frontend-design` skill (BLOCKING gate) for the PrivacyBadge — muted single `text-xs` line under the grid per research R2/R3, no trust-seal iconography, dark/light legible; record decisions in the `src/components/PrivacyBadge.tsx` header at T004
- [ ] T002 Invoke the `humanizer` skill (BLOCKING gate) on the draft copy set: badge line (R2 draft), amended `welcome_paragraph` + `welcome_privacy_line`, `PRIVACY_HELP_TITLE`/`_BODY`, README section wording — apply the reviewed wording in all subsequent tasks

## Phase 2: Foundational

- [ ] T003 Create `src/lib/privacy-facts.ts` per data-model: `PRIVACY_BADGE_TEXT`, `PRIVACY_NEVER_LEAVES` (3 items), `PRIVACY_NETWORK_USES` (exactly 2) with the humanizer-reviewed strings; vitest `src/__tests__/privacy-facts.test.ts`: P-7 vocabulary pin ("din dator" present, "din Mac" absent), P-6 overclaim-pattern guard with the explicit allowlist (research R7), P-8 exactly-two-network-uses alarm

## Phase 3: User Story 1 — The window answers "where does my document go?" (P1) 🎯 MVP

**Goal**: persistent, static, non-interactive Swedish privacy line under the grid, visible in every state, window still fits.

**Independent test**: render + Playwright state sweep.

- [ ] T004 [US1] Create `src/components/PrivacyBadge.tsx` per T001 design: `<p data-privacy-badge>` rendering `PRIVACY_BADGE_TEXT`, no link/tabIndex/handlers, content-exposed to AT; mount in `src/App.tsx` directly after the grid `<section>` (same conditional branch — co-location IS the BadgeAlwaysWithGrid invariant)
- [ ] T005 [P] [US1] Vitest `src/__tests__/PrivacyBadge.test.tsx`: renders the fact-base text verbatim, no interactive elements inside (no a/button/tabindex), not aria-hidden (P-2), present in the App ready-state tree alongside the grid (extend/verify via existing App.test.tsx patterns)
- [ ] T006 [US1] Playwright `tests/e2e/privacy.spec.ts`: badge visible at ready state with accessible text; emit processing/error/success zone snapshots → badge text unchanged (P-1/FR-002); badge + bottom grid row bounding boxes within the default viewport without scroll (P-10/FR-011); badge still in DOM with help panel open

## Phase 4: User Story 2 — Wizard explains WHY it works offline (P2)

**Goal**: canonical vocabulary + widened never-leaves scope in the wizard; download note kept (already states one-time + offline).

**Independent test**: wizard copy drift + content pins.

- [ ] T007 [US2] Amend `src/lib/wizard-strings.ts` + `src-tauri/tests/fixtures/wizard-strings.json` together (R4): `welcome_paragraph` → "lokalt på din dator" variant, `welcome_privacy_line` → "Dina dokument, instruktioner och resultat lämnar aldrig din dator." (humanizer-reviewed final wording from T002); grep for any Rust-side mirror of the fixture and update it too; `welcome_download_note` untouched
- [ ] T008 [P] [US2] Update `src/__tests__/WizardCopy.errors.test.tsx` (and any fixture-pinning Rust test) for the amended strings; add content pins: privacy_line mentions dokument+resultat+"din dator"; download_note still states the one-time download + offline-after meaning (P-3/P-4); **no `din Mac` remains anywhere in `WIZARD_STRINGS`** (analyze C1 — full-set vocabulary sweep, not just the two amended keys)

## Phase 5: User Story 3 — Help and README carry the honest fine print (P3)

**Goal**: `_privacy_help` chrome entry (3-way mirror) + README section, both naming BOTH network uses.

**Independent test**: drift assertions both directions + content pins.

- [ ] T009 [US3] Add the privacy help entry across the three mirrors (exact 041 pattern): `PRIVACY_HELP_TITLE`/`PRIVACY_HELP_BODY` consts in `src-tauri/src/help/zone_help.rs`, `_privacy_help` key in `src-tauri/tests/fixtures/zone-help-strings.json`, `PRIVACY_HELP` export in `src/lib/help-strings.ts`; render as `<section data-privacy-help>` in `src/components/HelpPanel.tsx` after the instruction entry
- [ ] T010 [P] [US3] Drift assertions: `privacy_help_matches_fixture` in `src-tauri/tests/help_strings_drift.rs` + the TS twin in `src/__tests__/help-strings-drift.test.ts`; content pins: body names the model download AND the update check (P-5) and uses "din dator" (P-7)
- [ ] T011 [P] [US3] Update `README.md` "Privacy guarantees" section to the fact base (F1–F4, same facts as in-app); do NOT touch the stale nine-zone copy elsewhere (separate register-noted doc-fix)

## Phase 6: Polish & gates

- [ ] T012 Destructive/negative sweep in `tests/e2e/privacy.spec.ts` (scaled to a static feature — the interactive attack surface is nil by design): badge has zero focusable descendants (Tab from instruction field lands on zone controls, never the badge); badge text node cannot be triggered (click → no invocation recorded); panels open/close cycle leaves badge intact; viewport shrink (sm breakpoint) keeps badge rendered (no responsive-hide regression)
- [ ] T013 Full gate sweep: `npm run lint && npm run typecheck && npm test`, `cd src-tauri && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`, `npm run test:e2e`; then `graphify update .`
- [ ] T014 Manual quickstart per `quickstart.md` (real `tauri dev`, light/dark, fresh-install wizard) — DEFER to user (headless agent); note in register tick

## Dependencies

```
T001, T002 → T003 → T004 → T005, T006
T002 → T007 → T008
T002 → T009 → T010
T011 after T002 (wording) — independent of code tasks
T012 after T006; T013 after all; T014 deferred
```

US order: US1 (MVP) → US2 → US3. US2/US3 independent of US1 (different files) — parallelizable after T002/T003.

## Parallel examples

- After T003: T004 ∥ T007 ∥ T009 ∥ T011
- After T004: T005 ∥ T006
- T008 ∥ T010 once their impl tasks land

## Implementation strategy

MVP = Phases 1–3 (badge visible, tested). US2/US3 are copy + mirrors. /tla expected to hit the triviality gate (zero states — static content), per the light track.
