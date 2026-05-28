# Feature Specification: Settings Panel (gear-icon slide-in)

**Feature Branch**: `main` (solo direct-push; no feature branch — see `project-workflow` memory)

**Created**: 2026-05-28

**Status**: Draft

**Input**: User description: "settings-panel — gear-icon slide-in panel accessed from the main window. Contains three sections: (1) model selector with three named tiers — 'Snabb' (fast, small model — gemma3:4b or llama3.2:3b), 'Smart' (default balanced model), 'Stor' (large, slower, higher-quality model); selecting a tier persists the choice and applies it to subsequent zone runs without restart. (2) appearance section that displays current system appearance (light/dark) as read-only — JuraDrop follows the OS, no manual override. (3) About section showing app name, current version, link to GitHub Releases (in-app — opens in default browser), and the open-source license. Panel slides in from the right edge with native macOS easing, dismiss via Esc / clicking outside / close-X. Settings persist across launches in the standard macOS app support directory. Swedish UI throughout. No telemetry, no cloud calls — Principle I holds."

## Clarifications

### Session 2026-05-28

- Q: Which concrete Ollama model IDs back the three tiers? → A: **Snabb → `llama3.2:1b`** (~1.3 GB, smallest pull, fastest cold inference, ships in the Ollama default registry), **Smart → `gemma3:4b`** (~3.3 GB, the existing project default — matches `DEFAULT_MODEL` in `src-tauri/src/sidecar/commands.rs`, every prompt in `src-tauri/src/prompts/` already references this model), **Stor → `gemma3:12b`** (~8.1 GB, same family as Smart so prompt behaviour is consistent — only size/quality changes, not the model's voice). Mapping lives in one new central location in `src-tauri/`.
- Q: When the user picks a tier whose Ollama model is not yet pulled, what happens? → A: **Show an explicit "Ladda ned" affordance on unpulled tiers; clicking it triggers the spec 008 wizard immediately** (constitution alignment — Principle III says "Model selection MAY be exposed in settings, but only between locally-pulled models", so the *selectable* set is the pulled set). All three tiers are always *visible* (discoverability), but unpulled tiers display a size badge ("~1.3 GB" / "~3.3 GB" / "~8.1 GB") and a "Ladda ned" button instead of an immediately-selectable radio. Clicking "Ladda ned" hands control to the existing spec 008 first-run-wizard download flow; on completion, the tier becomes selectable and is auto-selected (zero extra clicks). No background pre-download, no surprise outbound traffic — every byte transferred is triggered by an explicit user click. _(Supersedes the earlier draft of this clarification that deferred download to the next zone run; that version conflicted with Principle III.)_
- Q: What exact Swedish helper sentence sits under each tier label (≤ 80 chars each)? → A: **Snabb → "Snabbast och minst. Bra för korta texter."** (44 chars). **Smart → "Standardvalet. Bra balans mellan fart och kvalitet."** (51 chars). **Stor → "Bästa kvaliteten. Tar längre tid och mer plats på disken."** (58 chars). All three under the 80-char cap, written in the same voice as spec 008 wizard copy and spec 003 error messages, no AI-generated tells (em-dashes restrained, no rule-of-three, no inflated adjectives).
- Q: What does the gear icon do when another modal/wizard is currently up (first-run download, update-restart prompt)? → A: **Disable the gear icon while any other modal/wizard is up.** No click-handler, no hover affordance, reduced opacity (matches existing disabled-button treatment in `design-system/MASTER.md`). Cmd+, also no-ops while a modal is up. Rationale: stacking a slide-in panel over a first-run takeover would let the user change tier mid-download of a different model — race condition the FR-009 / FR-010 invariants do not need to handle. The wizard and update prompt are short-lived; disabling for that window is cheap.
- Q: Where in the main window does the gear icon live? → A: **Top-right corner of the window, on the same horizontal axis as the existing update-status indicator from spec 007.** The two icons sit side-by-side (gear leftmost of the pair, update indicator rightmost — gear is more frequently used). They share the 32 px high chrome bar above the 2×3 zone grid. The grid does not shift; the chrome bar already exists from spec 007. Accessible label **Inställningar** in Swedish for the gear; the spec 007 update indicator's existing label is unchanged.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Pick a model tier and have the next zone run use it (Priority: P1)

A Swedish law student has been using JuraDrop with the default model. A long contract is producing summaries that feel shallow. The student opens the gear-icon panel, taps **Stor**, closes the panel, then drags the contract back onto **Sammanfatta**. The next run uses the larger model — without a restart, without a re-download (if already pulled), and without leaking any document content.

**Why this priority**: This is the core value of the panel. Everything else (appearance section, About section) is informational. Without the model selector working end-to-end, the panel is decoration.

**Independent Test**: Open the panel, switch from **Smart** to **Stor**, close the panel, run any zone with a fixture document, and confirm the Rust backend received the **Stor** model ID in the inference request (verified via test seam or log capture in dev build) and the sidecar result file is produced normally.

**Acceptance Scenarios**:

1. **Given** the panel is closed and the active tier is **Smart**, **When** the user clicks the gear icon and selects **Snabb**, **Then** the radio selection moves to **Snabb**, the choice is persisted to disk before the panel closes, and the next zone run is dispatched to the **Snabb** model ID without an app restart.
2. **Given** the user selects **Stor** and the corresponding large model is not yet pulled in Ollama, **When** the user immediately starts a zone run, **Then** the run waits for the model to become available (reusing the existing first-run download UI — no new modal) or fails with a named Swedish error if the download is unavailable, and the selection itself is **not** rolled back to a previously-pulled tier.
3. **Given** the panel is open and the user clicks the close-X / presses Esc / clicks outside the panel, **When** any of those happen, **Then** the panel slides out and the most-recent selection is the persisted value (no implicit "cancel without saving" — selection is committed when the radio changes).

---

### User Story 2 — Confirm the app respects the OS appearance (Priority: P2)

A student running macOS in dark mode opens the panel to verify JuraDrop is following the OS. The **Utseende** (Appearance) row says **Mörkt läge (följer systemet)**. They switch macOS to light mode without closing JuraDrop. The panel — and the row — both update to **Ljust läge (följer systemet)** within a frame or two, with no extra click.

**Why this priority**: This exists to *prevent* a feature request, not to add one. Many users expect a manual toggle; this section's job is to communicate "no, JuraDrop follows the OS — by design — and here's the proof it's working." High-value clarity, low implementation cost.

**Independent Test**: Open the panel in dark mode → confirm copy reads **Mörkt läge (följer systemet)**. Switch the OS to light mode → confirm the copy updates without re-opening the panel. There is no interactive control to test.

**Acceptance Scenarios**:

1. **Given** the OS is in dark mode and the panel is open, **When** the user looks at the **Utseende** section, **Then** they see read-only text **Mörkt läge (följer systemet)** and no toggle/switch/dropdown.
2. **Given** the panel is open in dark mode, **When** the OS is switched to light mode, **Then** the panel chrome AND the **Utseende** row both reflect the new appearance within 500 ms without user action.

---

### User Story 3 — Find the version, source, and license (Priority: P3)

A student wants to verify they are on the latest version and wants to see the source code before trusting the app with privileged material. They open the panel, scroll to **Om JuraDrop**, see the app name, the version (e.g. `0.10.0`), a **Visa utgåvor på GitHub** link, and a one-line license summary (`Öppen källkod, MIT-licens`). Clicking the GitHub link opens their default browser at the Releases page; the JuraDrop window stays open.

**Why this priority**: The About section is the audit trail for trust — version, source, license. Not the first thing users interact with, but the thing that justifies why they trust the app at all. Must be correct; need not be flashy.

**Independent Test**: Open the panel → confirm app name, version (matches `Cargo.toml` + `tauri.conf.json` + `package.json`), and license string appear. Click the GitHub link → default browser opens at the Releases URL. The JuraDrop window remains focused (does not minimise, does not show an in-app webview).

**Acceptance Scenarios**:

1. **Given** the panel is open at the **Om JuraDrop** section, **When** the user reads the version, **Then** it matches the version string baked into the build (verified against the three pinned files at release time per the spec 006 pipeline).
2. **Given** the panel is open, **When** the user clicks **Visa utgåvor på GitHub**, **Then** their OS default browser opens at `https://github.com/johanolofsson72/juradrop/releases` and JuraDrop does not embed a webview, does not navigate the app window, and does not request any new network permission.

---

### Edge Cases

- **Panel opened while a zone is processing**: opening the panel MUST NOT cancel, pause, or rate-limit any in-flight zone run. The user is free to switch tier mid-run; the in-flight run keeps the tier it was dispatched with — only *subsequent* runs use the new tier.
- **Tier switched while a zone is processing**: same as above. No re-dispatch, no warning modal. The next-fresh-drop is the cutover boundary, not the moment of selection.
- **Settings file missing on launch** (first run, deleted manually, corrupted JSON): the app starts with the default tier **Smart**, default-on follow-system appearance, and writes a fresh settings file on the first selection change. No Swedish error appears for a missing file — that is normal first-run state.
- **Settings file present but the persisted tier is unknown** (e.g. user downgraded the app, or someone hand-edited the file to an unrecognised string): app silently falls back to **Smart**, logs a single warning to the dev console (debug build only), and overwrites the file on the next selection.
- **Window resized to its minimum width while the panel is open**: the panel keeps its fixed width and the main content area compresses; the panel does not push the main content off-screen, does not become wider than the window, and does not become a separate window.
- **Multiple Cmd+, keystrokes in rapid succession** (or repeated gear-icon clicks): the panel does not stack, double-open, or animate twice. State is `open` or `closed`; repeated open intents are coalesced.
- **GitHub Releases URL cannot be opened** (no default browser registered — extraordinarily rare on macOS, but the API can fail): the click silently no-ops in a release build and surfaces a console warning in a dev build. We do NOT show a Swedish error modal — this failure is too edge-case to interrupt the user.
- **System appearance switched at the exact moment the panel is opening**: the slide-in animation completes in the new appearance; no flicker between dark and light chrome during the animation.

## Requirements *(mandatory)*

### Functional Requirements

#### Panel chrome and lifecycle
- **FR-001**: The main window MUST present a gear icon (single button) that opens the settings panel. The icon's accessible label is **Inställningar** (Swedish). The gear icon lives in the top-right chrome bar of the main window (Clarification Q5), to the left of the existing spec 007 update-status indicator, both sharing the existing 32 px chrome strip above the 2×3 zone grid.
- **FR-002**: The settings panel MUST slide in from the right edge with a duration matching the existing project motion tokens in `design-system/MASTER.md` (no bespoke easing values introduced for this spec).
- **FR-003**: The panel MUST close on any of: clicking the close-X inside the panel, pressing **Esc** while the panel is open, clicking the scrim/area outside the panel, or pressing **Cmd+,** (the macOS-standard "preferences" shortcut) — pressing **Cmd+,** while the panel is open closes it (it acts as a toggle).
- **FR-004**: The panel MUST have a fixed pixel width (per `design-system/MASTER.md`) and MUST NOT push the main grid out of view. When the window is narrower than `panel-width + minimum-grid-width`, the grid compresses (the existing responsive layout already supports this); the panel never becomes a separate window.
- **FR-005**: Opening, closing, or having the panel open MUST NOT cancel, pause, rate-limit, or otherwise interfere with any in-flight zone run.
- **FR-005a**: The gear icon and the Cmd+, shortcut MUST be disabled (no click handler fires, hover affordance suppressed, opacity reduced to the existing disabled-button token) whenever any other modal or wizard is currently up — including the first-run download wizard (spec 008) and the update-restart confirm dialog (spec 007). The disabled state lifts the moment the blocking modal/wizard dismisses (Clarification Q4).

#### Section 1 — Model selector
- **FR-006**: The model selector MUST present exactly three named tiers in this order: **Snabb**, **Smart**, **Stor**. The tier labels appear in Swedish; the underlying Ollama model IDs are: **Snabb → `llama3.2:1b`** (~1.3 GB), **Smart → `gemma3:4b`** (~3.3 GB — matches the existing `DEFAULT_MODEL` constant in `src-tauri/src/sidecar/commands.rs`), **Stor → `gemma3:12b`** (~8.1 GB). The mapping lives in one new central Rust module (e.g. `src-tauri/src/settings/tier_map.rs`) and is exposed to the frontend as a typed enum — model IDs are NEVER hard-coded in React (Clarification Q1).
- **FR-007**: Exactly one tier MUST be selected at any time. The default for a fresh install is **Smart**.
- **FR-008**: Selecting a tier MUST persist the choice to the standard macOS app support directory immediately (synchronously from the user's point of view — before any other UI affordance can react). A subsequent app launch MUST restore the same tier.
- **FR-009**: Selecting a tier MUST apply the change to all *subsequent* zone runs without an app restart, without re-initialising the sidecar process, and without re-downloading any model the user already has pulled.
- **FR-010**: In-flight zone runs MUST keep the model they were dispatched with. The cutover boundary is the next dispatch, not the moment of selection.
- **FR-011**: Each tier's row MUST include the following short Swedish helper sentence (≤ 80 chars), exactly as written (Clarification Q3): **Snabb → "Snabbast och minst. Bra för korta texter."**, **Smart → "Standardvalet. Bra balans mellan fart och kvalitet."**, **Stor → "Bästa kvaliteten. Tar längre tid och mer plats på disken."**. The strings live in the cross-language fixture (FR-026) so the drift test catches typos and divergence.
- **FR-012**: For tiers whose underlying Ollama model is NOT yet pulled, the panel MUST display the tier with a size badge (e.g. **~1.3 GB**, **~3.3 GB**, **~8.1 GB**) and a Swedish **Ladda ned** button — the tier MUST NOT be selectable as a radio while unpulled (Principle III alignment — see Clarification Q2). Clicking **Ladda ned** MUST hand control to the spec 008 first-run-wizard download flow with the corresponding model ID. On successful download completion, the panel MUST re-render with that tier now selectable, auto-select it (so the user gets zero extra clicks), and persist the selection per FR-008. On download failure or cancel, the previously-selected tier MUST remain active. The app MUST NOT pre-download any model in the background — every byte transferred is triggered by an explicit click on **Ladda ned**.
- **FR-012a**: At least one tier MUST always be selectable in the panel — Principle III guarantees that the spec 008 first-run-wizard pulls Smart (`gemma3:4b`) on first launch, so on every subsequent launch the Smart tier is pulled and selectable. The other two tiers (Snabb and Stor) may be in the unpulled-with-Ladda-ned state until the user explicitly pulls them.

#### Section 2 — Appearance (read-only)
- **FR-013**: The appearance section MUST display read-only text in Swedish indicating the *current* system appearance, in one of two forms: **Ljust läge (följer systemet)** when the OS is in light mode, **Mörkt läge (följer systemet)** when the OS is in dark mode.
- **FR-014**: The appearance section MUST NOT present any control that lets the user override the OS appearance (no toggle, no radio, no dropdown). This is intentional — Principle VI (Native macOS feel) requires following the OS.
- **FR-015**: When the OS appearance changes while the panel is open, the appearance row's text MUST update within 500 ms without user action.

#### Section 3 — About
- **FR-016**: The About section MUST display the app name (**JuraDrop**), the current build's version string (read at build time from the same source that pins `Cargo.toml` + `tauri.conf.json` + `package.json` per the spec 006 release prep script), the open-source license short-line in Swedish (**Öppen källkod, MIT-licens**), and a button/link labelled **Visa utgåvor på GitHub**.
- **FR-017**: Clicking the **Visa utgåvor på GitHub** link MUST open the URL `https://github.com/johanolofsson72/juradrop/releases` in the OS default browser via the platform's `shell.open` (existing Tauri capability) — NOT in an embedded webview, NOT in the JuraDrop window.
- **FR-018**: The About section MUST be entirely static — no buttons that mutate app state, no toggles, no inputs.

#### Persistence and data
- **FR-019**: Persisted settings MUST live in the app's standard macOS Application Support directory (resolved via Tauri's `app_data_dir`/`app_config_dir` API — no hard-coded `~/Library/...` paths). The file is JSON, UTF-8, one object containing only the model tier key. No telemetry IDs, no analytics keys, no user content.
- **FR-020**: A missing settings file MUST be treated as "default state" (Smart tier) without any error surfaced to the user. A malformed settings file MUST be silently replaced with default state on the next selection (one debug-only console warning is acceptable).
- **FR-021**: The settings file MUST contain ONLY the model tier key (and a small schema version sentinel for forward-compat). No telemetry IDs, no analytics keys, no user content, no document paths, no zone history.

#### Privacy and constitution
- **FR-022**: Opening, closing, or interacting with the panel MUST NOT trigger any outbound network call (the only outbound calls in the whole app remain: the auto-updater per spec 007 and the initial model download per spec 008, neither of which is initiated *by* this panel — the panel can *cause* a model download only as a side-effect of FR-012, via the existing spec 008 flow).
- **FR-023**: The settings persistence file MUST NOT contain any user document content, any document path, any zone history, any tier-change history, or any analytics identifier. (This is the file-level corollary of Principle I.)

#### Accessibility and i18n
- **FR-024**: All user-facing copy in the panel MUST be in Swedish (sv-SE). Code, comments, and the JSON keys in the persistence file remain English (consistent with Principle V).
- **FR-025**: The panel MUST be keyboard-navigable: Tab walks through the focusable controls in source order (gear → close-X → tier radios → GitHub link → and back), and Enter/Space activates the focused control. Escape closes the panel from any focused element inside it.
- **FR-026**: The Swedish copy strings MUST be sourced from the same cross-language fixture that the existing zone error strings live in (`fixtures/zone-error-strings.json` or its sibling) so the drift test (T035 lineage) covers them too.

### Key Entities

- **SettingsSnapshot**: The in-memory representation of the user's persisted choices. Today it holds exactly one value (`model_tier ∈ {Snabb, Smart, Stor}`) plus a schema-version sentinel. Lives in Zustand on the React side and in a mirrored Rust struct that the inference dispatch reads.
- **ModelTier**: An enum with three variants — `Snabb`, `Smart`, `Stor` — each mapping to an Ollama model ID via project config (not hard-coded in the React layer). Mapping table lives in one place in `src-tauri/` and is exposed to the frontend as a typed enum.
- **PanelVisibilityState**: An enum on the React side — `closed`, `opening`, `open`, `closing`. Coalesces repeated open intents (FR-026 of the panel chrome group); intentionally simple — no nested modal/sub-panel state.
- **SettingsFile**: The on-disk JSON artifact at `${appDataDir}/settings.json`. Schema is `{ "schema_version": 1, "model_tier": "Smart" }`. Owned by Rust; React reads through a Tauri command. No content beyond the listed fields is permitted.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can switch tier and have the new tier in effect for the next zone run within **2 seconds** of clicking the tier (panel close + persistence flush + next-dispatch lookup), with **zero app restart** required. Measured by the functional Playwright + vitest tests.
- **SC-002**: Settings persist across **100%** of clean app restarts in CI: a test that sets the tier, quits the app, restarts it, and asserts the same tier remains, passes on every run.
- **SC-003**: The panel opens and closes within the project's standard animation budget (per `design-system/MASTER.md`) — measured by an end-to-end test asserting `open` → `closed` transitions complete inside the configured duration.
- **SC-004**: When the OS appearance changes while the panel is open, the appearance row's copy updates within **500 ms** (FR-015) — measured by a vitest using fake timers and a synthetic `prefers-color-scheme` change event.
- **SC-005**: The settings JSON file contains **0** bytes of user content, **0** document paths, and **0** telemetry identifiers — measured by a Rust unit test that round-trips every reachable SettingsSnapshot and asserts the serialised form against a strict schema fixture.
- **SC-006**: Opening the panel during an active zone run does NOT change the run's outcome — measured by a parametric test: same input, same zone, with and without the panel opened mid-run → byte-identical sidecar output.
- **SC-007**: The drift test between Rust and TypeScript strings (T035 lineage) extends to cover **100%** of new panel strings; if a string is added to one side without the other, the test fails in CI.

## Assumptions

- **Reuses spec 008 download flow for the un-pulled-model case.** The first-run wizard already handles "model is not on disk, show progress". When the user picks **Stor** and the corresponding model is not pulled, the next zone run will reuse the same UX (gated by sidecar readiness check). This spec does NOT introduce a second download UI.
- **Model IDs decided per Clarification Q1.** Snabb=`llama3.2:1b`, Smart=`gemma3:4b` (matches existing `DEFAULT_MODEL`), Stor=`gemma3:12b`. The central mapping is added in `src-tauri/src/settings/` as part of this spec; no prior central registry to reuse.
- **Gear icon placement decided per Clarification Q5.** The spec 007 update indicator already occupies the top-right chrome bar; the gear icon takes the slot immediately to its left in the same 32 px chrome strip. No new layout region is invented.
- **`shell.open` is already enabled in Tauri capabilities** (or is enabled as a single-line capability change in this spec's implementation). The spec 007 auto-updater uses a similar permission shape, so the precedent exists.
- **No analytics, no telemetry, no first-run notice for this panel.** The panel is discoverable through the gear icon and Cmd+,; that is enough. No tooltip on first launch.
- **Cmd+, is the macOS-standard preferences shortcut** and we honour it. It is a toggle (open if closed, close if open) — not "always opens".
- **Animation timings come from `design-system/MASTER.md`** (likely the existing slide-in / fade tokens used by other modals). This spec deliberately does not invent new motion values — bespoke easing would mean a design-system change, which is out of scope.
- **Light pipeline track (per the spec register).** No new concurrency, no new state machine beyond the trivial panel-visibility one, no new outbound surface. `/tla` is skipped unless the panel-visibility state machine reaches non-trivial complexity during implementation (it should not).
