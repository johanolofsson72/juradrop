# Implementation Plan: Concurrency stress tests (Spec 017)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: spec-only

## Summary

One integration test, `concurrency_stress.rs`, fires all 9 zone pipelines concurrently (per-zone wiremock + mock app + fixture copy) via `join_all`, over 3 rounds, asserting per-zone correctness, no cross-zone contamination, byte-identical sources, bounded time. Reuses the spec-013 harness pattern. No new deps.

## Constitution Check
- **III. Local-only / IV. single-user:** PASS — mocked Ollama, local temp files.
- Gate: PASS.

## Approach

- A `ZONE_CASES` table: 9 × (ZoneId, fixture_name, mock_response, &[markers]) reusing the per-zone data shape from the spec-013 individual tests.
- A self-contained per-zone async runner (mirrors `common::run_zone_pipeline` but returns the sidecar path + text instead of asserting inline, so the caller can cross-check isolation).
- `for round in 0..3 { join_all(9 runners).await; assert each }`.
- Cross-contamination check: for each completed (zone, sidecarText), assert the text does NOT contain another zone's unique marker.
- `futures::future::join_all` (futures already a direct dep) — no Send bound needed (no spawn).

## Phases

1. Write `concurrency_stress.rs` (table + runner + 3-round loop + isolation assertions).
2. Run; if a race/contamination surfaces, fix the code (FR-006).
3. Full suite + clippy + fmt.
