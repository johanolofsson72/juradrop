# Implementation Plan: Real-Ollama slow suite (Spec 018)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: spec-only

## Summary

One `#[ignore]`'d looping test runs a real `gemma3:4b` inference per zone on the committed fixtures, asserting shape/presence (sidecar, non-empty, source unchanged, disclaimer). Skips cleanly without the model. `ignore_audit` expected count bumped 1→2. No new deps.

## Constitution Check
- **III. Local-only inference:** PASS — targets 127.0.0.1:11434 only.
- **I. Privacy:** PASS — local, fixtures are synthetic test data.
- Gate: PASS.

## Approach

- Reuse the spec-013/017 harness shape (mock_builder app + real `OllamaClient::with_base_url("http://127.0.0.1:11434")`).
- Skip guard up front via `client.list_tags()`: Err → skip; no `gemma3:4b` → skip.
- Loop `zone_cases()` (same 9 zone/fixture pairs); per zone: copy fixture to TempDir, `handle_drop`, poll ≤120s for sidecar, assert presence/non-empty/source-unchanged/disclaimer.
- Update `tests/ignore_audit.rs`: `ignore_count == 2`, comment naming both hardware tests.

## Phases
1. Write `real_ollama_zones.rs` (ignored + skip guard + 9-zone loop).
2. Update `ignore_audit.rs` count.
3. Verify: `cargo test` green (slow test ignored); `cargo test --test real_ollama_zones -- --ignored` skips cleanly here (no model); clippy + fmt.
