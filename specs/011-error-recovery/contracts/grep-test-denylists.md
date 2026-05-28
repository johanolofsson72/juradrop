# Contract — Grep-test denylists

Two new CI tests, both running inside `cargo test`. No new GitHub Actions step, no shell script.

## Test 1: English-leakage denylist (`src-tauri/tests/english_leakage_denylist.rs`)

**Purpose**: Enforce FR-013 — no Rust-language tells or English error patterns in any user-facing string.

**Denylist (14 substrings, case-sensitive)**:

```
panicked at
RUST_BACKTRACE
unwrap()
Result::Err
thread '
Error:
Traceback
cannot borrow
Box<dyn
lock poisoned
mutex poisoned
RefCell
borrowed value
cannot move out of
```

Plus the path-prefix `src-tauri/src/` (FR-013).

**File set**:
- `src/**/*.ts`
- `src/**/*.tsx`
- `src/**/*.json` (except `package.json` and `package-lock.json` which contain English library names by necessity)
- `src-tauri/tests/fixtures/*.json`

**Excludes**: `node_modules`, `target`, `dist`, dotfiles, `src-tauri/tests/english_leakage_denylist.rs` itself (the test source contains the denylist as code).

**Pass criterion**: Zero matches across the file set.

**Failure shape**: `assert!(violations.is_empty(), "english-leakage denylist hit:\n{}", violations.join("\n"))`.

## Test 2: Telemetry-library denylist (`src-tauri/tests/telemetry_denylist.rs`)

**Purpose**: Enforce FR-015 — no crash-reporting or analytics library in the dep tree.

**Denylist (18 substrings, case-insensitive)**:

```
sentry
plausible
posthog
mixpanel
segment
amplitude
bugsnag
rollbar
crashlytics
appcenter
datadog
firebase
googleanalytics
matomo
fathom
umami
splitbee
vercel-analytics
```

**File set** (exactly 4 files):
- `src-tauri/Cargo.toml`
- `src-tauri/Cargo.lock`
- `package.json`
- `package-lock.json`

**Matching**: File contents lowercased; denylist entries already lowercase; `str::contains` then.

**Pass criterion**: Zero matches across the 4 files.

**Failure shape**: `assert!(violations.is_empty(), "telemetry denylist hit:\n{}", violations.join("\n"))`.

## Test 3 (bonus, ratifies R-008): No custom panic_hook

**Purpose**: Enforce FR-016 — no custom panic hook that could route panic output anywhere except local stderr.

**Matcher**: Recursive walk of `src-tauri/src/**/*.rs`; assert the substring `panic::set_hook` does NOT appear in any file.

**Pass criterion**: Zero matches.

**Rationale**: If a future contributor wants to add a custom panic hook (e.g., to write to a crash log file), this test fires and forces a deliberate code review. The default Rust panic hook (stderr-only, no telemetry) is correct per R-007.

## CI integration

All three tests run as part of `cargo test`. No new pipeline configuration. They're picked up automatically because they live in `src-tauri/tests/*.rs`.

A failure in any of them blocks the same way an integration test failure does — `cargo test` exits non-zero, the release workflow halts before the signing + notarization steps.

## Maintenance

When updating either denylist:
1. Update the constant in the test file.
2. Update the corresponding entry count constant in `spec.allium` (`english_leakage_denylist_size` / `telemetry_denylist_size`).
3. Re-run `allium check spec.allium` to confirm the constraint holds.
4. Re-run `cargo test --test english_leakage_denylist --test telemetry_denylist` to confirm the new entries don't false-positive on existing code.
