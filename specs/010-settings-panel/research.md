# Phase 0 Research — Spec 010 Settings Panel

**Date**: 2026-05-28
**Status**: Complete (all R-001..R-010 resolved; no `NEEDS CLARIFICATION` remaining)

## R-001 — Snabb tier model choice (`llama3.2:1b`)

**Decision**: `llama3.2:1b` (~1.3 GB on disk, ~600 MB quantised, Meta Llama Community License).

**Rationale**:
- Smallest broadly-supported Ollama instruct model with non-trivial Swedish capability (Llama 3.2 added 8 official languages; Swedish is not official but performs adequately for short text). For longer or harder text, the user has Smart and Stor.
- 1.3 GB pull is fast enough on consumer Swedish broadband (15–30 s typical) that the spec 008 wizard's existing UX handles it gracefully.
- Already exists in the default Ollama registry — no custom registry, no manual model creation. Spec 008's pull code path works unchanged.
- Cold-inference latency on M1/M2 Air (~1 s first token) is dramatically below `gemma3:4b` (~3 s) and `gemma3:12b` (~9 s) — gives the "Snabb" label real meaning.

**Alternatives considered**:
- `llama3.2:3b` — middle-sized; rejected because it's only marginally smaller than `gemma3:4b`, so it doesn't justify a separate tier.
- `tinyllama:1.1b` — smaller but instruction-tuning is weaker; produced visibly worse Swedish in spot-test.
- `qwen2.5:0.5b` — smallest viable, but Swedish quality cliff makes it unsuitable for legal text even at the "Snabb" tier (anonymisation in particular needs decent NER).

## R-002 — Smart tier model choice (`gemma3:4b`)

**Decision**: `gemma3:4b` (~3.3 GB on disk, Apache 2.0).

**Rationale**:
- This is the existing project default — `src-tauri/src/sidecar/commands.rs` has `pub(crate) const DEFAULT_MODEL: &str = "gemma3:4b";` and every prompt in `src-tauri/src/prompts/` is tuned for it. Keeping Smart on this model means **zero** prompt re-tuning for the default tier.
- Already pulled on first launch by the spec 008 wizard.
- Quality on Swedish legal text was the original pre-MVP benchmark choice (per the constitution's Technology Stack section).

**Alternatives considered**:
- `gemma3:7b` (if/when published) — heavier than 4b; would either replace Smart or sit between Smart and Stor. Held for a future spec.
- `llama3.2:3b` — comparable size; rejected because spec 003/004's prompts were tuned for gemma3's opening-paragraph quirks ("Här är en sammanfattning:" filter in `zone_id.rs`). Switching would require re-tuning every prompt.
- `phi3.5:3.8b` — competitive but the existing prompts target gemma3 specifically; the "Smart" tier must not regress relative to today.

## R-003 — Stor tier model choice (`gemma3:12b`)

**Decision**: `gemma3:12b` (~8.1 GB on disk, Apache 2.0).

**Rationale**:
- Same family as Smart (`gemma3:4b`) — so the existing prompts in `src-tauri/src/prompts/` work without modification. The Stor tier produces better-reasoned outputs but speaks in the same voice.
- 8.1 GB pull is the upper bound of what consumer broadband + a law student's SSD can comfortably accommodate. Larger models (gemma3:27b at ~17 GB) would push too many users into the "abandons during download" failure mode.
- Inference latency on M1 Air (~9 s first token) is slower than Smart but tolerable for the explicit "I'm willing to wait for quality" tier.

**Alternatives considered**:
- `llama3.1:8b` — comparable size; rejected for the same family-consistency reason as R-001.
- `gemma3:27b` — too large for consumer download and inference; would require a 16 GB+ Mac to run smoothly.
- `mistral-nemo:12b` — comparable; rejected because gemma3 is already the project's flagship family.

## R-004 — Persistence location (`app_data_dir`)

**Decision**: Resolve via Tauri's `app.path().app_data_dir()` (Tauri 2.x API). Filename: `settings.json` (no version suffix in the filename — version lives in the JSON `schema_version` field).

**Rationale**:
- Tauri's `app_data_dir` resolves to `~/Library/Application Support/com.juradrop.app/` on macOS — the standard location for per-user app data.
- Spec 008 already uses this directory for the wizard's "first-run complete" marker (`first_run_complete.txt`). Reusing the same directory means no new directory creation logic, no new path-not-found error paths.
- Cross-platform if we ever ship beyond macOS (Linux: `~/.config/`, Windows: `%APPDATA%`) — but JuraDrop is macOS-only by constitution, so this is theoretical.

**Alternatives considered**:
- `app_config_dir` (separate config-vs-data convention) — overkill for 50 bytes of state. Spec 008's choice was `app_data_dir`; consistency wins.
- A SQLite database — laughable overkill for one tier choice.
- `localStorage` in the WKWebView — works but persistence semantics are fragile (Safari can purge web storage under disk pressure). Real disk file is more robust.

## R-005 — `shell.open` capability scope

**Decision**: Add one entry to `src-tauri/capabilities/main.json` under the `shell:default` permission's `open` scope: `"https://github.com/johanolofsson72/juradrop/releases"`.

**Rationale**:
- Tauri 2.x's `shell:default` permission denies `shell.open` for any URL not explicitly scoped (security default).
- A single literal URL is the tightest possible scope. We never need to open arbitrary URLs from the panel — only this one.
- Spec 007's auto-updater pattern already uses a scoped `shell.open` for the GitHub release notes URL; this is the same pattern.

**Alternatives considered**:
- Scope the entire `https://github.com/johanolofsson72/juradrop/**` domain — broader than needed and a precedent for laziness. Tight scope wins.
- Use `webbrowser` Rust crate instead of `shell.open` — adds a dep, duplicates Tauri's built-in.

## R-006 — System appearance subscription

**Decision**: Use `window.matchMedia('(prefers-color-scheme: dark)')` wrapped in React 18's `useSyncExternalStore` hook.

**Rationale**:
- `useSyncExternalStore` is purpose-built for subscribing to external (non-React) state stores like media-query listeners. Solves the tearing problem (a concurrent render might otherwise see two different appearance values mid-tree).
- The MediaQueryList API's `addEventListener('change', ...)` fires synchronously on OS appearance change, well under SC-004's 500 ms budget.
- No polling, no setInterval, no manual cleanup gymnastics.

**Alternatives considered**:
- A custom `useEffect` + `addEventListener` hook — works, but is the pre-React-18 idiom and has the tearing problem under concurrent rendering.
- A Tauri command that returns the current appearance — overkill (one IPC round-trip for a value the browser already has).
- Tauri's `app.theme()` API — gives the same answer but only at app launch; doesn't fire change events. Combine with media query for change detection? No — too many moving parts for one value.

## R-007 — Cmd+, keyboard shortcut

**Decision**: Register a global `keydown` listener in `useCmdComma` hook; listen for `event.metaKey && event.key === ','`; call `event.preventDefault()` and dispatch `togglePanel()`. Mount the hook once at App.tsx level.

**Rationale**:
- macOS-standard preferences shortcut. Users expect it.
- Tauri 2.x's menu API can bind keyboard shortcuts to menu items, but we don't have a JuraDrop menu bar (Principle IV — "The window IS the app"). So a global keydown listener is the right primitive.
- `event.preventDefault()` is important: WKWebView's default Cmd+, behaviour is "do nothing", but we still call preventDefault to be explicit and prevent any future browser-level binding.

**Alternatives considered**:
- Tauri's `register_global_shortcut` API — registers OS-wide shortcuts (would steal Cmd+, from every other app while JuraDrop runs). Wrong scope.
- Bind in the panel itself (only fires when panel is focused) — defeats the purpose; user can't open the panel via Cmd+, if the shortcut only works once the panel is open.

## R-008 — Animation tokens

**Decision**: Reuse the slide-in / fade-in / scale-up tokens that already exist in `design-system/MASTER.md` from spec 008's wizard animations. No new tokens.

**Rationale**:
- The spec 008 wizard uses these exact tokens. Reusing them gives the panel the same "this app moves consistently" feel.
- Avoids adding to the design system without a documented design-system change.

**Alternatives considered**:
- Bespoke "slide-from-right-edge" easing curve — would need a design-system addition and a frontend-design skill round-trip for one panel. Out of scope.

## R-009 — Cross-language drift fixture

**Decision**: Extend the existing `fixtures/zone-error-strings.json` with a new top-level `settings_panel` key containing all panel strings. Both Rust (`SettingsPanelStrings` struct in `src-tauri/src/settings/strings.rs`) and TypeScript (`SETTINGS_PANEL_STRINGS` constant in `src/lib/tier-strings.ts`) read from this fixture.

**Rationale**:
- Same lineage as the T035 drift test from spec 004 / extended in spec 005 / extended in spec 009.
- One fixture file, two consumers, one CI test — adding a string on one side without the other fails CI deterministically.

**Alternatives considered**:
- A separate `fixtures/settings-panel-strings.json` — splitting fixtures complicates the drift test runner. Single fixture wins.
- Inline strings in both languages — exactly the drift mode this lineage exists to prevent.

## R-010 — Auto-select-after-pull pattern

**Decision**: Extend the spec 008 `FirstRunWizard` invocation payload with a `source: panel_triggered | first_run | dispatch_triggered` field (new field, default `first_run` for backwards compatibility with the existing wizard call). When the wizard completes successfully AND `source = panel_triggered`, the wizard's success callback emits a Tauri event `settings://tier_pulled` with the target tier ID. The settings store listens for this event and auto-selects the tier.

**Rationale**:
- Keeps the spec 008 wizard unaware of the panel — it doesn't import settings types, it just adds one new field and one new event emission gated on the source. Loose coupling.
- The settings store owns the "after pull, what to do" logic — single responsibility.
- Event-driven means no polling, no shared-state mutation across module boundaries.

**Alternatives considered**:
- Pass a closure to the wizard — TypeScript closures don't survive Tauri command boundaries. Not portable.
- Add `target_tier` to the snapshot pre-emptively at click time, then validate after pull — leaves the snapshot in an "intended but not yet realised" state that complicates the `SelectableSetEqualsPulledSet` invariant. Cleaner to commit only after success.
- Poll `get_tier_pull_state` from the panel every 1 s while the wizard is open — wasteful and racy.
