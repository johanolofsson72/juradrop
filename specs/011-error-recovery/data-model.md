# Phase 1 Data Model — Spec 011 Error Recovery

**Date**: 2026-05-28
**Source spec**: [spec.md](spec.md)
**Source Allium**: [spec.allium](spec.allium)

## Entities

### `RetryCounter` (existing — RATIFIED)

`AtomicU8` on `OllamaSidecar`. The contract this spec pins:

```rust
// src-tauri/src/sidecar/manager.rs (already exists)
retry_count: AtomicU8,
```

**Invariants** (formalized by `crash_recovery_invariants.rs`):
- Initial value = 0 (via `AtomicU8::new(0)` in constructor).
- Mutated ONLY by `increment_retry()` which performs `fetch_add(1, Ordering::Relaxed) + 1`.
- Read by `retry_count_value()` (the listener's gate) and `retry_count()` (a sibling accessor).
- Maximum reachable value within a single app lifetime = 1.
- Never decremented within app lifetime (Clarification Q5).

### `SidecarCrashEvent` (existing — RATIFIED)

Tauri event channel + payload.

```rust
// src-tauri/src/sidecar/manager.rs:126 (already exists)
let _ = app_for_emit.emit("juradrop://sidecar-crashed", payload.code);
```

**Schema**:
- Channel: `juradrop://sidecar-crashed` (pinned in `config.crash_event_channel`)
- Payload: `i32` exit code
- Carries no PII, no path, no user-content fragment.

**Lifecycle** (formalized by `crash_recovery_invariants.rs`):
- Fired exactly once per `tokio::process::Child::wait()` completion when the prior status was not `Stopping`.
- Consumed exactly once by the listener registered in `lib.rs` setup.

### `EnglishLeakageDenylist` (NEW)

Static list of 14 substrings. Lives in the test binary as a constant; not exported.

```rust
// src-tauri/tests/english_leakage_denylist.rs
const ENGLISH_LEAKAGE_DENYLIST: &[&str] = &[
    "panicked at",
    "RUST_BACKTRACE",
    "unwrap()",
    "Result::Err",
    "thread '",
    "Error:",
    "Traceback",
    "cannot borrow",
    "Box<dyn",
    "lock poisoned",
    "mutex poisoned",
    "RefCell",
    "borrowed value",
    "cannot move out of",
];
```

Plus path-prefix `src-tauri/src/` as a separate check (FR-013).

**Matching contract**:
- Case-sensitive `str::contains` on file contents.
- File globs: `src/**/*.{ts,tsx,json}` + `src-tauri/tests/fixtures/*.json`.
- Excludes `node_modules`, `target`, `dist`, dotfiles.

### `TelemetryDependencyDenylist` (NEW)

Static list of 18 library-name substrings. Lives in the test binary.

```rust
// src-tauri/tests/telemetry_denylist.rs
const TELEMETRY_DENYLIST: &[&str] = &[
    "sentry", "plausible", "posthog", "mixpanel", "segment",
    "amplitude", "bugsnag", "rollbar", "crashlytics", "appcenter",
    "datadog", "firebase", "googleanalytics", "matomo", "fathom",
    "umami", "splitbee", "vercel-analytics",
];
```

**Matching contract**:
- Case-insensitive — file contents lowercased before `contains`.
- File set: `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `package.json`, `package-lock.json`.
- Any match fails the test with the path + matched substring.

### `CrashRecoveryStrings` (NEW)

Pinned Swedish copy fixture.

```json
{
  "_comment": "Spec 011 — pinned Swedish copy for crash recovery surfaces. FelOvantat (terminal after exhausted retry) + ModelError (in-flight DropJob crash). The cross-language drift test asserts the Rust UserVisibleStatus surface and any TS-side mirror match these values byte-for-byte.",
  "fel_ovantat": "AI-motorn svarar inte. Starta om JuraDrop.",
  "model_error": "AI-motorn svarade inte — försök igen"
}
```

**Drift contract** (formalized by `crash-recovery-strings-drift.test.ts`):
- Both strings ≤ 80 chars (`fel_ovantat` = 42 chars, `model_error` = 35 chars).
- Both wrapped in `SwedishCopy` value at every code-side reference point.
- Both must match the existing source-of-truth in Rust: `fel_ovantat` corresponds to the welcome card's display copy for `UserVisibleStatus::FelOvantat`; `model_error` corresponds to `ZoneFailure::ModelError`'s Display impl.

## Relationships

```text
  ┌──────────────────────┐
  │ tokio::Child::wait() │   (in src-tauri/src/sidecar/manager.rs)
  └──────────┬───────────┘
             │ unexpected exit
             ▼
  ┌──────────────────────┐
  │ SidecarCrashEvent    │ emit("juradrop://sidecar-crashed", exit_code)
  └──────────┬───────────┘
             │
             ▼
  ┌──────────────────────┐
  │ retry_count_value()  │ gate
  └─┬────────────────────┘
    │                     ├─ == 0 ─▶ increment_retry() ─▶ spawn() ─▶ after_sidecar_ready()
    │                     │
    │                     └─ != 0 ─▶ error_override = FelOvantat ─▶ WelcomeCard surfaces
```

The two denylists are TEST-ONLY entities — they live in the test binaries, never in production code. They enforce a STATIC property of the codebase (no telemetry libs in deps, no English tells in user strings), not a runtime invariant.
