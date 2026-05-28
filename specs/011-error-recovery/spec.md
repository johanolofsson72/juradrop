# Feature Specification: Error Recovery (sidecar crash → one auto-restart, Swedish-only failure surface)

**Feature Branch**: `main` (solo direct-push; see `project-workflow`)

**Created**: 2026-05-28

**Status**: Draft

**Input**: User description — formalize the existing T045/F4 SidecarOneRetry pattern + add no-leakage and telemetry-free invariants. Most behavior is ALREADY IMPLEMENTED across specs 002/008; this spec ratifies it with explicit invariants and tests, then adds two NEW grep-enforced invariants (no-Rust-tells in user-facing copy + no-telemetry-libraries in the dep tree).

## Clarifications

### Session 2026-05-28

- Q: Should the English-leakage denylist (FR-013) include additional Rust-specific tells beyond the 8 currently listed? → A: **Yes — extend to 14 entries.** Add `Box<dyn`, `lock poisoned`, `mutex poisoned`, `RefCell`, `borrowed value`, `cannot move out of`. These cover the most common panic-message patterns Rust emits for memory-safety / sync errors. Total denylist after extension: `panicked at`, `RUST_BACKTRACE`, `unwrap()`, `Result::Err`, `thread '`, `Error:`, `Traceback`, `cannot borrow`, `Box<dyn`, `lock poisoned`, `mutex poisoned`, `RefCell`, `borrowed value`, `cannot move out of`. Plus the path-prefix check for `src-tauri/src/`.
- Q: Should the telemetry-library denylist (FR-015) include additional analytics platforms beyond the 11 currently listed? → A: **Yes — extend to 18 entries.** Add `firebase`, `googleanalytics`, `matomo`, `fathom`, `umami`, `splitbee`, `vercel-analytics`. These cover the most common open-source + commercial alternatives a future contributor might reach for. Total denylist: `sentry`, `plausible`, `posthog`, `mixpanel`, `segment`, `amplitude`, `bugsnag`, `rollbar`, `crashlytics`, `appcenter`, `datadog`, `firebase`, `googleanalytics`, `matomo`, `fathom`, `umami`, `splitbee`, `vercel-analytics`. Matching is case-insensitive substring on `Cargo.toml`, `Cargo.lock`, `package.json`, `package-lock.json`.
- Q: What happens if the sidecar crashes DURING the original `after_sidecar_ready` async task — i.e., before the initial bootstrap completes? → A: **The retry listener is idempotent.** The original `after_sidecar_ready` call may complete with stale state (the sidecar disappeared mid-tag-list call → `list_tags` returns Err → existing code logs the error and exits the function silently). The crash listener then re-spawns the sidecar AND re-calls `after_sidecar_ready` via GAP-4. The fresh bootstrap clears `error_override` (GAP-1), re-lists tags, and re-triggers pull if needed. The two task lifetimes overlap by design; the in-memory state is protected by `parking_lot::RwLock` so concurrent writes are serialized. No new code needed — existing pattern already handles this; this clarification PINS the contract.
- Q: The sidecar crash payload contains the integer exit code — does it ever surface in any user-facing string? → A: **No, never.** The payload (`i32` exit code) is consumed only by the listener for logging via `eprintln!` (debug-only, stderr only). The user-facing copy is ALWAYS the Swedish `FelOvantat` string — `AI-motorn svarar inte. Starta om JuraDrop.` — regardless of which exit code caused the crash. FR-013 already enforces this transitively (any code-leaking string would be caught by `Error:` / `thread '` / numeric ID patterns); this clarification PINS the contract explicitly so a future contributor doesn't add `format!("AI-motorn svarade inte (exit {code})", ...)` thinking it's helpful.
- Q: Does the retry budget EVER reset within a single app lifetime (e.g., user manually quits the sidecar process from Activity Monitor and the app sees a clean exit code 0)? → A: **No — strictly per-app-lifetime.** The `AtomicU8` `retry_count` field is set to 0 only by `OllamaSidecar::new()` in the constructor. There is no in-session reset path, no user-visible "reset retries" button, no time-based decay. If the user wants a fresh retry budget, they quit and relaunch JuraDrop (which is what the FelOvantat copy explicitly tells them to do). This rules out subtle bugs where a clean-exit-then-crash sequence accidentally hands the user a second retry; the budget is always 1 per process lifetime.

## What is NEW vs RATIFIED (read first)

To keep the spec honest:

| Behavior | Status | Where it lives today |
|---|---|---|
| Sidecar crash → emit `juradrop://sidecar-crashed` | **RATIFIED** | `src-tauri/src/sidecar/manager.rs:126` (drain task) |
| One-shot retry, monotonic AtomicU8 budget | **RATIFIED** | `src-tauri/src/lib.rs:79-100` (listener) + `manager.rs:33,141,218,231` |
| Swedish-only error surface (9 variants, FelOvantat for crash) | **RATIFIED** | `src-tauri/src/sidecar/status.rs:41-118` |
| `error_override` for terminal error display | **RATIFIED** | `src-tauri/src/sidecar/commands.rs:105,154,280,341` |
| Post-retry-success bootstrap (re-run after_sidecar_ready) | **RATIFIED** | `src-tauri/src/sidecar/commands.rs:60` (GAP-4) |
| In-flight DropJob → ModelError on sidecar disappearance | **RATIFIED** | spec 003/004 zone error mapping |
| **No Rust-language tells in user-facing copy** | **NEW** | grep-enforced CI test (this spec) |
| **No telemetry/crash-reporting libraries in dep tree** | **NEW** | grep-enforced CI test (this spec) |
| **Per-app-lifetime retry budget is 1 (not per-crash)** | **NEW invariant** | code already enforces it; this spec PINS the contract |
| **Pull-cancel-on-crash invariant** (partial download discarded) | **NEW invariant** | code path exists; this spec pins the contract + test |
| **Recovery-instruction copy** (`Starta om JuraDrop`) | **NEW copy hardening** | extend FelOvantat helper line |

Roughly: ~120 LOC of new tests, ~15 LOC of new Rust, zero new state machines, zero new dependencies.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Transient crash auto-heals silently (Priority: P1)

A law student is in the middle of dropping documents on the Sammanfatta zone. The Ollama sidecar process crashes (out-of-memory in the kernel, killed by Activity Monitor by a wandering finger, transient bug). Within 10 seconds, the app auto-restarts the sidecar, the next dispatch works normally, and the user sees no error at all — just a brief "Startar AI..." status flicker on the welcome card while the sidecar boots back up.

**Why this priority**: This is the dominant case. Most crashes are transient (OS pressure, single-bug edge case). Silent auto-recovery means the user never even notices. Without it, every crash is a "Starta om JuraDrop" prompt — high friction, low value.

**Independent Test**: Inject a SIGKILL into the bundled Ollama sidecar process via a test seam. Assert that within 10 seconds the sidecar status transitions Crashed → Starting → Ready, the welcome card never shows FelOvantat copy, and a fresh dispatch on any zone produces the expected sidecar output.

**Acceptance Scenarios**:

1. **Given** the app is idle with the sidecar Ready, **When** the sidecar is killed externally and the drain task fires `juradrop://sidecar-crashed`, **Then** within 10 seconds the listener re-spawns the sidecar, after_sidecar_ready re-runs, the model_status returns to Ready, and no Swedish error appears in the UI.
2. **Given** the user has just dropped a `.docx` on the Sammanfatta zone, **When** the sidecar crashes mid-inference, **Then** the in-flight DropJob terminates with ZoneFailure::ModelError (Swedish `AI-motorn svarade inte — försök igen`), the zone returns to idle within the standard error-clear budget, AND the listener silently re-spawns the sidecar so the user can retry without quitting.

---

### User Story 2 — Second crash holds a polite Swedish error until quit (Priority: P2)

A second crash happens in the same app session (rare — usually means the OS is overloaded or the bundled binary has a hard bug on this particular Mac). The retry budget is exhausted, so the app does NOT attempt a second retry. Instead, the welcome card switches to **AI-motorn svarar inte. Starta om JuraDrop.** and stays there until the user quits and relaunches.

**Why this priority**: Bounded retries prevent infinite loops on permanently-broken environments. A clean, named error is honest about what happened without leaking a stack trace.

**Independent Test**: Kill the sidecar twice in the same session. Assert that the second crash leaves the app in the FelOvantat user-visible state, the listener does NOT call `state.sidecar.spawn` a second time (verified via a mock counter), and the visible Swedish copy matches the pinned string exactly.

**Acceptance Scenarios**:

1. **Given** the app has already auto-retried once after a first crash, **When** a second crash fires `juradrop://sidecar-crashed`, **Then** the listener observes `retry_count_value() != 0`, logs `retry budget exhausted; holding Crashed` (debug-only, not surfaced), and the welcome card displays **AI-motorn svarar inte. Starta om JuraDrop.** until app quit.
2. **Given** the app has reached the second-crash terminal state, **When** the user quits and re-opens JuraDrop, **Then** the retry budget resets to 0 (per-app-lifetime semantics), the sidecar bootstraps cleanly, and the previous error is gone.

---

### User Story 3 — Crash during model pull → partial download discarded, wizard resumes (Priority: P3)

A first-time user is downloading the `gemma3:4b` model via the spec 008 wizard. Halfway through (~1.5 GB of 3.3 GB), the sidecar crashes. The partial blob is discarded by Ollama on retry-spawn, the wizard's progress UI resets to 0, the SidecarOneRetry listener re-spawns the sidecar, and after_sidecar_ready triggers a fresh pull. The user sees the wizard reset to "Hämtar AI-modell…" with a fresh progress bar — no error, no manual click.

**Why this priority**: First-run reliability is critical. A crash mid-download must not strand the user with a 50%-downloaded model and no way to resume.

**Independent Test**: Mock the pull stream to crash the sidecar at the 50% mark. Assert that the wizard's progress resets to 0, the next `juradrop://progress` event fires below 5%, and the eventual `klar` state matches the no-crash success path byte-for-byte.

**Acceptance Scenarios**:

1. **Given** the wizard is downloading the model at 50% progress, **When** the sidecar crashes, **Then** the partial pull is cancelled (no torn-blob persistence), the listener auto-retries the sidecar, after_sidecar_ready re-runs (which detects model NOT present + consent still granted), and the wizard's progress restarts from 0.

---

### Edge Cases

- **Settings file write race during crash**: A `set_model_tier` call lands at the exact moment the sidecar crashes. Spec 010's atomic temp-file + rename pattern guarantees the on-disk settings.json is either fully old or fully new; the crash cannot leave a torn-write. Ratify with a stress test (T-NEW in the test plan below).
- **Update install during crash**: The spec 007 deferred-restart confirm dialog is up. The sidecar crashes. Per FR-005a (spec 010) the gear icon is disabled, but the update modal continues to own the screen. The retry happens regardless (it doesn't touch the update state). After retry succeeds, the update modal is still up; user can confirm or dismiss normally. No interaction between the two state machines.
- **Crash during first-launch consent modal**: User has not yet clicked Fortsätt. The sidecar crashes — but it hadn't even started a pull yet, so there's nothing to discard. Retry happens; after_sidecar_ready sees `consent == NotAsked` and waits silently.
- **Crash while gear icon is being clicked**: The panel is opening (visibility=`opening`). The sidecar crashes. The panel completes its open animation; the tier rows render with whatever pull state was last cached. No crash-related corruption of panel state.
- **Crash exactly at the moment of app shutdown**: The drain task may fire `juradrop://sidecar-crashed` while the app is already in WindowEvent::CloseRequested. The listener's spawned task may not get a chance to call sidecar.spawn before the app exits. This is acceptable — no retry on shutdown, no error surfaced, the app just closes.

## Requirements *(mandatory)*

### Functional Requirements

#### Crash detection + auto-restart
- **FR-001**: The sidecar drain task MUST emit `juradrop://sidecar-crashed` exactly once per unexpected child-process exit (status code ≠ 0 OR signal-termination). Already implemented in `manager.rs:126`. This spec ratifies the channel name and one-per-crash guarantee.
- **FR-002**: A SessionStart listener registered in `lib.rs` setup MUST observe every `juradrop://sidecar-crashed` event and atomically check the per-app retry counter via `retry_count_value()`.
- **FR-003**: If `retry_count_value() == 0`, the listener MUST call `state.sidecar.increment_retry()` (which returns the post-increment value, so a concurrent second call sees `1` not `0`) AND spawn exactly one re-spawn task. The retry budget is **per-app-lifetime** — not per-crash, not per-minute.
- **FR-004**: If `retry_count_value() != 0`, the listener MUST log `retry budget exhausted; holding Crashed` (debug-only) and NOT call spawn. The app stays in `FelOvantat` until quit.
- **FR-005**: The re-spawn task MUST complete within 10 seconds in the happy case (matches `wait_ready(Duration::from_secs(10))`).
- **FR-006**: On successful re-spawn, the listener MUST call `after_sidecar_ready` to re-run the post-ready bootstrap (clear stale `error_override`, list tags, re-trigger pull if missing-and-consent-granted). Already implemented (GAP-4); ratify.

#### Error surface (Swedish-only)
- **FR-007**: On retry failure OR second crash, `error_override` MUST be set to `UserVisibleStatus::FelOvantat`. The welcome card MUST display exactly **AI-motorn svarar inte. Starta om JuraDrop.** with no English, no stack trace, no error code.
- **FR-008**: In-flight DropJobs interrupted by a crash MUST terminate with `ZoneFailure::ModelError` (Swedish `AI-motorn svarade inte — försök igen`). The zone MUST return to idle via the existing error-clear schedule so the user can retry from the same zone without quitting.
- **FR-009**: NEW — the FelOvantat copy MUST include a recovery instruction. Current value (**AI-motorn svarar inte. Starta om JuraDrop.**) ALREADY contains it. This FR pins the copy as final (no rewording in beta).
- **FR-010**: All other existing Swedish error copy (FelKundeInteStarta, FelPortenUpptagen, FelDiskFull, FelModellnedladdningAvbroten, ModellSaknasAvbruten) MUST stay ≤ 80 chars and MUST be sourced from the existing fixture lineage. Drift test extends to cover these.

#### Pull-cancel-on-crash
- **FR-011**: When the sidecar crashes mid-pull, the in-flight pull stream MUST terminate (reqwest bytes_stream drops on connection loss — already happens). The wizard's progress slice MUST be reset to 0 by the next `juradrop://status` emit after re-spawn completes. The partial blob MUST NOT be persisted by JuraDrop (Ollama itself owns the model directory; we delegate cleanup to it).
- **FR-012**: On re-spawn success, `after_sidecar_ready` MUST detect the model is still missing AND consent was already granted, and re-trigger the pull task with a fresh `pull_cancel` token. The user MUST NOT need to re-click Fortsätt.

#### No-leakage invariant (NEW)
- **FR-013**: NO user-facing string in any Swedish copy fixture, in any React component's literal text, OR in any Tauri command's String error return MAY contain any of the 14 denylist substrings (Clarification Q1): `panicked at`, `RUST_BACKTRACE`, `unwrap()`, `Result::Err`, `thread '`, `Error:` (with the colon, English-style), `Traceback`, `cannot borrow`, `Box<dyn`, `lock poisoned`, `mutex poisoned`, `RefCell`, `borrowed value`, `cannot move out of`. Enforced by a CI grep test that walks `src/**/*.{ts,tsx,json}` and `src-tauri/tests/fixtures/*.json` and fails the build on any match. **Implementation note**: the original spec also included a path-prefix `src-tauri/src/` denylist intended to catch leaked Rust source paths. Empirically this is over-eager — legitimate JSON `_comment` fields and TS source-of-truth comments reference Rust paths to document the cross-language correspondence. The 14 substring patterns cover the actual leakage modes (any string emitting a Rust panic / error already contains `panicked at`, `Error:`, `thread '`, etc., so source paths inside such strings are caught transitively). The path-prefix portion was dropped in implementation. Test exclusions: `*.test.{ts,tsx}` files (may contain denylist patterns AS test data) and `package.json` / `package-lock.json` (contain English library names by necessity).
- **FR-014**: All ZoneFailure variants' Display impl AND any Rust `format!` call that produces a string returned across the Tauri boundary as a user-facing error MUST go through a Swedish-copy helper. Enforced indirectly: FR-013's grep covers any English-language tells that slip through.

#### Telemetry-free invariant (NEW)
- **FR-015**: The dependency tree MUST contain ZERO crash-reporting / analytics / telemetry libraries. The 18 denylisted substrings (Clarification Q2) — `sentry`, `plausible`, `posthog`, `mixpanel`, `segment`, `amplitude`, `bugsnag`, `rollbar`, `crashlytics`, `appcenter`, `datadog`, `firebase`, `googleanalytics`, `matomo`, `fathom`, `umami`, `splitbee`, `vercel-analytics` — MUST appear nowhere in: `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `package.json`, `package-lock.json`. Matching is case-insensitive. Enforced by a CI grep test.
- **FR-016**: No `panic_hook` or `set_panic_hook` registration MAY emit anywhere except the local stderr stream. Enforced by a CI grep test asserting no `panic::set_hook` calls in `src-tauri/src/` reference any HTTP client, any Tauri command, or any file write to a non-local path.
- **FR-017**: No outbound HTTP call from any crash-handling code path. Inherited from Principle I; ratified here as a code-locality assertion: the sidecar-crash listener in `lib.rs` MUST NOT import `reqwest`, `tauri-plugin-http`, `tauri-plugin-shell::open` for any non-pinned URL, or any other outbound-capable type.

### Key Entities

- **SidecarCrashEvent**: The Tauri event fired on the `juradrop://sidecar-crashed` channel. Payload is the integer exit code (existing). Carries no PII, no path information, no user-content fragment.
- **RetryCounter**: An `AtomicU8` on `OllamaSidecar`. Lifecycle: 0 at app boot → 1 after first crash + retry attempt → never decremented within app lifetime. Resets to 0 on every fresh app launch (constructor sets it back).
- **PostRetryBootstrap**: The `after_sidecar_ready` function executed after a successful re-spawn. Already exists. This spec pins the contract that it MUST be called from the retry path (GAP-4 invariant — already present, this spec ratifies).
- **EnglishLeakageDenylist**: The set of substrings whose presence in any user-facing string fails CI. Pinned in this spec's FR-013.
- **TelemetryDependencyDenylist**: The set of crash-reporting / analytics library names whose presence in dep manifests fails CI. Pinned in this spec's FR-015.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of single-crash injections in CI auto-heal silently — the welcome card never displays FelOvantat copy after exactly one synthetic SIGKILL. Measured by a vitest + Rust unit test pair.
- **SC-002**: 100% of double-crash injections in CI surface FelOvantat copy after the second crash AND stop calling `sidecar.spawn`. Measured by a Rust integration test counting spawn invocations.
- **SC-003**: The retry counter is monotonic across all reachable code paths — no test scenario can make `retry_count_value()` decrement within a single app lifetime. Measured by a property-based test asserting the post-increment value is never less than any prior observed value.
- **SC-004**: Crash-during-pull recovery completes within 90 seconds total (10 s re-spawn + ≤ 80 s re-download depending on connection). The 90 s budget is a CI target on a wired test runner; manual real-hardware verification covers user-perceptible wall-clock.
- **SC-005**: 0 English-language tells in any user-facing string. Measured by the new FR-013 grep test which runs on every CI build.
- **SC-006**: 0 telemetry / crash-reporting libraries in any dep manifest. Measured by the new FR-015 grep test.
- **SC-007**: 0 outbound HTTP requests originate from the crash-handling code path. Measured by Rust unit test that stubs `reqwest::Client::new` and asserts the stub is never called during a synthetic crash + retry sequence (or by static-analysis grep — whichever is more reliable).
- **SC-008**: Per-zone error-clear schedule budget (existing) is preserved — after a crash-induced ModelError, the zone returns to idle within the same number of seconds the spec 003 user perceives for any other error. No new perceived latency.

## Assumptions

- **Ollama's own model-directory cleanup is correct.** When a pull stream drops mid-download, Ollama discards the partial blob from its own tag list on the next request. We delegate this — JuraDrop does NOT manually inspect or delete Ollama's blob directory. If this assumption breaks (e.g., a future Ollama version persists corrupt partial blobs), spec 011's FR-011 will need a code-side cleanup pass.
- **The drain task fires exactly once per crash.** `tokio::process::Child::wait()` in `manager.rs` is consumed by a single `await`; no double-fire is possible without code change.
- **One retry is enough for transient crashes.** Field evidence from the alpha period (n=12 crashes across 4 testers) suggests >90% of crashes were transient — auto-restart fixed them silently. A 2- or 3-retry budget would catch a few more but risks masking persistent bugs. The 1-retry budget is the project's tradeoff.
- **`Starta om JuraDrop` instruction is sufficient guidance.** Users on macOS know how to quit (Cmd+Q) and relaunch. No further explanation needed in the error string. Constitution Principle VIII.
- **Full pipeline track per the spec register** — this is a behavior-binding spec with formal invariants and a state-machine-shaped contract (RetryCounter monotonicity). `/tla` runs.
- **No new dependencies.** All new code lives inside existing modules (`src-tauri/src/sidecar/`, `src-tauri/tests/`). Net dep delta: 0.
- **Beta acceptance criteria.** This spec is the LAST behavior-binding spec before public beta (spec 012 is polish-only). If FR-005..FR-008 fail in real-hardware testing, beta is blocked.
