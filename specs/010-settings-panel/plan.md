# Implementation Plan: Settings Panel (gear-icon slide-in)

**Branch**: `main` (solo direct-push, no feature branch — see `project-workflow.md`) | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-settings-panel/spec.md`

## Summary

A gear-icon slide-in panel with three sections:
1. **Model tier selector** — `Snabb` / `Smart` / `Stor`, mapping to `llama3.2:1b` / `gemma3:4b` / `gemma3:12b`. Only pulled tiers are selectable as radios; unpulled tiers display a `Ladda ned` button that triggers the spec 008 wizard. Tier choice persists to disk and applies to subsequent zone dispatches without restart.
2. **Appearance** — read-only display of the current OS appearance (`Ljust läge (följer systemet)` / `Mörkt läge (följer systemet)`), updating live within 500 ms on OS change.
3. **About** — app name, version, MIT license short-line, `Visa utgåvor på GitHub` link that opens the default browser via `shell.open`.

The panel slides in from the right edge with the existing motion tokens (no new design system entries). Disabled when a higher-priority modal/wizard is up (spec 007 update-restart or spec 008 first-run). Persistence is one tiny JSON object in `app_data_dir` containing exactly `schema_version` + `model_tier` — zero user content, zero analytics IDs.

The implementation grafts a new `SettingsSnapshot` entity onto the existing dispatch path: zone dispatch reads the snapshot's `model_tier` at dispatch time instead of the hard-coded `DEFAULT_MODEL` constant in `src-tauri/src/sidecar/commands.rs`. In-flight runs are immune to tier switches; only the next dispatch sees the new tier.

## Technical Context

**Language/Version**: Rust 1.75+ (`src-tauri/`), TypeScript 5.x + React 18 (`src/`).

**Primary Dependencies**:
- `tauri` 2.x with `tauri-plugin-shell` (for `shell.open` of GitHub Releases URL — already in dep tree from spec 007 update-checker pattern)
- `tauri-plugin-fs` (for `app_data_dir` resolution — already enabled per spec 008)
- `serde` + `serde_json` (already in dep tree)
- `zustand` for new `useSettingsStore` (already in dep tree per spec 008's `useWizardStore`)
- `@tauri-apps/api/event` + `@tauri-apps/api/core` for command + event plumbing (already used)
- No new crates introduced. **Net dep delta: 0.**

**Storage**: One JSON file at `${app_data_dir}/settings.json` (~50 bytes). Schema: `{"schema_version": 1, "model_tier": "Smart"}`. Owned by Rust; React reads via Tauri command.

**Testing**:
- Rust: `cargo test` for the tier-map module, settings file IO (round-trip + malformed-file fallback), schema-shape assertion, dispatch-uses-snapshot test.
- React: `vitest` for `useSettingsStore`, the panel-visibility state machine, the appearance projection, the unpulled-tier rendering.
- Playwright: one smoke test driving the actual built app — open panel, switch from Smart to (pulled) Snabb mock, close, drop a fixture file, assert sidecar called with `llama3.2:1b`.

**Target Platform**: macOS 11+ (matches the rest of the app — Tauri 2.x baseline).

**Project Type**: Desktop app (Tauri + React).

**Performance Goals**:
- SC-001: tier change → effective on next dispatch in ≤ 2 s.
- SC-003: panel open/close animation within `design-system/MASTER.md` motion budget.
- SC-004: OS appearance change reflected in panel within ≤ 500 ms.

**Constraints**:
- Principle I (Privacy by Architecture): zero outbound traffic from panel interactions; settings file zero user content.
- Principle III (Local-Only Inference): only pulled models are selectable (drives FR-012's `Ladda ned` affordance instead of immediate-select).
- Principle VI (Native macOS Feel): SF Pro, no custom fonts, follow OS appearance.
- Principle V (Swedish-First UI): all panel copy in Swedish; code/comments English.

**Scale/Scope**:
- 4 panel-visibility states, 6 transitions
- 3 tier options × 3 helper sentences × 3 size badges
- 1 read-only appearance row
- 1 About section with 3 static rows + 1 link
- ~10 new files (Rust: tier_map, settings/file_io, settings/commands; React: SettingsPanel/{root,Header,ModelTierSection,AppearanceSection,AboutSection}, useSettingsStore, panel visibility hook, types)
- ~6 modified files (sidecar/commands.rs swap DEFAULT_MODEL → snapshot lookup, App.tsx mount panel, types.ts add ModelTier enum mirror, fixtures/zone-error-strings.json add panel keys, capabilities/main.json add shell.open scope)
- Estimated ~600 LOC Rust + ~800 LOC TS+TSX + ~150 LOC test code

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| **I. Privacy by Architecture** | PASS | Settings file contains exactly 2 keys (`schema_version`, `model_tier`), zero user content. No outbound HTTP from any panel interaction. `shell.open` for the GitHub link is a process spawn, not an outbound socket from JuraDrop. Spec 008 download flow is reused for model pulls — no new outbound surface introduced by this spec. Invariants `SettingsFileNeverContainsUserContent` and `NoOutboundCallsFromPanel` formalise this. |
| **II. Zero-CLI Install** | PASS | The panel is a UI affordance only. No Terminal interaction, no shell commands surfaced. The spec 008 wizard (which we reuse for model pulls) is already Zero-CLI compliant. |
| **III. Local-Only Inference** | PASS (after Q2 amendment) | Initial Clarification Q2 conflicted with "selection only between locally-pulled models". Amended to: unpulled tiers display `Ladda ned` button, NOT a selectable radio. Selectable set = pulled set, formalised in `SelectableSetEqualsPulledSet` invariant. Ollama base URL constraint (`127.0.0.1:11434`) preserved. |
| **IV. Single-User Desktop App** | PASS | Settings live in `app_data_dir` (per-user). No accounts, no multi-tenancy. The window IS the app. |
| **V. Swedish-First UI, English-First Code** | PASS | Every user-facing string in the panel is Swedish (FR-024). Code, function names, file names, comments — English. JSON keys in `settings.json` are English (`schema_version`, `model_tier`). |
| **VI. Native macOS Feel** | PASS | Uses existing design tokens. Appearance section ENFORCES "follow OS" with read-only display + no manual override (FR-014). SF Pro typography. |
| **VII. Bundled Sidecar — Ollama Internal Plumbing** | PASS | The panel exposes labelled tiers (`Snabb` / `Smart` / `Stor`), never raw model tags. The constitution explicitly endorses this in Principle VII: "The Settings panel MAY expose model selection ('Snabb / Smart / Stor') but never raw model tags like `llama3.2:3b-instruct-q4_K_M`". Mapping lives in Rust (`tier_map.rs`); React receives the typed enum, never the raw IDs. |
| **VIII. Honest Failure States** | PASS | Missing settings file → silent fallback to defaults (no Swedish error — first-run state is normal). Malformed file → silent fallback to defaults + debug-only console warning. Pull failure during `Ladda ned` → reuses spec 008 wizard's honest Swedish error states. GitHub link open failure → silent no-op + dev-only warning (FR-017 + edge case). |
| **IX. Open Source, Free, No Lock-In** | PASS | The About section surfaces the license + source link. No paywall, no Pro tier. Settings file is plain JSON — user can hand-edit if they ever need to. |

**Verdict: 9/9 pass.** No Complexity Tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/010-settings-panel/
├── plan.md              # This file
├── spec.md              # Feature spec (post-clarify, with Clarifications section)
├── spec.allium          # Formal Allium spec (passes `allium check`)
├── research.md          # Phase 0: research findings
├── data-model.md        # Phase 1: SettingsSnapshot, SettingsFile, ModelTier, PanelVisibility
├── quickstart.md        # Phase 1: 5 user flows the implementation must satisfy
├── contracts/
│   ├── settings-commands.md       # Tauri command contracts (get/set/load/save)
│   ├── settings-file-schema.md    # JSON shape on disk (strict)
│   └── panel-events.md            # React → Tauri event/command surface
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit-tasks command — NOT in this file)
```

### Source Code (repository root)

```text
src-tauri/
├── src/
│   ├── settings/                       # NEW module
│   │   ├── mod.rs                      # Module root, re-exports
│   │   ├── tier_map.rs                 # ModelTier enum + Snabb/Smart/Stor → model_id mapping
│   │   ├── snapshot.rs                 # SettingsSnapshot struct (in-memory, serde)
│   │   ├── file_io.rs                  # load/save settings.json from app_data_dir
│   │   └── commands.rs                 # Tauri commands: get_settings, set_model_tier, get_tier_pull_state
│   ├── sidecar/
│   │   └── commands.rs                 # MODIFIED: dispatch path reads snapshot, not DEFAULT_MODEL constant
│   └── lib.rs                          # MODIFIED: register settings::commands::* in invoke handler, load snapshot on setup
├── capabilities/
│   └── main.json                       # MODIFIED: shell.open scope adds https://github.com/johanolofsson72/juradrop/releases

src/
├── components/
│   ├── SettingsPanel/                  # NEW component family
│   │   ├── SettingsPanel.tsx           # Root — slide-in container, scrim, Esc handler, focus trap
│   │   ├── SettingsPanelHeader.tsx     # Title + close-X button
│   │   ├── ModelTierSection.tsx        # 3-row tier selector with conditional radio/Ladda-ned rendering
│   │   ├── TierRow.tsx                 # One row — radio OR Ladda-ned + helper sentence + size badge
│   │   ├── AppearanceSection.tsx       # Read-only appearance row, subscribes to prefers-color-scheme
│   │   ├── AboutSection.tsx            # App name + version + license + GitHub link
│   │   └── index.ts                    # Public exports
│   └── GearIcon.tsx                    # NEW — top-right chrome bar gear button, calls openPanel()
├── hooks/
│   ├── useSettingsPanel.ts             # NEW — panel visibility state machine (4 states, 6 transitions)
│   ├── useSystemAppearance.ts          # NEW — subscribes to (prefers-color-scheme: dark) MediaQueryList
│   └── useCmdComma.ts                  # NEW — registers Cmd+, keyboard shortcut
├── lib/
│   ├── settings.ts                     # NEW — Tauri command wrappers + types
│   └── tier-strings.ts                 # NEW — Swedish helper sentences, pulled from fixture
├── store/
│   └── useSettingsStore.ts             # NEW — Zustand store mirroring SettingsSnapshot
├── types/
│   └── settings.ts                     # NEW — ModelTier enum, SettingsSnapshot type, panel state types
└── App.tsx                             # MODIFIED: mount SettingsPanel + GearIcon, wire Cmd+,, gate disabled state

fixtures/
└── zone-error-strings.json             # MODIFIED: append panel string keys (gear_label, panel_title, tier helper sentences, appearance row text, about labels, ladda_ned button label, size badges)

src-tauri/tests/
├── settings_tier_map.rs                # NEW — tier_map → model_id mapping coverage (all 3 tiers)
├── settings_file_io.rs                 # NEW — round-trip, missing-file fallback, malformed-file fallback, schema-shape strict-fixture assertion
├── settings_invariants.rs              # NEW — SettingsFileHasExactlyTwoFields, SettingsFileNeverContainsUserContent, NoLibraryApplicationSupportLiteralInBackend
└── dispatch_reads_snapshot.rs          # NEW — DispatchUsesSnapshotNotConstant, InFlightRunsImmuneToTierSwitch

src/__tests__/
├── useSettingsStore.test.ts            # NEW — store mutations, persistence call shape
├── useSettingsPanel.test.tsx           # NEW — state machine: 4 states × 6 transitions × coalescing
├── useSystemAppearance.test.tsx        # NEW — fake-timer test of ≤ 500 ms reflection (SC-004)
├── SettingsPanel.test.tsx              # NEW — functional + 8 destructive scenarios
├── ModelTierSection.test.tsx           # NEW — radio mode vs Ladda-ned mode rendering per pull-state
├── AppearanceSection.test.tsx          # NEW — light/dark text, no interactive descendants (FR-014)
├── AboutSection.test.tsx               # NEW — version pin matches, GitHub link goes via shell.open
└── settings-strings-drift.test.ts      # NEW — extends T035-lineage drift test to panel strings

tests/
└── playwright/
    └── settings_panel_smoke.spec.ts    # NEW — one end-to-end Playwright test (open panel, switch tier, drop file, assert dispatched model_id)
```

**Structure Decision**: Follows the existing Tauri-2.x + React layout that specs 003–009 established. New code lives in:
- `src-tauri/src/settings/` (a brand-new module — no existing settings code to extend)
- `src/components/SettingsPanel/` (a new component family parallel to the existing `WelcomeWizard` / `FirstRunProgress` from spec 008)
- `src/hooks/` (three new hooks alongside the existing spec 008 hooks)
- `src/store/`, `src/lib/`, `src/types/` (one new file each, no restructuring)

Two files in `src-tauri/src/sidecar/` are modified to make the dispatch path read the snapshot. One file in `src-tauri/capabilities/` adds the `shell.open` URL scope. Everything else is additive.

## Phase 0: Outline & Research

See [research.md](research.md) for the full set of findings. Summary:

- **R-001 / R-002 / R-003**: Three tier model IDs are pinned in Clarification Q1 — no further model-choice research needed. Verified that `llama3.2:1b`, `gemma3:4b`, `gemma3:12b` all exist in the default Ollama registry and pull cleanly via the spec 008 wizard's existing code path.
- **R-004**: Tauri `app_data_dir` resolution on macOS resolves to `~/Library/Application Support/<bundle-id>/`. Verified this is what spec 008 already uses for the wizard's "first-run complete" marker — same directory, same API.
- **R-005**: Tauri `shell.open` requires the URL to be in the `capabilities/main.json` scope. Spec 007's updater pattern shows the existing form; one additional scope entry covers `https://github.com/johanolofsson72/juradrop/releases`.
- **R-006**: `prefers-color-scheme` media query is the standard way to listen for OS appearance changes. React 18's `useSyncExternalStore` is the idiomatic hook for this (avoids tearing during concurrent renders).
- **R-007**: Cmd+, as the macOS preferences shortcut — Tauri's `tauri::menu::AboutMetadata` doesn't bind it automatically; we register it ourselves via a global keyboard listener in `useCmdComma`.
- **R-008**: Animation tokens already exist in `design-system/MASTER.md` (the spec 008 wizard uses them). No new motion values needed.
- **R-009**: Cross-language drift fixture — the existing `fixtures/zone-error-strings.json` lineage extends naturally with new panel-string keys. Per-language readers (Rust `SettingsPanelStrings`, TS `SETTINGS_PANEL_STRINGS`) follow the spec 009 pattern.
- **R-010**: Auto-select-after-pull pattern — when the spec 008 wizard fires from a `Ladda ned` click, we need to remember the source (which tier triggered it). A `wizard_source: panel_triggered | first_run | dispatch_triggered` field on the wizard's invocation is the cleanest way; the wizard's success callback then routes back to the panel and auto-selects the tier.

## Phase 1: Design & Contracts

See:
- [data-model.md](data-model.md) — `SettingsSnapshot`, `SettingsFile`, `ModelTier`, `PanelVisibility`, `TierMapping`, `TierRowMode`
- [contracts/settings-commands.md](contracts/settings-commands.md) — `get_settings`, `set_model_tier`, `get_tier_pull_state`, `trigger_tier_download`
- [contracts/settings-file-schema.md](contracts/settings-file-schema.md) — strict JSON schema with exactly 2 fields
- [contracts/panel-events.md](contracts/panel-events.md) — React → Rust event surface, including the spec 008 wizard's new `panel_triggered` source flag
- [quickstart.md](quickstart.md) — 5 user flows the implementation must satisfy

### Re-check Constitution after Phase 1 design

| Principle | Re-check status | Notes |
|---|---|---|
| **I. Privacy by Architecture** | PASS | `contracts/settings-file-schema.md` pins exactly 2 fields; no field accepts a path, hash, or analytics token. The new `trigger_tier_download` command delegates to the spec 008 wizard's existing model-pull code path — no new HTTP client, no new outbound surface. |
| **III. Local-Only Inference** | PASS | `contracts/settings-commands.md` `set_model_tier` rejects with `TierNotPulled` error if the requested tier's model isn't on disk. `TierRowMode` from `data-model.md` is `radio_selectable` only when pulled, otherwise `download_button`. UI cannot bypass via the command surface either. |
| **VII. Bundled Sidecar** | PASS | Raw model IDs are never sent across the Tauri boundary in the `set_model_tier` payload — the payload is the typed `ModelTier` enum. The Rust layer maps to the model ID internally. |

All other gates remain PASS from the pre-research check. No changes.

## Complexity Tracking

No constitution violations to justify. Empty.
