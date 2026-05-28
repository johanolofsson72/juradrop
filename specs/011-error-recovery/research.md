# Phase 0 Research — Spec 011 Error Recovery

**Date**: 2026-05-28
**Status**: Complete (all R-001..R-008 resolved)

## R-001 — Exit code values from Ollama on macOS

**Decision**: Treat all non-zero exit codes (and signal terminations) as "crash". Do NOT branch on the specific code — every non-zero outcome routes through the same retry path + FelOvantat surface.

**Rationale**: Observed exit codes in alpha testing: `0` (clean shutdown — shouldn't fire crash event because drain task gates on `status != stopping`), `137` (SIGKILL — Activity Monitor / OOM killer), `134` (SIGABRT — assertion failure in Ollama itself), `139` (SIGSEGV — memory access violation). Branching on these adds complexity without user benefit; the user always sees the same Swedish copy and the same recovery path. Per Clarification Q4, exit codes never surface in user-facing strings.

**Alternatives considered**: Switch on exit code class (signal vs status vs clean) and surface different Swedish copy. Rejected — over-engineered for the 90% case; Clarification Q5's per-app-lifetime retry budget is the right primitive.

## R-002 — Denylist matching strategy for English-leakage (FR-013)

**Decision**: Case-sensitive `str::contains` on the raw 14 substrings. The denylist patterns are themselves all-lowercase or carry their own intended casing (`Error:` with capital E, `Box<dyn` with capital B, `RUST_BACKTRACE` all-caps).

**Rationale**: We want to catch the literal text Rust emits — and Rust panic messages, type names, and backtrace headers all have stable casing. A case-insensitive scan would false-positive on the Swedish word `Error` if it ever appeared (it doesn't, but defensive). Simple `contains` (no regex) keeps the test fast and dependency-free.

**Alternatives considered**: Regex matching with anchored boundaries — adds the `regex` crate and runtime overhead. Rejected; the false-positive rate of `contains` on these specific substrings is provably zero in our Swedish copy.

## R-003 — Denylist matching strategy for telemetry libraries (FR-015)

**Decision**: Case-insensitive `to_lowercase()` then `contains`. Required because library names appear with varied casing across the four dep manifests — `Sentry` in `Cargo.toml` (PascalCase), `sentry-rs` in `Cargo.lock` (lowercase), `@sentry/react` in `package.json` (lowercase with scope), etc.

**Rationale**: We want to catch any variant. A case-sensitive scan would miss `Sentry` if the contributor typed it that way. Cost: one `to_lowercase()` per file (4 files × ~50 KB avg = 200 KB total — negligible).

**Alternatives considered**: Lowercase only the denylist (not the file content) — wrong direction; the file content can vary in casing, the denylist is fixed.

## R-004 — Directory traversal for the grep tests

**Decision**: Use plain `std::fs::read_dir` recursion. No new dependency on `walkdir` or `ignore`.

**Rationale**: Matches the spec 010 `settings_invariants.rs` pattern that already works in this codebase. Adding `walkdir` for one more test would be a net dep increase for ~5 lines of saved code. The recursion is straightforward (~20 LOC including the visited-directories deduplication and the `node_modules` / `target` / `dist` / dotfile exclusion).

**Alternatives considered**: Spawn `grep -r` as a subprocess — fragile (depends on system grep flavor, breaks on Windows if we ever port), slower, and pollutes test output with subprocess stdout.

## R-005 — CI integration

**Decision**: The new grep tests run as part of the existing `cargo test` command. No new GitHub Actions step, no new shell script.

**Rationale**: The existing CI pipeline (per spec 006) runs `cargo test` as the Rust gate. The new test binaries are picked up automatically because they're `.rs` files under `src-tauri/tests/`. Adding them to the existing pipeline is zero additional CI configuration.

**Alternatives considered**: Standalone shell script in `scripts/check-no-leakage.sh` — adds a second invocation path that can drift from the canonical test, harder to debug locally.

## R-006 — Fixture file naming

**Decision**: `src-tauri/tests/fixtures/crash-recovery-strings.json` as a sibling of the existing `zone-error-strings.json`, `wizard-strings.json`, `settings-panel-strings.json`.

**Rationale**: Same shape as siblings (top-level keys = string names, values = Swedish copy). Same drift-test pattern. A future contributor scanning the fixtures directory sees the spec-by-spec pattern immediately.

**Alternatives considered**: Append to `zone-error-strings.json` under a `crash_recovery` top-level key — couples the two specs more tightly than needed, makes per-spec drift tests harder to scope.

## R-007 — Default Rust panic hook behavior on macOS

**Decision**: Rely on the default Rust panic hook. JuraDrop never calls `std::panic::set_hook` and never sets the `RUST_BACKTRACE` environment variable for the bundled app.

**Rationale**: Default behavior on macOS:
- Panic message + `note: run with RUST_BACKTRACE=1` written to stderr.
- Tauri does NOT surface stderr to the WebView. The WebView only sees what the Rust code explicitly emits via `app.emit(...)` or returns from a `#[tauri::command]`.
- The user does not see the panic — they see the FelOvantat copy from the next status emit.

This satisfies FR-016 (no panic_hook emits anywhere except local stderr) without writing any new code.

**Alternatives considered**: Register a custom panic hook that explicitly writes to a local log file with PII scrubbing. Rejected — adds code, adds maintenance, and the user has no use for the log file (no telemetry, no support form). The default behavior is correct.

## R-008 — Static-grep test for FR-016 (no panic_hook → HTTP/Tauri call)

**Decision**: A simple `cargo test` that walks `src-tauri/src/**/*.rs` and asserts the substring `panic::set_hook` does NOT appear. If a future contributor adds a custom hook, the test fails and forces a Principle I review.

**Rationale**: Static assertion is more conservative than dynamic — even if a future hook only emitted to stderr, the assertion fires and forces a deliberate code review. Default behavior remains correct; only intentional changes are flagged.

**Alternatives considered**: Dynamic panic injection test — fragile because Rust's panic semantics interact awkwardly with `catch_unwind` in test harnesses, and the test would only catch hooks that emit on the specific panic shape we inject.
