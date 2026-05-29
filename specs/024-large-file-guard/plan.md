# Implementation Plan: Large-file guard (Spec 024)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: light

## Summary

A `metadata().len()` check at the top of `extract::extract_text` returns the new `ZoneFailure::FileTooLarge` for files over 50 MB, before any per-format read — preventing an OOM on a multi-GB drop. New failure variant mirrored Rust ↔ JSON ↔ TS. No new state machine → skip `/tla`.

## Constitution Check
- **VIII. Honest failure:** PASS — polite Swedish rejection instead of an OOM crash.
- **I. Privacy:** PASS — local metadata check, no outbound.
- Gate: PASS.

## Approach

- `errors.rs`: add `FileTooLarge` variant (`#[error("Filen är för stor — max 50 MB")]`, serde `file_too_large`) + to `ALL_VARIANTS`.
- `extract.rs`: `const MAX_INPUT_FILE_BYTES: u64 = 50 * 1024 * 1024;` + guard at the top of `extract_text` (`if let Ok(m) = fs::metadata(path) { if m.len() > MAX { return Err(FileTooLarge) } }` — metadata error falls through to the existing per-format read path).
- `zone-error-strings.json` + `DropZone.errors.ts` + TS `ZoneFailure` union: add `file_too_large` with the identical string.
- Tests: integration in a new `tests/large_file_guard.rs` (oversized → FileTooLarge; under-cap → reads); the existing errors.rs invariants cover the copy; drift tests (long_tail_drift.rs + DropZone.longtail-formats / SammanfattaZone.errors) extended.

## Phases
1. Rust: variant + const + guard.
2. Cross-language: fixture + TS map + TS union.
3. Tests: integration + drift; full suite + clippy + fmt + typecheck + lint.
