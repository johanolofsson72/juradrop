# Feature Specification: Opt-in local crash diagnostics

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Full pipeline (new entity + behavior + Principle-I-sensitive → `.allium` + `/tla`).

**Input**: When something fails on a user's machine there is currently no way to diagnose it — by design (Principle I forbids telemetry). Spec 011 deferred `CrashReproductionLogging` noting it would need "explicit consent + a scrub pipeline." Add exactly that: an **opt-in** (default OFF), **local-only** (never auto-sent), **content-scrubbed** diagnostics log the user can turn on in Settings and inspect themselves. The log records only content-free event categories (sidecar crash, retry, zone-failure category, app/OS version) — never document text, prompts, model output, or file paths. Content-safety is structural: the logging API takes a category enum, so content *cannot* be logged.

## Why this spec exists

A privacy tool still needs a way for a willing user to help diagnose a bug without betraying the privacy promise. The deferred-from-011 feature, done right: consent-gated, local-only, content-free by construction. It strengthens support without weakening Principle I.

## Principle I review (REQUIRED — this is privacy-sensitive)

- **Default OFF.** No diagnostics are written unless the user explicitly turns the toggle on.
- **Local-only.** The log is a file in the app data dir. It is NEVER sent anywhere — no network, no auto-upload. The only outbound traffic in the whole app remains the updater + model pull (constitution Principle I). This spec adds ZERO outbound calls.
- **Content-free by construction.** The log API is `log_event(DiagnosticEvent)` where `DiagnosticEvent` is an enum of fixed categories — there is no free-text/String parameter that could carry document content, prompts, or output. A structural test asserts the log never contains content.
- **No new settings-snapshot field.** The consent flag is stored in the diagnostics module's OWN file, leaving `SettingsSnapshot`'s test-enforced 2-field privacy invariant (`settings_invariants.rs`) completely intact.
- **User-inspectable.** Settings shows the log's path so the user can read or delete it. No "auto-send" button, ever.

## What's IN scope

| Item | Type |
|---|---|
| `diagnostics` Rust module: `DiagnosticEvent` enum, global gate, `log_event`, size cap | Code |
| Consent flag persisted in the module's own file (NOT SettingsSnapshot) | Code |
| `set_diagnostics_enabled` / `get_diagnostics_status` Tauri commands | Code |
| Settings-panel section: toggle (default OFF) + Swedish explanation + the log path | Code (UI) |
| Wire `log_event` into the zone-failure + sidecar-crash sites | Code |
| Tests: enabled→scrubbed write; disabled→nothing; content-free structural; consent persists; drift | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Any auto-send / email / upload | Principle I — local-only, user copies it manually if they want |
| A field in SettingsSnapshot | Keeps the 2-field privacy invariant intact; consent lives in the diagnostics file |
| Reveal-in-Finder button | User decision: show the path only (no new capability) |
| Logging document content / prompts / output | Forbidden — the enum API makes it impossible |

## Clarifications

### Session 2026-05-29 (auto-picked + user interview)

- Q: Scope? → A: **Full feature** (Rust module + consent + settings toggle + wiring). [user]
- Q: How does the user reach the log? → A: **Show the path in Settings** (no new capability). [user]
- Q: Where is the consent flag stored? → A: **In the diagnostics module's own file**, NOT `SettingsSnapshot` — preserves the test-enforced 2-field privacy invariant.
- Q: What is logged? → A: **Content-free categories only**: sidecar crash, sidecar restart (with attempt number), zone-failure category (the ZoneFailure serde tag, e.g. `model_error`), plus app version + OS. Each event renders to a fixed line; no free text.
- Q: Retention? → A: **Size-capped** (cap the file at ~64 KB; oldest lines dropped). A diagnostics log shouldn't grow unbounded.
- Q: Default state? → A: **OFF.** Diagnostics only run after explicit opt-in.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A user opts in and gets a content-free local log (Priority: P1)

A user hitting repeated failures turns on "Felsökningslogg" in Settings. From then on, failures append a content-free line to a local file whose path Settings shows. They can open it, read the categories/timestamps, and delete it. Nothing is sent anywhere.

**Independent Test**: with diagnostics enabled, `log_event(ZoneFailureLogged(model_error))` appends a line containing the category + timestamp + version, and NO document content; with diagnostics disabled (default), the same call writes nothing.

**Acceptance Scenarios**:
1. **Given** diagnostics OFF (default), **When** events occur, **Then** no log file is written.
2. **Given** the user enables diagnostics, **When** a zone fails, **Then** a line with the failure CATEGORY (not content) + timestamp + app/OS is appended.
3. **Given** any logged event, **When** the log is inspected, **Then** it contains no document text, prompt, model output, or user file path.
4. **Given** consent was enabled, **When** the app restarts, **Then** the consent persists (loaded from the diagnostics file).
5. **Given** the log exceeds the size cap, **When** a new line is appended, **Then** the file is trimmed to stay under the cap.

### Edge Cases

- Toggling on then off → subsequent events write nothing.
- The diagnostics dir not writable → logging silently no-ops (never crashes the app).
- Settings copy is Swedish, humanizer-reviewed, and states plainly: local-only, content-free, off by default.

## Requirements

### Functional

- **FR-001**: `src-tauri/src/diagnostics/` MUST expose `DiagnosticEvent` (enum of content-free categories: `SidecarCrash`, `SidecarRestart { attempt: u8 }`, `ZoneFailureLogged { category: &'static str }`, where `category` is a ZoneFailure serde tag) and `log_event(DiagnosticEvent)`. NO variant carries free text/content.
- **FR-002**: `log_event` MUST be a no-op when diagnostics are disabled (the default). When enabled, it appends one line: `<rfc3339-timestamp> <category-token> v<app_version> <os>`. No content, no path.
- **FR-003**: The consent flag MUST persist in the diagnostics module's OWN file (e.g. `<app_data>/diagnostics/consent.json`), NOT in `SettingsSnapshot`. `SettingsSnapshot` MUST remain exactly two fields (`settings_invariants.rs` stays green, untouched).
- **FR-004**: `set_diagnostics_enabled(bool)` + `get_diagnostics_status()` (returns `{enabled, log_path}`) Tauri commands. Enabling persists consent; disabling persists + stops further writes.
- **FR-005**: The log file MUST be size-capped (~64 KB); appends beyond the cap trim the oldest lines.
- **FR-006**: A failed diagnostics write (unwritable dir, etc.) MUST silently no-op — diagnostics MUST NEVER crash or degrade the app.
- **FR-007**: `log_event` MUST be wired into at least the zone-failure finalize path and a sidecar-crash/restart path.
- **FR-008**: Settings panel MUST gain a "Felsökningslogg" section: a toggle (default OFF), Swedish explanation (local-only, content-free, off by default), and the log path as selectable text. Copy via humanizer.
- **FR-009**: NO outbound network surface is added (Principle I). The telemetry denylist + no-outbound invariants stay green.

### Key Entities

- **DiagnosticEvent**: enum of content-free event categories. The structural guarantee that content cannot be logged.
- **DiagnosticsConsent**: `{ enabled: bool }` persisted in the diagnostics file; default `false`.

## Success Criteria

- **SC-001**: Default OFF → no log written. Verified by test.
- **SC-002**: Enabled → events append content-free lines (category + timestamp + version). Verified by test.
- **SC-003**: The log NEVER contains document content/prompts/output/paths — structurally (enum API) + a test asserting it. 
- **SC-004**: Consent persists across restart (own file). `SettingsSnapshot` still exactly 2 fields — `settings_invariants.rs` green, unchanged.
- **SC-005**: Size cap holds. Failed writes no-op (no crash).
- **SC-006**: Net new deps: 0. Telemetry denylist + no-outbound invariants green (no new outbound).
