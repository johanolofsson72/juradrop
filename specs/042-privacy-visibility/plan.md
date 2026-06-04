# Implementation Plan: Privacy Visibility

**Branch**: `main` (register rule: solo direct-push) | **Date**: 2026-06-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/042-privacy-visibility/spec.md` (+ `spec.allium`)

## Summary

One fact base, four surfaces: a static non-interactive privacy line under the zone grid (new `PrivacyBadge` component), amended wizard copy (canonical "din dator" + results/instructions scope — the structure already exists from spec 008), a second chrome-level help entry (`_privacy_help` via the 041 mechanism), and an updated README privacy section. Consistency is enforced by a shared `privacy-facts` constants module + vocabulary-pinning tests. Zero behavior change, zero new outbound, zero deps.

## Technical Context

**Language/Version**: TypeScript 5 / React 18 (frontend), Rust only for the help-mirror consts

**Primary Dependencies**: none new — existing Tailwind tokens, the spec-041 chrome-help mechanism, the spec-008 wizard-strings fixture machinery

**Storage**: N/A — static copy, nothing persisted

**Testing**: vitest (copy pins, fact consistency, render), Playwright (badge visibility across states, a11y), cargo test (help drift mirror)

**Target Platform**: macOS desktop (Tauri 2, WKWebView)

**Project Type**: desktop-app, existing structure

**Performance Goals**: zero impact (static text node)

**Constraints**: window fit (FR-011: 1160×1000 must hold WelcomeCard + instruction field + 3×4 grid + badge without scroll); honest scoping (FR-003)

**Scale/Scope**: 1 new component, 1 new constants module, 1 new help entry ×3 mirrors, ~3 wizard strings amended ×2 mirrors, README section, ~15 new tests

## Constitution Check

| Principle | Verdict | Evidence |
|---|---|---|
| I. Privacy by Architecture | **PASS — this spec is its visibility layer** | Zero new network surface; the feature only *describes* the existing guarantee, honestly scoped (FR-003). |
| II. Zero-CLI | PASS | Copy + static UI. |
| III. Local-Only Inference | PASS | Untouched. |
| IV. Single-User Desktop | PASS | No state, no storage. |
| V. Swedish-First UI | PASS | All new copy Swedish, humanizer-gated; canonical "din dator" (clarified). |
| VI. Native macOS Feel | PASS | frontend-design gate; muted footer line in system tokens, no trust-seal theater. |
| VII. Bundled Sidecar | PASS | Untouched (the wizard download note already explains the model honestly without naming Ollama). |
| VIII. Honest Failure States | PASS — extended to honest *success* claims | No overclaim: the two network uses are named on the detail surfaces. |
| IX. Open Source | PASS | README updated. |

**Violations**: none. Complexity Tracking: empty.

## Project Structure

### Documentation (this feature)

```text
specs/042-privacy-visibility/
├── spec.md / spec.allium     # done
├── plan.md                   # this file
├── research.md               # Phase 0
├── data-model.md             # Phase 1
├── quickstart.md             # Phase 1
├── contracts/
│   └── privacy-copy.md       # the fact base + per-surface rendering contract
└── tasks.md                  # /speckit-tasks output
```

### Source Code (repository root)

```text
src/
├── lib/
│   ├── privacy-facts.ts        # NEW: the fact base — canonical claim strings
│   ├── wizard-strings.ts       # MODIFY: privacy_line + paragraph → canonical scope/vocab
│   └── help-strings.ts         # MODIFY: + PRIVACY_HELP (mirror 3/3)
├── components/
│   ├── PrivacyBadge.tsx        # NEW: static line under the grid (frontend-design gated)
│   ├── App.tsx                 # MODIFY: mount badge below the grid section
│   └── HelpPanel.tsx           # MODIFY: render the privacy entry next to the instruction entry

src-tauri/
├── src/help/zone_help.rs       # MODIFY: + PRIVACY_HELP_TITLE/_BODY consts (mirror 1/3)
├── tests/fixtures/zone-help-strings.json   # MODIFY: + _privacy_help (mirror 2/3)
├── tests/fixtures/wizard-strings.json      # MODIFY: amended wizard strings
└── tests/help_strings_drift.rs # MODIFY: + privacy entry assertion

README.md                        # MODIFY: Privacy guarantees section
src/__tests__/                   # NEW/MODIFY: PrivacyBadge.test.tsx, privacy-facts pins,
                                 #   WizardCopy drift updates, help drift updates
tests/e2e/privacy.spec.ts        # NEW: visibility-across-states + a11y + window-fit
```

**Structure Decision**: existing two-tree layout; the only structural addition is the fact-base module that makes SC-004 mechanically testable.

## Design decisions (Phase 0 summary — rationale in research.md)

1. **Fact base as code** (`privacy-facts.ts`): the badge text, the never-leaves list, and the two network-use descriptions live in ONE exported const; badge and help-entry TS strings derive from it, and vocabulary-pin tests assert the rules (contains "din dator", never contains overclaim phrasing) — SC-004 becomes mechanical.
2. **Badge placement**: full-width muted line directly under the grid `<section>`, same column (`gap-4` rhythm) — `data-privacy-badge` handle, exposed as content (no `aria-hidden`), no `tabIndex`, no link. Compact `text-xs text-muted-foreground`, single line ≈20 px — window fit preserved (research R3).
3. **Wizard amendments, not additions**: `welcome_paragraph` ("lokalt på din Mac" → "lokalt på din dator"), `welcome_privacy_line` scope widened ("Dina dokument, instruktioner och resultat lämnar aldrig din dator."); `welcome_download_note` kept verbatim — it already states one-time + offline (US2/AS2 satisfied since spec 008). Both mirrors (TS + JSON fixture) updated together under the existing byte-for-byte drift test.
4. **Help entry**: exact 041 `_instruction_help` pattern — consts in zone_help.rs, `_privacy_help` fixture key, `PRIVACY_HELP` TS export, sibling section in HelpPanel, dedicated drift assertions both directions.
5. **Rust-side wizard strings**: verify at impl whether a Rust const mirrors wizard-strings.json (spec 008 pattern); update every existing side, never just one.
6. **README**: update "Privacy guarantees" in place to the fact base; the stale nine-zone copy elsewhere in README stays a separate doc-fix candidate (register-noted since 040).

## Verification mapping

| Requirement | Proof |
|---|---|
| FR-001/002, SC-001 | Playwright: badge visible in idle/processing/error/success (emitted snapshots) + with panels open; vitest render |
| FR-003, SC-004 | vitest fact pins: no surface string makes a no-internet-ever claim; all machine references say "din dator"; detail surfaces name both network uses |
| FR-004/005, SC-002 | WizardCopy drift test (updated fixture) + content assertions on privacy_line/download_note |
| FR-006 | Rust + TS help drift assertions for `_privacy_help` |
| FR-007/008 | README updated to the same facts (manual review + quickstart check); canonical-vocab pin covers in-app surfaces |
| FR-009, SC-003 | existing no-egress e2e + CSP pin tests pass unchanged; net deps 0 |
| FR-010, SC-005 | vitest a11y (content exposure) + Playwright accessible-text assertion |
| FR-011 | Playwright: at default viewport, badge AND grid bottom row visible without scroll |
| FR-012 | humanizer + frontend-design gates (process, recorded in tasks) |
