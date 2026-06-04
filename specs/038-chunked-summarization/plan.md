# Implementation Plan: Chunked Processing for Long Documents

**Branch**: `038-chunked-summarization` (register row; work happens on `main` per project workflow) | **Date**: 2026-06-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/038-chunked-summarization/spec.md`

## Summary

Long documents are silently double-clipped today: extraction hard-cuts at 24,000 chars
(extract.rs:20) and the Ollama call sets no `num_ctx`, so the model clips again at its 4k
default. Fix: (1) explicit `num_ctx = 8192` on every generate; (2) structure-aware chunking
into ≤ 12 × 24k-char chunks processed sequentially through the existing generic
`DropZone::dispatch` pipeline, with per-zone combine semantics (reduce / concat / aggregate /
condense-then-structure), per-part Swedish progress riding the existing `progress_hint`, and
all-or-nothing failure semantics. Extraction ceiling moves to 288,000 chars (~240 pages); the
existing truncation disclaimers stay wired to the new ceiling so they remain honest.

## Technical Context

**Language/Version**: Rust 1.7x (src-tauri), TypeScript/React 18 (src/) — no frontend changes expected

**Primary Dependencies**: Tauri 2.x, tokio, reqwest, wiremock (tests) — net new deps: 0

**Storage**: N/A (no settings change, no persistence change)

**Testing**: cargo test (unit + wiremock integration via tests/common harness), vitest (unchanged surface), Playwright smoke (one progress-hint assertion)

**Target Platform**: macOS desktop (Tauri WKWebView)

**Project Type**: Desktop app — Rust core + React frontend

**Performance Goals**: 100-page document fully processed; worst case (12 chunks + combine on Stor) ≤ ~30 min; single-chunk documents: zero added latency (same single call)

**Constraints**: Local-only inference (127.0.0.1:11434), no new outbound traffic, 50 MB input guard stays, 180 s per-call timeout stays, memory bounded by 288k-char extraction ceiling

**Scale/Scope**: 11 document-consuming zones share one orchestration change; ~1 new Rust module + edits in 4 existing modules; ~15-20 tasks

## Constitution Check

*GATE: evaluated 2026-06-04 pre-Phase-0; re-evaluated post-Phase-1 — PASS.*

| Principle | Verdict | Evidence |
|---|---|---|
| I. Privacy by Architecture | PASS | Chunking is in-process string slicing; `options.num_ctx` is a body field on the SAME localhost call; no new outbound, no content persistence. Chunk content never logged (`Redacted` wrapping preserved end-to-end). |
| II. Zero-CLI Install | PASS | No install-path change. |
| III. Local-Only Inference | PASS | Same `OllamaClient` base_url; no remote-host capability added. |
| IV. Single-User Desktop App | PASS | No daemon/service change. |
| V. Swedish UI, English Code | PASS | New user-facing strings (2 progress hints + 1 anonymisera disclaimer) in Swedish via humanizer; code/comments English. |
| VI. Native macOS Feel | PASS | Progress text rides the existing zone hint surface; no new chrome. |
| VII. Bundled Sidecar | PASS | No Ollama lifecycle change. |
| VIII. Honest Failure States | PASS | All-or-nothing runs; mid-chunk failure → existing ModelError Swedish copy; truncation disclaimer now fires only when content is genuinely skipped (>240 pages) — *more* honest than today. |
| IX. Open Source, No Lock-In | PASS | Output formats unchanged. |

No violations → Complexity Tracking not required.

## Project Structure

### Documentation (this feature)

```text
specs/038-chunked-summarization/
├── plan.md              # This file
├── research.md          # Phase 0 — decisions D1-D10
├── data-model.md        # Phase 1 — ChunkPlan/Chunk/CombineStrategy shapes
├── quickstart.md        # Phase 1 — manual verification script
├── contracts/
│   └── chunking.md      # Phase 1 — module contract + generate-request contract change
├── spec.allium          # /allium:elicit output (pre-implementation baseline)
└── tasks.md             # Phase 2 (/speckit-tasks — not created by /speckit-plan)
```

### Source Code (repository root)

```text
src-tauri/src/
├── zones/
│   ├── chunking.rs          # NEW — pure module: split_into_chunks, ChunkPlan,
│   │                        #   CombineStrategy, merge_aggregate, merge_concat
│   ├── extract.rs           # MOD — TRUNCATION_CHAR_LIMIT → EXTRACT_CEILING_CHARS (288_000),
│   │                        #   + CHUNK_CHAR_TARGET (24_000) re-export home
│   ├── sammanfatta.rs       # MOD — dispatch(): chunk plan, sequential loop w/ progress
│   │                        #   snapshots + cancel races, combine step, anonymisera
│   │                        #   multi-chunk disclaimer prepend
│   └── zone_id.rs           # MOD — ZoneId::combine_strategy() exhaustive match (12 arms)
├── prompts/
│   ├── mod.rs               # MOD — combine-instruction constants (model-facing Swedish):
│   │                        #   reduce-combine for sammanfatta/punktlista, condense for
│   │                        #   strukturera; frame_prompt reused for combine passes
│   └── strukturera.rs       # MOD — condense-pass prompt constant
└── sidecar/
    └── client.rs            # MOD — GenerateRequest.options { num_ctx: 8192 }

src-tauri/tests/
├── (chunking unit tests)    # in-module #[cfg(test)] (boundaries, abbreviations, ceiling,
│                            #   merge dedup, UTF-8 safety)
├── zone_pipeline_chunked.rs # NEW — multi-chunk integration: sequenced wiremock responses,
│                            #   request count, num_ctx + framing per request, progress
│                            #   snapshots, mid-chunk failure → no sidecar, cancel mid-run,
│                            #   anonymisera combined-sweep + disclaimer, capped disclaimer
└── zone_docx_robustness.rs  # MOD — 24k pins → 288k ceiling pins

tests/e2e/                   # MOD — one Playwright assertion: emitted processing snapshot
                             #   with progress_hint "Bearbetar del 2 av 5…" renders in zone
```

**Structure Decision**: Single orchestration point — the generic `DropZone` in
zones/sammanfatta.rs runs all 12 zones, so the chunk loop lands exactly once. Chunking
itself is a pure std-only module for exhaustive unit testing.

## Execution flow (implementation order)

1. **chunking.rs** (pure logic + unit tests): `split_into_chunks(&str) -> ChunkPlan`,
   boundary cascade paragraph→sentence (Swedish-abbrev guard)→whitespace→char, skip-blank
   rule, ceiling cap + `was_capped`, `CombineStrategy` + `ZoneId::combine_strategy()`,
   deterministic `merge_concat` / `merge_aggregate` (heading/numbered/bullet-aware,
   exact-trim dedup).
2. **client.rs**: `GenerateOptions { num_ctx }` serialized into `GenerateRequest`; constant
   `GENERATE_NUM_CTX = 8192`.
3. **extract.rs**: ceiling rename + 288_000; update pinning tests.
4. **prompts**: combine instructions (sammanfatta-combine, punktlista-combine,
   strukturera-condense) as model-facing constants; combine passes reuse `frame_prompt`
   DATA framing (FR-007).
5. **dispatch loop** in sammanfatta.rs: plan → if single chunk, existing path verbatim →
   else loop (progress snapshot → select! generate vs cancel → collect) → combine per
   strategy (reduce/condense passes also select! vs cancel) → anonymisera disclaimer +
   sweep on combined → existing writer/open/success tail.
6. **Swedish strings** through humanizer: "Bearbetar del {i} av {n}…", "Sammanställer…",
   anonymisera multi-chunk disclaimer paragraph.
7. **Integration tests** (zone_pipeline_chunked.rs) + Playwright progress assertion.
8. Full gate sweep: cargo test, clippy -D warnings, fmt, vitest, typecheck, eslint,
   Playwright.

## Post-Design Constitution Re-Check

Re-evaluated after Phase 1 design: still PASS on all nine principles. The only borderline
item examined: per-chunk progress strings could theoretically leak content — they are
format-string constants with integers only (`del {i} av {n}`), never document text, matching
the snapshot.rs:53 "pre-defined Swedish phrase, never document content" contract.
