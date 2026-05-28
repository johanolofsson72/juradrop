# Quickstart — Spec 011 Error Recovery

**Four user flows the implementation must satisfy.** Each has an explicit test that proves it.

## Flow 1 — Single transient crash auto-heals silently (SC-001)

**Pre-conditions**: App running with sidecar Ready, model `gemma3:4b` pulled, user about to drop a `.docx` on Sammanfatta.

**Steps**:
1. Drop a `.docx` on Sammanfatta. The dispatch starts.
2. While the inference is running, inject a SIGKILL into the Ollama child process (test seam: kill the PID stored by the sidecar manager).
3. The drain task awaits the exit and emits `juradrop://sidecar-crashed`.
4. The listener observes `retry_count_value() == 0`, increments to 1, spawns a fresh sidecar.
5. Within 10 seconds, `wait_ready` succeeds and `after_sidecar_ready` runs.
6. The in-flight DropJob terminates with `ZoneFailure::ModelError`; the zone returns to idle within the standard error-clear budget.
7. The user drops the same `.docx` again. The new dispatch runs against the freshly-spawned sidecar and produces a correct sidecar file.

**Assertions**:
- `useStatusStore.status.visible` never equals `fel_ovantat` during or after the test.
- The zone's `visible_state` returns to `idle` within `zone_error_clear_budget_seconds` (=4s).
- The retry dispatch completes successfully against the same model.
- `sidecar.retry_count_value()` == 1 at end of test.

## Flow 2 — Double crash exhausts the retry budget, surfaces FelOvantat (SC-002)

**Pre-conditions**: Same as Flow 1.

**Steps**:
1. Inject the first SIGKILL. Listener retries → sidecar Ready.
2. Inject a second SIGKILL within the same app session.
3. The drain task fires `juradrop://sidecar-crashed` again.
4. The listener observes `retry_count_value() != 0`, logs `retry budget exhausted; holding Crashed` (debug-only), and does NOT call `sidecar.spawn`.
5. `error_override` is set to `FelOvantat`.
6. The welcome card displays exactly `AI-motorn svarar inte. Starta om JuraDrop.`
7. Closing and re-opening the app resets the retry budget to 0 and the sidecar bootstraps normally.

**Assertions**:
- `sidecar.spawn` is called exactly 2 times across the test (initial + first retry). A spy mock asserts this.
- After the second crash, `useStatusStore.status.visible == 'fel_ovantat'`.
- The welcome card's rendered text contains the pinned Swedish copy.
- No English tells, no exit code, no signal name in the rendered DOM.

## Flow 3 — Crash mid-pull discards partial download and resumes (SC-004)

**Pre-conditions**: Fresh install. User has clicked Fortsätt on the consent modal; download is at ~50% progress.

**Steps**:
1. While the pull stream is downloading, inject a SIGKILL.
2. The pull stream's `bytes_stream` drops (connection lost), the wizard's progress slice eventually shows 0.
3. The drain task emits the crash event; the listener retries.
4. Re-spawn succeeds; `after_sidecar_ready` re-runs, detects model NOT present + consent fortsatt, and triggers a fresh pull task with a new cancellation token.
5. The wizard's progress UI resumes from 0%.
6. The total recovery + completion time stays within 90 seconds on a wired test runner.

**Assertions**:
- `useStatusStore.status.progress_percent` is 0 within 1 second of the crash injection.
- `AppState.pull_cancel.is_cancelled()` is true immediately after the crash.
- A fresh `juradrop://progress` event fires with `percent < 5` after re-spawn.
- The eventual `klar` state matches the no-crash success path byte-for-byte (same `gemma3:4b` tag list).

## Flow 4 — Crash-during-dispatch returns the zone to idle, no quit required

**Pre-conditions**: Sidecar Ready, model pulled, no zone in flight.

**Steps**:
1. Drop a `.docx` on Punktlista. Dispatch begins.
2. ~500ms into the inference, inject SIGKILL.
3. The `client.generate` call returns `Err` (connection refused / EOF).
4. The dispatch path in `sammanfatta.rs` catches the error and calls `finalize_with_failure(..., ZoneFailure::ModelError)`.
5. The zone emits a snapshot with `state: error` and `failure: model_error`.
6. The error-clear schedule fires after `zone_error_clear_budget_seconds`; the zone returns to `idle`.
7. The retry listener (firing in parallel) re-spawns the sidecar.
8. The user drops the same `.docx` again. The new dispatch succeeds.

**Assertions**:
- The zone's emitted snapshot includes the Swedish `AI-motorn svarade inte — försök igen` copy.
- The zone is `idle` within `zone_error_clear_budget_seconds + 1` of the crash.
- A subsequent drop on the same zone produces a correct output file.
- No app quit / relaunch needed between the crashed dispatch and the successful retry dispatch.
