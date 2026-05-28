# Implementation Plan: Parser robustness battery (Spec 015)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: spec-only

## Summary

One integration test, `parser_robustness.rs`, generates a deterministic battery of malformed inputs and runs every extractor over them inside `catch_unwind`, asserting no panic + typed `ZoneFailure` on failure. No new deps, no nightly, runs on every `cargo test`.

## Constitution Check

- **VIII. Honest failure:** PASS — this directly hardens the no-stack-trace-leak promise.
- **I. Privacy:** unaffected (local test only).
- Gate: PASS.

## Approach

- Deterministic byte generators: `seeded_bytes(seed, len)` via xorshift64; `truncations(valid)` → [1/4, 1/2, 3/4]; static cases (empty, `[0]`, magic+garbage, null-embedded, invalid-UTF-8).
- Read the committed spec-013 probe fixtures as the "valid" base for truncation cases (`tests/fixtures/extraction-probe/extraction-probe.<ext>`).
- For each format, map to its extractor via `juradrop_lib::zones::extract::extract_text(path, InputFormat::X)` (writes bytes to a TempDir file first, since extractors take `&Path`).
- `catch_unwind(AssertUnwindSafe(|| extract_text(...)))`; assert `.is_ok()` at the catch level (i.e. no panic). The inner `Result<ExtractedText, ZoneFailure>` may be Ok or Err — both acceptable.
- If any catch returns `Err` (a panic), the test fails loudly naming the (format, input); fix the extractor (FR-005).

## Phases

1. Write `parser_robustness.rs` with generators + the 6-format battery.
2. Run it; if panics surface, patch the offending extractor to return `ZoneFailure`.
3. Full suite + clippy + fmt.
