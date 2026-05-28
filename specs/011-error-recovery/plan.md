# Implementation Plan: Error Recovery

**Branch**: `main` (solo direct-push) | **Date**: 2026-05-28 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/011-error-recovery/spec.md`

## Summary

Mostly RATIFICATION + 2 NEW grep-enforced invariants. The crash-detection + one-shot-retry machinery already lives in `src-tauri/src/sidecar/manager.rs` (drain task → `juradrop://sidecar-crashed` event) and `src-tauri/src/lib.rs` (listener with `retry_count_value()` gate). The Swedish error surface is already in `src-tauri/src/sidecar/status.rs` (`FelOvantat` + 8 sibling variants). Spec 011 binds these to a formal Allium contract, adds dedicated invariant tests, and adds two NEW CI grep tests:

1. **English-leakage denylist** — 14 substrings (Clarification Q1) that MUST NOT appear in any user-facing string (Swedish copy fixtures + React component literals + Tauri command String error returns).
2. **Telemetry-library denylist** — 18 substrings (Clarification Q2) that MUST NOT appear in any dependency manifest (`Cargo.toml`, `Cargo.lock`, `package.json`, `package-lock.json`).

Plus small Swedish copy hardening: pin the `FelOvantat` recovery instruction copy as final (`AI-motorn svarar inte. Starta om JuraDrop.`), pin the `ModelError` copy used for crash-during-dispatch (`AI-motorn svarade inte — försök igen`), and add both to the cross-language drift fixture.

Net dep delta: **0**. Net new Rust LOC: ~80 (two grep-test binaries + one synthetic-crash integration test). Net new TS LOC: ~30 (one drift test). No new React components, no new state machines, no UI changes.

## Technical Context

**Language/Version**: Rust 1.75+, TypeScript 5.x + React 18.

**Primary Dependencies**: No new deps. Uses existing `tokio::process::Child::wait()`, `parking_lot::RwLock`, `AtomicU8`, `serde_json`. Plain `std::fs::read_dir` recursion for grep tests (matches spec 010 pattern).

**Storage**: None. retry_count is in-memory only; resets on app boot.

**Testing**:
- Rust: 3 new test binaries:
  - `crash_recovery_invariants.rs` — retry-counter monotonicity, copy pinning, channel uniqueness
  - `english_leakage_denylist.rs` — recursive walk of `src/**/*.{ts,tsx,json}` + fixtures
  - `telemetry_denylist.rs` — case-insensitive scan of 4 dep manifests
- TS: `crash-recovery-strings-drift.test.ts` — extends the T035-lineage drift test

**Target Platform**: macOS 11+.

**Project Type**: Desktop app (Tauri + React).

**Performance Goals**:
- SC-001: 100% single-crash auto-heal (no FelOvantat surfaced).
- SC-002: 100% double-crash exhausts retry budget cleanly.
- SC-004: Crash-during-pull recovery within 90s budget on CI.

**Constraints**:
- Principle I: zero outbound from crash-handling code; telemetry-free dep tree.
- Principle VIII: Swedish-only error surface; no stack traces, no English tells.
- No new dependencies.

**Scale/Scope**:
- 0 new files in `src-tauri/src/` (RATIFICATION lives in existing modules)
- 3 new Rust test binaries in `src-tauri/tests/`
- 1 new fixture in `src-tauri/tests/fixtures/`
- 1 new TS test in `src/__tests__/`
- ~80 LOC Rust + ~30 LOC TS

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| **I. Privacy by Architecture** | PASS | This spec STRENGTHENS Principle I by adding the telemetry-denylist invariant (FR-015). The English-leakage invariant (FR-013) strengthens further: stack traces / Rust source paths leaking into user-facing strings would be a Principle I violation in spirit. Zero new outbound traffic, zero analytics, zero crash-reporting. |
| **II. Zero-CLI Install** | PASS | Crash recovery is invisible to the user. The "Starta om JuraDrop" instruction is a quit-and-relaunch via Cmd+Q + dock click — standard macOS user behavior. |
| **III. Local-Only Inference** | PASS | Inherited from spec 002. Retry path re-spawns the same bundled Ollama binary at `127.0.0.1:11434`. No remote-host fallback. |
| **IV. Single-User Desktop App** | PASS | Per-app-lifetime retry budget is per-process = per-user-per-session. No multi-tenant concern. |
| **V. Swedish-First UI, English-First Code** | PASS | This spec STRENGTHENS Principle V by adding the English-leakage denylist (FR-013). |
| **VI. Native macOS Feel** | PASS | No UI changes. FelOvantat reuses the existing welcome card (SF Pro, auto dark/light). |
| **VII. Bundled Sidecar** | PASS | User never sees "Ollama crashed" or "exit code 137". They see `AI-motorn svarar inte. Starta om JuraDrop.` Enforced by FR-013 + Clarification Q4. |
| **VIII. Honest Failure States** | PASS | This spec IS Principle VIII operationalized. Transient failures auto-heal silently; permanent failures surface a clear, named Swedish error with a recovery instruction. The constitution's example wording is pinned verbatim in FR-007 + FR-009. |
| **IX. Open Source, Free, No Lock-In** | PASS | No new deps = no new license obligations. Telemetry-free invariant guarantees JuraDrop will not silently start reporting usage data. |

**Verdict: 9/9 pass.** No Complexity Tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/011-error-recovery/
├── plan.md              # This file
├── spec.md              # Feature spec (with Clarifications + NEW/RATIFIED table)
├── spec.allium          # Formal Allium (0 errors, 14 inherited-pattern warnings dismissed)
├── research.md          # Phase 0 — research findings (small — most behavior is RATIFIED)
├── data-model.md        # Phase 1 — entities + denylists
├── quickstart.md        # Phase 1 — 4 user flows
├── contracts/
│   ├── crash-event-channel.md
│   ├── error-copy-fixture.md
│   └── grep-test-denylists.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 — /speckit-tasks output
```

### Source Code (repository root)

```text
src-tauri/
├── src/
│   ├── sidecar/
│   │   ├── manager.rs                  # NO CHANGE — drain task already correct
│   │   ├── commands.rs                 # NO CHANGE — error_override already correct
│   │   └── status.rs                   # NO CHANGE — UserVisibleStatus already correct
│   ├── lib.rs                          # NO CHANGE — listener already correct
│   └── main.rs                         # OPTIONAL: verify default Rust panic hook is stderr-only

src-tauri/tests/
├── crash_recovery_invariants.rs        # NEW — retry-counter monotonicity, copy pinning, channel uniqueness
├── english_leakage_denylist.rs         # NEW — recursive walk + grep, 14 substrings
└── telemetry_denylist.rs               # NEW — 4-file scan, 18 substrings

src-tauri/tests/fixtures/
└── crash-recovery-strings.json         # NEW — pinned FelOvantat + ModelError Swedish copy

src/__tests__/
└── crash-recovery-strings-drift.test.ts   # NEW — extends T035-lineage drift test
```

**Structure Decision**: Pure additive — three test binaries + one fixture + one drift test + a no-op review of `main.rs` panic hook. No code under `src-tauri/src/` or `src/components/` is modified.

## Phase 0: Outline & Research

See [research.md](research.md). Summary (8 findings):

- **R-001**: Exit code values from Ollama on macOS — exit 0, 137 (SIGKILL), 134 (SIGABRT), 139 (SIGSEGV). None surface in user-facing strings.
- **R-002**: 14-entry English-leakage denylist uses case-sensitive `str::contains`.
- **R-003**: 18-entry telemetry denylist uses `to_lowercase()` + `contains` — case-insensitive.
- **R-004**: No new `walkdir` dep — `std::fs::read_dir` recursion matches the spec 010 pattern.
- **R-005**: Grep tests run inside `cargo test`, not as a separate CI step.
- **R-006**: Drift fixture is a sibling of the existing `zone-error-strings.json` and `settings-panel-strings.json`.
- **R-007**: Default Rust panic hook on macOS writes to stderr only. Tauri does not surface stderr to WebView. JuraDrop never sets `RUST_BACKTRACE`.
- **R-008**: No new `panic::set_hook` registration needed. Default Rust behavior satisfies FR-016.

## Phase 1: Design & Contracts

See:
- [data-model.md](data-model.md) — `SidecarCrashEvent`, `RetryCounter`, `EnglishLeakageDenylist`, `TelemetryDependencyDenylist`, `CrashRecoveryStrings`
- [contracts/crash-event-channel.md](contracts/crash-event-channel.md) — Tauri event channel pinning + payload shape
- [contracts/error-copy-fixture.md](contracts/error-copy-fixture.md) — Swedish copy invariants
- [contracts/grep-test-denylists.md](contracts/grep-test-denylists.md) — the two new CI grep tests
- [quickstart.md](quickstart.md) — 4 user flows

### Re-check Constitution after Phase 1 design

All 9 principles remain PASS. The data-model is purely descriptive (no new state machine, no new mutation point). The contracts are testable assertions about existing behavior + the two new grep tests.

## Complexity Tracking

No constitution violations to justify. Empty.
