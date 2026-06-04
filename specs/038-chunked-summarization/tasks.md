# Tasks: Chunked Processing for Long Documents

**Input**: Design documents from `/specs/038-chunked-summarization/`
**Prerequisites**: plan.md, research.md (D1-D10), data-model.md, contracts/chunking.md, spec.allium

**Note on UI**: This feature ships ZERO new frontend code — progress rides the existing
`ZoneSnapshot.progress_hint`, which DropZone.tsx:79 already renders verbatim. The
`frontend-design` skill gate is therefore not triggered (no HTML/CSS/component/Tailwind
work). New Swedish strings still pass the `humanizer` gate (T016).

**Tests**: Required (full track). Functional coverage per implemented function + destructive
scenarios per `.claude/docs/spec-testing-checklist.md` (categories mapped to a desktop
drop-zone app — web-only attacks like URL-jumping/XSS-into-DB are N/A and replaced by
pipeline-level hostile inputs).

## Phase 1: Setup

*(No new dependencies, no scaffolding — net new crates: 0. Phase intentionally empty.)*

## Phase 2: Foundational (blocking prerequisites for all user stories)

- [ ] T001 Create `src-tauri/src/zones/chunking.rs` (pure, std-only): `CHUNK_CHAR_TARGET=24_000`, `MAX_CHUNKS=12`, `CombineStrategy` enum, `ChunkPlan { chunks, was_capped }`, `split_into_chunks(&str) -> ChunkPlan` with boundary cascade paragraph→sentence (Swedish-abbreviation guard: t.ex., bl.a., m.m., dvs., osv., kap., s.k., p.g.a., m.fl., jfr, prop., bet.)→whitespace→UTF-8-safe char fallback; skip whitespace-only slices; register module in `src-tauri/src/zones/mod.rs` (inherits the spec-035 `cfg_attr` deny ratchet)
- [ ] T002 Unit tests in `src-tauri/src/zones/chunking.rs` `#[cfg(test)]`: contract guarantees G2-G6 (single-chunk identity ≤ target; join reproduces processed prefix; ≤ 12 chunks + was_capped semantics; abbreviation guard creates no false boundaries; å/ä/ö multi-byte safety; degenerate inputs: one 30k-char paragraph, one 30k-char sentence, 30k chars with no whitespace, text exactly at/1-char-over CHUNK_CHAR_TARGET and at/over the 288k ceiling)
- [ ] T003 [P] Add `merge_concat(parts) -> String` and `merge_aggregate(zone, parts) -> String` to `src-tauri/src/zones/chunking.rs` per contracts/chunking.md §1 (kontakter heading-grouped bullet dedup in canonical category order; kallor/identifiera strip-number→dedup→renumber; forklara term-key dedup, first wins) + unit tests for G7 (exact-trim exactly-once) incl. hostile shapes: parts with missing headings, empty parts, duplicate items differing only in surrounding whitespace
- [ ] T004 [P] Add `ZoneId::combine_strategy()` exhaustive 12-arm match in `src-tauri/src/zones/zone_id.rs` per contracts §2 + pinning unit test (compiler enforces arm for any future zone)
- [ ] T005 [P] Add `GenerateOptions { num_ctx: u32 }` + `GENERATE_NUM_CTX: u32 = 8192` to `src-tauri/src/sidecar/client.rs`; serialize as `options` in `GenerateRequest`; unit/wiremock test asserting every `/api/generate` body carries `options.num_ctx == 8192` (contracts §3)
- [ ] T006 [P] Rename `TRUNCATION_CHAR_LIMIT` → `EXTRACT_CEILING_CHARS = 288_000` in `src-tauri/src/zones/extract.rs` (doc comment: ceiling = MAX_CHUNKS × CHUNK_CHAR_TARGET; was_truncated now means "exceeded the chunked ceiling"); update the re-export in `src-tauri/src/zones/docx_extract.rs:21` and the pinning tests in `src-tauri/tests/zone_docx_robustness.rs:90-119`
- [ ] T007 [P] Add model-facing Swedish combine/condense instruction constants: `SAMMANFATTA_COMBINE` + `PUNKTLISTA_COMBINE` in `src-tauri/src/prompts/mod.rs` (or sibling files matching existing per-zone layout) and `STRUKTURERA_CONDENSE` in `src-tauri/src/prompts/strukturera.rs`; each instructs the model that the input consists of partial results ("Del 1: … Del N: …") to condense per the zone's output conventions; unit test pins that combine passes route through `frame_prompt` with DOKUMENT framing + guard (FR-007)

**Checkpoint**: chunking/merging/strategy/num_ctx/ceiling all unit-green — no dispatch changes yet; full existing suite still green.

## Phase 3: User Story 1 — Summarize a long document end to end (P1) + reduce/condense family

**Goal**: 100-page drop on Sammanfatta produces a whole-document summary; Strukturera gets condense-then-structure.
**Independent test**: multi-chunk sammanfatta integration test with sentinels in first/middle/last chunk appears in combined output; no truncation disclaimer.

- [ ] T008 [US1] Rework `DropZone::dispatch` in `src-tauri/src/zones/sammanfatta.rs`: build `ChunkPlan` after extraction; single-chunk plans take the existing path verbatim (one generate, no new snapshots); multi-chunk plans run the sequential loop — per chunk: emit `ZoneState::Processing` snapshot with `progress_hint = "Bearbetar del {i} av {n}…"`, `tokio::select!` generate vs cancel_token, `is_cancelled()` re-check between chunks; collect per-chunk outputs in order
- [ ] T009 [US1] Implement combine step in `src-tauri/src/zones/sammanfatta.rs`: emit "Sammanställer…" snapshot; `Reduce` → label partials "Del {i}:" + one framed combine generate (raced vs cancel; recursive re-chunk safety net if combine input > CHUNK_CHAR_TARGET); `CondenseThenStructure` → per-chunk passes already used STRUKTURERA_CONDENSE, then one framed strukturera pass over joined condensates; `Concat`/`Aggregate` → `merge_concat`/`merge_aggregate` (no model call); any combine error → `finalize_with_failure(ModelError)`
- [ ] T010 [US1] Integration test `src-tauri/tests/zone_pipeline_chunked.rs` (extend `tests/common/mod.rs` harness with a sequenced-response + request-recording wiremock variant): long generated txt fixture (3 sentinels spread across ≥3 chunks) on Sammanfatta → request count = chunks+1, every request has num_ctx 8192 + DOKUMENT framing + ≤ prompt-size bound, combined sidecar contains all sentinel-bearing partials, NO truncation disclaimer (SC-001, FR-005/006/007); single-chunk doc → exactly 1 request, output byte-pattern matches pre-038 (SC-004)

**Checkpoint**: US1 demonstrable on its own (MVP).

## Phase 4: User Story 2 — Ordered transforms in full (P2)

**Goal**: Till svenska/engelska, Förenkla, Anonymisera process every chunk, concat in order; anonymisera multi-chunk disclosure.
**Independent test**: numbered-section fixture through a concat zone preserves all sections in order.

- [ ] T011 [US2] Anonymisera multi-chunk handling in `src-tauri/src/zones/sammanfatta.rs`: after concat-combine, prepend the FR-014 Swedish review-disclaimer paragraph (pattern of pii_sweep warning prepend, sammanfatta.rs:258-266) BEFORE the pii sweep runs on the full combined output (FR-010 ordering: disclaimer ahead of sweep warning, sweep scans combined text)
- [ ] T012 [P] [US2] Integration tests in `src-tauri/tests/zone_pipeline_chunked.rs`: (a) tillsvenska multi-chunk — numbered sections 1..N spread over chunks, output contains all sections in chunk order, no gaps (SC-002); (b) anonymisera multi-chunk — sweep warning computed from COMBINED output (plant residue in last chunk's mock response) + multi-chunk disclaimer present + single-chunk anonymisera carries NO new disclaimer (FR-014)

## Phase 5: User Story 3 — Extraction without losing the tail (P2)

**Goal**: Kontakter/Kallor/Identifiera/Forklara aggregate across chunks with exactly-once dedup.
**Independent test**: sentinel item only in the final chunk appears exactly once in output.

- [ ] T013 [P] [US3] Integration tests in `src-tauri/tests/zone_pipeline_chunked.rs`: kontakter multi-chunk — unique phone sentinel in final chunk's mock response appears exactly once under `## Telefonnummer`; duplicate contact across two chunk responses appears once (SC-003); kallor renumbering yields strictly sequential numbering after merge

## Phase 6: User Story 4 — Honest progress and honest failure (P3)

**Goal**: per-part progress visible; mid-run failure → Swedish error, no sidecar; concurrency intact.
**Independent test**: failure injected on chunk 2 of 3 → Error state, no sidecar file exists.

- [ ] T014 [US4] Integration tests in `src-tauri/tests/zone_pipeline_chunked.rs`: (a) snapshot sequence on the zone channel contains "Bearbetar del 1 av N…" → … → "Sammanställer…" → success, monotonically (SC-006); (b) wiremock fails chunk 2 of 3 → ZoneFailure::ModelError snapshot, target sidecar path does NOT exist (SC-005, FR-009); (c) cancel fired mid-chunk-2 → cancellation flash, no sidecar, no further generate requests (existing cancel semantics preserved per-chunk)
- [ ] T015 [P] [US4] Playwright addition in `tests/e2e/` (zones spec): via the mock bridge, emit a processing snapshot with `progress_hint: "Bearbetar del 2 av 5…"` and assert the zone renders that text; then emit success and assert normal flow (frontend functional coverage for the one user-visible change)

## Phase 7: Polish & Cross-Cutting

- [ ] T016 Run the `humanizer` skill over the three new user-facing Swedish strings ("Bearbetar del {i} av {n}…", "Sammanställer…", anonymisera multi-chunk disclaimer) and apply the reviewed copy in `src-tauri/src/zones/sammanfatta.rs` (BLOCKING gate per CLAUDE.md before ship)
- [ ] T017 [P] Destructive-scenario sweep (≥8, categories mapped per spec-testing-checklist; add to `src-tauri/tests/zone_pipeline_chunked.rs` / `chunking.rs` tests where marked): (1) invalid input — model returns empty string on chunk pass → EmptyResponse → ModelError, no sidecar; (2) invalid input — hostile document containing literal `--- DOKUMENT SLUTAR ---` inside a chunk still framed safely (extends framing test to chunked path); (3) wrong order/timing — second drop during multi-chunk run bounces with ZoneBusy toast, in-flight run undisturbed; (4) timing/race — cancel lands between chunk N completion and N+1 start → no further requests; (5) timing/race — tier switch mid-run: model_id stays pinned for all chunks of the in-flight job (spec-010 invariant extended); (6) boundary — document exactly at 12×24k ceiling → 12 chunks, was_capped=false, no disclaimer; one char over → was_capped=true + disclaimer; (7) boundary — chunk responses that individually exceed CHUNK_CHAR_TARGET trigger the recursive reduce safety net and terminate; (8) resource — concurrency_stress-style simultaneous multi-zone drops while one zone runs a 3-chunk job: no cross-zone contamination (extend existing pattern); (9) accessibility (Playwright) — progress text exposed via the zone's existing accessible name/label surface (no regression in zones.spec a11y assertions)
- [ ] T018 [P] Privacy regression check: assert no chunk content appears in any log path (`Redacted` preserved through chunk loop — extend `seam_privacy_invariant.rs` or telemetry_denylist pattern to the chunked path); confirm net outbound = same single localhost endpoint (no new URLs in diff)
- [ ] T019 Full gate sweep: `cd src-tauri && cargo test` + `cargo clippy --all-targets -- -D warnings` + `cargo fmt --check`; `npm test`; `npm run lint && npm run typecheck`; `npm run test:e2e` — all green
- [ ] T020 Manual verification per quickstart.md on real model (`npm run tauri dev`) — DEFERRED-TO-USER if no Mac GUI/model available in the execution environment; pipeline + smoke tests substitute, user runs the visual pass

## Dependencies

```text
Phase 2 (T001→T002; T003,T004,T005,T006,T007 parallel after T001)
  └─→ Phase 3 (T008 → T009 → T010)   [US1 — MVP]
        ├─→ Phase 4 (T011 → T012)     [US2; T011 depends on T009 combine step]
        ├─→ Phase 5 (T013)            [US3; needs T003 merges + T009 wiring]
        └─→ Phase 6 (T014, T015)      [US4; needs the loop from T008/T009]
              └─→ Phase 7 (T016 … T020 final)
```

## Parallel execution examples

- After T001: T003, T004, T005, T006, T007 touch disjoint files — run in parallel.
- After T010: T012, T013, T014 are independent test additions to the same new test file —
  write sequentially or in one batch; T015 (Playwright) and T017/T018 are parallel-safe.

## Implementation strategy

MVP = Phase 2 + Phase 3 (US1): chunked Sammanfatta proves the whole machinery (plan, loop,
progress, reduce-combine, num_ctx). Phases 4-6 wire the remaining strategies and harden.
Phase 7 gates ship-readiness. Single-chunk behavior is bit-stable throughout — every phase
keeps the full existing suite green, so the feature can pause at any checkpoint without
regressing current users.
