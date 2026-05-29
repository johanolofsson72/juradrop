# Tasks: On-demand tier download

**Feature**: spec 027 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

Tests are REQUIRED here per `CLAUDE.md` (100% functional coverage + destructive) and the full pipeline track. Story labels: US1 = download happy path, US2 = honest failure + retry, US3 = cancel.

## Phase 1: Setup

- [ ] T001 Read existing pull machinery to anchor the implementation: `src-tauri/src/sidecar/client.rs` (`pull`, `PullEvent`, `PullLine`), `src-tauri/src/sidecar/commands.rs` (`spawn_pull_task`, `has_sufficient_disk_for_pull`, `AppState`), `src-tauri/src/settings/commands.rs` (stub `trigger_tier_download`, `tier_is_pulled`, `ModelTier::model_id`), `src/components/FirstRunProgress.tsx` (progress visual language). No code change — context only.

## Phase 2: Foundational (blocking prerequisites)

- [ ] T002 In `src-tauri/src/sidecar/client.rs`, extend `PullEvent::Progress { percent }` → `Progress { percent, completed, total }` and pass the already-parsed `total`/`completed` from `PullLine::into_event` through (currently discarded at line ~247). Keep the `total == 0` guard.
- [ ] T003 Update the bundled callsite in `src-tauri/src/sidecar/commands.rs` (`spawn_pull_task`, ~line 194) to match `PullEvent::Progress { percent, .. }` — no behavioural change to the spec-008 flow.
- [ ] T004 Update the existing `client.rs` pull unit tests (`pull_line_*`) to assert the byte fields are now carried on `Progress` (extend the existing assertions; do not remove them).
- [ ] T005 Create `src-tauri/src/settings/tier_download.rs` with the core types from data-model.md: `DownloadPhase { Downloading, Error }`, `DownloadFailure { Network, DiskFull, NotReady, NotFound }` (snake_case serde), `TierDownloadState { tier, phase, completed, total, failure }`, and a serialisable payload struct (adds `percent` derived from completed/total). Register the module in `src-tauri/src/settings/mod.rs`. (analyze I1 — pin the lifecycle name mapping so it cannot drift): the persistent Rust slot uses `DownloadPhase { Downloading, Error }`; **slot-absent** means `not_pulled` (never started, or cancelled) OR `pulled` (disambiguated by `get_tier_pull_state`/`/api/tags`). The EVENT payload's `phase` is the broader signal set `downloading | error | done | cancelled` (`done`/`cancelled` are transient emit-only signals fired as the slot clears — they are NOT stored `DownloadPhase` variants). The allium `status { not_pulled | downloading | pulled | error }` is the conceptual union of both.
- [ ] T006 Add the at-most-one download slot + cancel token to settings state: `Arc<RwLock<Option<TierDownloadState>>>` and `Arc<RwLock<CancellationToken>>` (held in `SettingsState` or a small `TierDownloadHandle` owned by `AppState`). Wire construction in `src-tauri/src/lib.rs`.
- [ ] T007 Add the four new Swedish strings + the three control strings to `src/lib/settings-panel-strings.ts`, the fixture `src-tauri/tests/fixtures/settings-panel-strings.json`, and the Rust drift test's expected key set (`settings_strings_drift.rs`): `tier_downloading_label`, `tier_download_cancel`, `tier_download_retry`, `tier_download_err_network`, `tier_download_err_disk_full`, `tier_download_err_not_ready`, `tier_download_err_not_found`. Run the **humanizer** skill on all seven before finalising (FR-014).

## Phase 3: User Story 1 — download a tier on demand (P1) 🎯 MVP

**Goal**: Clicking Ladda ned pulls the tier's model with live progress; on completion the row becomes selectable.
**Independent test**: with the mock-Ollama seam streaming a pull, the row goes not_pulled → downloading (progress) → radio_selectable.

- [ ] T008 [US1] In `tier_download.rs`, implement `start_tier_download(app, handle, sidecar, tier)`: precondition checks (sidecar ready, no bundled pull active, no active slot, tier not already pulled), set the slot to `Downloading{completed:0,total:0}`, spawn a process-lifetime task calling `client.pull(tier.model_id(), cb)`, emit the first `juradrop://settings/tier-download` event. Refuse paths return `Err("not_ready")` / `Err("busy")` without starting a pull (FR-001, FR-010, FR-009).
- [ ] T009 [US1] Implement the pull task's `on_event` callback: `Progress` → update slot completed/total + throttled emit (≥1% or ≥500 ms, mirrors `spawn_pull_task`); `Completed` → clear slot, emit `phase: done`; `Failed` → see US2 (T015). Derive `percent` for the payload (FR-003, SC-002).
- [ ] T010 [US1] Add the Tauri commands in `src-tauri/src/settings/commands.rs`: `start_tier_download(tier)`, `get_tier_download_state() -> Option<payload>`; register both in `src-tauri/src/lib.rs`. DELETE the stub `trigger_tier_download` + `TierDownloadRequest` + the `juradrop://settings/tier-download-requested` emit (FR-012).
- [ ] T011 [P] [US1] In `src/lib/tauri-bridge.ts`, replace `triggerTierDownload`/`subscribeTierDownloadRequested`/`TierDownloadRequest` with `startTierDownload(tier)`, `getTierDownloadState()`, `subscribeTierDownload(cb)`, and the `TierDownloadEvent` type per contracts/tier-download.md (FR-012).
- [ ] T012 [US1] Create `src/lib/tier-download-store.ts` (Zustand): holds the current `TierDownloadEvent | null`, subscribes to `juradrop://settings/tier-download`, hydrates via `getTierDownloadState()` on init, exposes `start(tier)` / (cancel + retry added in US2/US3). On `phase: done` it triggers a `getTierPullState()` refresh so the row flips (FR-005, FR-011).
- [ ] T013 [US1] Update `src/components/SettingsPanelModelTier.tsx`: the `download_button` row reads the store; when this tier is downloading, render the progress sub-state ("{percent} % · {done} / {total} GB" via a sv-SE byte formatter, or `tier_downloading_label` when total=0) instead of the Ladda-ned button; disable the OTHER tier's Ladda-ned while any download is active (FR-009). `onDownload` calls `startTierDownload`. Invoke the **frontend-design** skill before editing; reuse FirstRunProgress visual language + the documented `#007aff`/`#0a84ff` accent.

## Phase 4: User Story 2 — honest failure + retry (P2)

**Goal**: failures show a distinct Swedish message + Försök igen; not-ready refuses cleanly.
**Independent test**: inject a mid-stream error / connection failure / not-ready → correct category + retry re-enters downloading.

- [ ] T014 [US2] In `tier_download.rs`, implement `categorise_failure(&ClientError or Failed(msg)) -> DownloadFailure` per research R-003: not-found (msg contains "not found"/"manifest"), disk-full (space/write error or pre-check fail), network (everything else). Add a disk pre-check before spawn (reuse `has_sufficient_disk_for_pull`) → `NotReady`/`DiskFull` refuse path. Unit-test every branch (SC-003).
- [ ] T015 [US2] Wire the pull task's `Failed`/`Err` arm: set slot `phase: Error, failure: <category>`, emit `phase: error` with the failure. No auto-retry (FR-006, FR-007).
- [ ] T016 [US2] Add `retry` to the store + a `start_tier_download` re-entry from the error state (same command; precondition allows `error` slot). Map each `DownloadFailure` to its Swedish string in `SettingsPanelModelTier.tsx`; render the error sub-state with **Försök igen**. Invoke **frontend-design** before the row edit.
- [ ] T017 [US2] Handle the `not_ready` refuse on the frontend: `startTierDownload` returning `Err("not_ready")` shows `tier_download_err_not_ready` on the row without entering downloading (FR-010).

## Phase 5: User Story 3 — cancel (P3)

**Goal**: Avbryt stops the download and returns the row to Ladda ned; tier stays uninstalled.
**Independent test**: cancel mid-stream → row not_pulled, tier reported not pulled.

- [ ] T018 [US3] In `tier_download.rs`, implement `cancel_tier_download(handle, tier)`: trip the cancel token, the pull task exits via `tokio::select!` (mirror `spawn_pull_task` lines 225+), command clears the slot to `None`, emit `phase: cancelled` (FR-008, SC-004).
- [ ] T019 [US3] Register the `cancel_tier_download` command in `src-tauri/src/lib.rs`; add `cancelTierDownload(tier)` to `tauri-bridge.ts` + `cancel` to the store.
- [ ] T020 [US3] Add the **Avbryt** control to the downloading sub-state in `SettingsPanelModelTier.tsx` → calls `cancelTierDownload`. Invoke **frontend-design** before the edit.

## Phase 6: Tests (functional coverage FIRST, then destructive) — per `.claude/rules/tests.md`

### Functional inventory (every implemented function gets ≥1 test)

- [ ] T021 [P] Rust: `src-tauri/tests/tier_download_state.rs` — state machine transitions (not_pulled→downloading→pulled; →error; →not_pulled on cancel; error→downloading on retry), `ErrorHasReason`, terminal=pulled.
- [ ] T022 [P] Rust: `tier_download_concurrency.rs` — at-most-one slot: second `start` while downloading is refused `busy`; `AtMostOneDownloading` holds (FR-009, SC-005).
- [ ] T023 [P] Rust: `tier_download_failures.rs` — `categorise_failure` for all four categories + disk pre-check refuse (SC-003).
- [ ] T024 [P] Rust: `tier_download_model_map.rs` — Snabb→`llama3.2:1b`, Stor→`gemma3:12b`; a download's model_id is always in the localhost set (`PullsAreLocalModelOnly`, `LocalhostOnly`).
- [ ] T025 [P] Rust: `tier_download_no_content_leak.rs` — grep/structural: the payload + event carry no document text; the module never imports the zone/extract surface (FR-013, Principle I).
- [ ] T026 [P] Rust: mock-Ollama streaming pull via the wiremock seam — happy stream → Completed; mid-stream 500 → Failed→network; verifies byte fields propagate.
- [ ] T026a [P] Rust (FR-015 coverage, analyze C1): assert a tier download does NOT block inference — structurally (the `tier_download` module acquires no lock also held by the `generate` path; grep/ownership test) and, via the mock seam, a download task and a `generate` call run concurrently without one awaiting the other. Closes the FR-015 automated-coverage gap.
- [ ] T027 [P] Front: `src/__tests__/tier-download-store.test.ts` — subscribe/hydrate, start/cancel/retry actions, `phase: done` triggers pull-state refresh, error sets failure. (analyze C2 / SC-002) Add a throttle/cadence assertion: rapid progress events update the store but are coalesced so the row would update at least once per second and never less often while the stream produces data.
- [ ] T028 [P] Front: `src/__tests__/SettingsPanelModelTier.test.tsx` — row renders each sub-state (button / downloading+progress / error+retry); other tier's button disabled while one downloads; byte formatter sv-SE; indeterminate label when total=0.
- [ ] T029 [P] Front: extend `src/__tests__/SettingsPanel.test.tsx` + strings drift test for the seven new keys.

### Destructive (≥8 scenarios across the 6 attack categories)

- [ ] T030 [P] Destructive: rapid double/triple click on Ladda ned starts exactly one download (idempotent); click Ladda ned on tier B while A downloads is blocked (categories: timing, wrong-order).
- [ ] T031 [P] Destructive: cancel at 0 % and at ~99 %; cancel then immediately retry; cancel a non-active tier is a no-op (boundary, timing).
- [ ] T032 [P] Destructive: not-ready spam (click before sidecar ready, repeatedly) never starts a pull and never crashes; bundled-pull-active refuses (skip-steps, wrong-order).
- [ ] T033 [P] Destructive: malformed/garbage pull stream lines, `total:0`/missing-total, total<completed → indeterminate or clamped 100 %, never NaN/divide-by-zero, never a leaked stack trace (invalid input, boundary).
- [ ] T034 [P] Destructive: panel close mid-download then reopen rehydrates progress; keyboard path (Tab to Ladda ned, Enter) starts a download; Escape on the panel does not abort the backend download (accessibility, timing — FR-011).

## Phase 7: Polish & cross-cutting

- [ ] T035 Run full gates: `npm test -- --run`, `cd src-tauri && cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check`, `npm run lint && npm run typecheck`. Fix any cross-spec breakage (e.g. the deleted `TierDownloadRequest` referenced by old spec-010 tests).
- [ ] T036 Visual check via quickstart.md Flows 1–6 in `npm run tauri dev` (Snabb is the fast tier to verify end-to-end). Confirm the contrast fix (Flow 6) still holds in light + dark.
- [ ] T037 `/tla` on the per-tier download state machine (4 states, async boundaries, concurrency guard — non-trivial, so TLA+ applies). Address findings per `validation-followup.md`.

## Dependencies & order

- Phase 1 → 2 → 3 (MVP). US2 and US3 depend on US1's `start_tier_download` + task plumbing (T008/T009) but are otherwise independent of each other.
- T002 (PullEvent bytes) blocks T003/T004/T009 (anything reading progress).
- Tests in Phase 6 follow their feature tasks; the `[P]` tests are mutually parallel (distinct files).
- T037 (`/tla`) runs after browser tests (T030–T034) per the pipeline.

## Parallel execution example

After Phase 2, the Rust test files T021–T026 and the front tests T027–T029 are all `[P]` (distinct files) and can be written concurrently once their feature tasks land.

## MVP scope

Phases 1–3 (T001–T013) deliver the P1 happy path — a user can download a tier and select it. US2 (failure/retry) and US3 (cancel) harden it.
