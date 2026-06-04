# Research: Kontakter grouped per person (spec 040)

## R1 — Merge algorithm shape

**Decision**: Keep `merge_kontakter`'s existing heading-keyed accumulation (one pass over each part's lines, `## `-prefixed trimmed lines switch the current section, non-empty lines append with exact-trim per-section dedup). Change four behaviors:

1. Drop the `CANONICAL` five-category ordering array — all headings render in first-seen order.
2. Pin `## Övriga uppgifter` (exact trimmed match) last, regardless of first-seen position.
3. Route lines seen before any heading into the Övriga section instead of a headingless leading block.
4. Render sections with zero lines as a bare heading instead of dropping them (a found name is information).

**Rationale**: The existing function is already 90% of the per-person merge — heading-keyed, first-seen for unknown headings, per-section dedup. The four deltas are exactly the spec's FR-006–FR-010. Rewriting from scratch would risk the proven traversal.

**Alternatives considered**: (a) parsing into a person struct with categorized fields — rejected: the merge would then have to re-render and could normalize/reorder model text, violating the keep-model-lines-verbatim behavior and adding failure modes; (b) fuzzy name unification across headings — rejected in spec (could merge two real people; Principle VIII).

## R2 — Övriga uppgifter as a reserved heading

**Decision**: Identify the catch-all by exact trimmed heading text `## Övriga uppgifter` (a `const` shared between prompt text and merge).

**Rationale**: The prompt instructs the model to emit exactly this heading; the merge keys on the same constant so prompt and merge can never disagree (same single-source-of-truth pattern spec 039 used for the shared PII regexes).

**Alternatives considered**: heuristic detection of "non-person-looking" headings — rejected: fabricates classification, untestable.

## R3 — Prompt design for gemma3:4b

**Decision**: Rewrite `KONTAKTER_SYSTEM_PROMPT` to demand: one `## ` heading per person; under it bullets prefixed `Adress:` / `Personnummer:` / `Telefon:` / `E-post:`; unattributable details under a final `## Övriga uppgifter`; explicit "gissa aldrig vem en uppgift tillhör" (no force-pairing); omit empty sections; keep the "skriv bara" no-greeting guardrail. Extraction scope unchanged (names + the four categories only).

**Rationale**: Small models follow concrete format examples better than abstract instructions; the prompt includes a one-line shape example as the existing zones' prompts do. The no-force-pairing instruction is the model-side mirror of Principle VIII; the deterministic Övriga-last guarantee for multi-part docs lives in the merge, not in model obedience.

**Alternatives considered**: two-pass extraction (extract then attribute) — rejected: doubles inference time on the slowest path (long docs), and the combine pass already exists for multi-part; per-category extraction with deterministic re-grouping — rejected: pairing person→detail deterministically from category lists is impossible without the document context (that *is* the attribution problem).

## R4 — Single-part path

**Decision**: No post-processing on single-part output (byte-identical pass-through preserved, spec-038 SC-004).

**Rationale**: Clarified 2026-06-04. Running the merge on single outputs would break an established, TLA-verified invariant for marginal gain; short docs have few persons, so prompt steering suffices and the user sees exactly what the model produced (honest output).

## R5 — Test surface inventory

**Decision**: Update in place (no new test files except cases added to existing ones):

- `chunking.rs` g7 unit tests: `g7_kontakter_merges_headings_and_dedups` (canonical-order assertions → person-order assertions), `g7_kontakter_dedup_ignores_surrounding_whitespace` (keep, shape-agnostic), `g7_kontakter_handles_missing_headings_and_empty_parts` (headingless lines now assert Övriga membership + Övriga-last). New cases: Övriga-pinned-last across parts, empty-person-heading preserved, cross-person duplicate preserved, same-person-two-parts union, whole-part-without-headings folds to Övriga, Övriga-only document.
- `zone_pipeline_kontakter.rs`: canned model output and required-token assertions move to per-person shape.
- `zone_pipeline_chunked.rs` `kontakter_multi_chunk_aggregates_with_exactly_once_dedup`: per-person part fixtures; keep exactly-once assertions; add Övriga-last assertion.
- `real_ollama_zones.rs` (ignored, hardware): loosen/update category-heading expectations if pinned.
- vitest `help-strings-drift.test.ts` + Rust `help_strings_drift.rs`: no logic change — fixtures and both mirrors updated together.

**Rationale**: Per project test rules — functional coverage per changed behavior, all existing guarantees re-pinned under the new shape.
