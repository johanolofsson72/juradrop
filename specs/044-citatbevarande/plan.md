# Implementation Plan: Citatbevarande (spec 044)

**Branch**: `main` | **Date**: 2026-06-05 | **Spec**: [spec.md](spec.md) + spec.allium

## Summary

New pure module `zones/quote_mask.rs` (the `pii_scrub.rs` template): `mask_quotes(text) -> MaskOutcome { text, spans }` + `restore_quotes(output, spans)`. Wired in `dispatch()`: trigger check (instruction contains "behåll citat", zone ∈ translation zones) → mask BEFORE chunking (global indices, exactly where the 039 scrub sits) → restore on the full combined output BEFORE sidecar build. Both translation prompts gain the unconditional `[CITAT N]`-verbatim guard line. Help entry documents the phrase.

## Technical Context

Rust only (one new module + dispatch wiring + 2 prompt consts + help mirror ×3). No new deps (std string scanning; no regex needed — quote marks are fixed char pairs). No UI change. Tests: unit (mask/restore/collisions/caps/balance), wiremock integration (placeholders in prompts, verbatim restore, dormant byte-identity, chunked cross-boundary), real-model addition to the gated manus suite (SC-005 = Johan's exact field case). `/tla`: triviality-gate expectation (pure transform, 0 states).

## Constitution Check

I: quote registry stack-only, no logs (039 discipline) — PASS·strengthened. II–IX: PASS (no surface changes beyond help copy, humanizer-gated).

## Key mechanics

1. **Trigger** (`quote_mask::is_triggered(zone, instruction)`): `zone.is_translation()` (new tiny `ZoneId` helper) && `instruction.to_lowercase().contains("behåll citat")`.
2. **Masking scan**: single pass over chars; opening marks `”` `“` `"` `»`; a span closes on the matching-class closer (`”`→`”`, `“`→`”`, `"`→`"`, `»`→`«` or `»`); span (incl. marks) ≤ 1000 chars else abandoned (rescan continues AFTER the failed opener); collision-safe numbering: start N above any pre-existing literal `[CITAT k]` in the source (deterministic, tested).
3. **Restore**: simple `output.replace(&placeholder, &original)` per span — placeholder uniqueness guaranteed by numbering; destroyed placeholders no-op.
4. **Wiring** (sammanfatta.rs): after the 039 scrub block, before `split_into_chunks`: `let quote_spans = if quote_mask::is_triggered(...) { mask + swap model_input } else { vec![] }`; after the combine/sweep section, before sidecar build: `restore_quotes(...)` when spans non-empty. (Order vs Anonymisera machinery irrelevant — disjoint zones.)
5. **Prompts**: one sentence appended to TILLENGELSKA/TILLSVENSKA consts: markers `[CITAT 1]` etc. must be reproduced exactly (Swedish, model-facing — 039's proven preservation pattern).
6. **Budget**: prompt growth ≈ +90 chars on two zone prompts — the combine.rs budget test recomputes from real consts; expected to hold trivially.
7. **Help** (FR-007): extend `INSTRUCTION_HELP` body with the documented phrase (3-way mirror + drift tests; humanizer pass).

## Verification mapping

| Req | Proof |
|---|---|
| FR-001/SC-001 | unit round-trips + wiremock: prompt has `[CITAT N]`, lacks originals; sidecar has originals verbatim |
| FR-002/SC-003 | chunked integration: quotes in chunk 1 and 3, global numbering, all restored |
| FR-003/SC-002 | dormant tests: no trigger / wrong zone / "översätt även citaten" ⇒ byte-identical prompt |
| FR-004 | prompt-const tests + budget test |
| FR-005 | unit: destroyed placeholder ⇒ surrounding text intact |
| FR-006/SC-004 | chunked_path_privacy extension: quote_mask module no-log static invariant |
| FR-008/SC-005 | TESTMANUS step 2 re-promoted; real-model manus case (Johan's exact scenario) |
| FR-009 | unit: literal `[CITAT 1]` in source — numbering starts above, restore touches only issued placeholders |
