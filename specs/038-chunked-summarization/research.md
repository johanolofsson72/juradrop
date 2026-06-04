# Research: Chunked Processing for Long Documents (038)

All decisions below are grounded in code read on 2026-06-04. No NEEDS CLARIFICATION remain.

## D1 — Context window: explicit `num_ctx = 8192` on every generate call

**Decision**: Add `options: {"num_ctx": 8192}` to the Ollama `/api/generate` request body
(`GenerateRequest`, src-tauri/src/sidecar/client.rs:252). One constant for all three tiers.

**Rationale**: Ollama's default context window (4096 in current builds, 2048 historically) is
*smaller* than today's 24,000-char (~6,000-token) input cap — the model has been silently
clipping our already-truncated input a second time. This is the root cause of "even ~20 pages
sometimes summarize as less". Budget: framing + system prompt (~400 tokens) + 24k chars Swedish
(~6,000 tokens) + response headroom (~1,500 tokens) ≈ 7,900 → 8192 fits with margin.
All three tier models (llama3.2:1b, gemma3:4b, gemma3:12b) support ≥ 8k context; KV-cache
memory at 8192 is acceptable on the 8 GB-Mac floor the tiers already assume.

**Alternatives considered**: Per-tier num_ctx (rejected: no benefit — 8192 fits all three;
uniform constant is simpler and FR-011 allows it). Huge num_ctx + no chunking (rejected:
small-model long-context recall collapses — a 1b/4b model genuinely loses the middle; KV cache
at 32k+ on gemma3:12b would OOM 16 GB machines; chunking is needed regardless).

## D2 — Chunk size: keep 24,000 chars as the per-chunk target, uniform across tiers

**Decision**: `CHUNK_CHAR_TARGET = 24_000` (the proven single-pass size becomes the per-chunk
size). Extraction ceiling becomes `12 × 24_000 = 288_000` chars (clarified ceiling).

**Rationale**: 24k chars ≈ 6k tokens is already the validated sweet spot for the smallest tier
(spec 003/018 ran all zones at this size on real models). Reusing it means the single-chunk
path is byte-identical to today (FR-002/SC-004 for free).

## D3 — Boundary detection: paragraph → sentence → whitespace → char (last resort)

**Decision**: New pure module `src-tauri/src/zones/chunking.rs`. Greedy accumulation of
paragraph blocks (`\n\n` separators, which extraction's blank-line collapse already normalizes)
up to the target; a single paragraph larger than the target splits at sentence boundaries
(`. `, `? `, `! `, `.\n`…) with a Swedish abbreviation guard (t.ex., bl.a., m.m., dvs., osv.,
kap., s.k., p.g.a., m.fl., jfr, prop., bet.); a single sentence larger than the target splits
at the last whitespace before the limit; pathological whitespace-free runs fall back to a
char-boundary cut (UTF-8-safe via `char_indices`, mirroring `truncate_to_char_limit`).
Whitespace-only chunks are skipped (spec edge case).

**Rationale**: extraction already collapses blank-line runs (extract.rs:65), so `\n\n` is a
reliable paragraph separator across all 6 input formats. Pure functions → exhaustive unit
tests without a Tauri app.

**Alternatives considered**: Token-based splitting via a tokenizer crate (rejected: new
dependency for marginal precision; the char-proxy is already calibrated for Swedish).
Sliding-window overlap between chunks (rejected for v1: doubles model passes at the seams;
concat zones would duplicate content; revisit only if seam quality is a field problem).

## D4 — Where chunking integrates: `DropZone::dispatch`, extraction keeps one text

**Decision**: `extract::finalise()` keeps truncating, but at the new 288,000-char ceiling
(`was_truncated` now means "exceeded the chunked ceiling"). `DropZone::dispatch`
(src-tauri/src/zones/sammanfatta.rs:165) builds a `ChunkPlan` from `extracted.raw`; 1 chunk →
exactly today's code path (one `client.generate`, no combine); >1 chunk → sequential per-chunk
generate loop with progress snapshots, then combine, then the existing pii-sweep / writer /
open tail. `TRUNCATION_CHAR_LIMIT` is renamed `EXTRACT_CEILING_CHARS` (= 288_000) and
`CHUNK_CHAR_TARGET` (= 24_000) is added; the pinning tests in zone_docx_robustness.rs:90-119
update to the ceiling.

**Rationale**: one orchestration point (the generic DropZone runs all 12 zones), zero changes
to extractors, writers keep their `was_truncated` wiring — the existing truncation disclaimers
("Texten kortades av — modellen såg bara början…" / "(Dokumentet förkortades…)") remain
*honest* under the new meaning: they now fire only above ~240 pages (FR-006/FR-013). No new
disclaimer copy needed for the capped case.

## D5 — Combine strategies (per clarified FR-004)

| Strategy | Zones | Mechanism |
|---|---|---|
| `Reduce` | Sammanfatta, Punktlista | Per-chunk pass with the zone's own prompt → partials labelled "Del 1:…Del N:" → ONE combine model pass with a zone-specific Swedish combine instruction (model-facing, not UI copy) framed as DOKUMENT per spec 022. If combine input > CHUNK_CHAR_TARGET, recursively re-chunk the partials (safety net; 12 × ~2k-char partials fit in one pass in practice). |
| `Concat` | TillEngelska, TillSvenska, Forenkla, Anonymisera | Deterministic join of per-chunk outputs in index order, `\n\n`-separated. No combine model call. |
| `Aggregate` | Kontakter, Kallor, Identifiera, Forklara | Deterministic structural merge in code: bullet/numbered/heading-aware line merge with exact-match dedup (trimmed, case-preserving). Kontakter merges under its `## category` headings; Kallor + Identifiera renumber the merged list; Forklara dedups on the term before the first dash/colon. No combine model call → SC-003 "exactly once" is deterministic, not probabilistic. |
| `CondenseThenStructure` | Strukturera | Per-chunk condensation pass (new model-facing Swedish condense prompt preserving rättsfrågor, domslut, citerade lagrum *from the text*) → strukturera's existing IRAC prompt runs once over the joined condensates. |
| `Exempt` | Generera | Input is user instructions; never chunked (instructions ≤ ceiling in practice; if oversized, existing ceiling truncation applies). |

**Rationale for deterministic aggregate**: model-side dedup on a 1b model is a coin flip;
SC-003 requires exactly-once. Exact-match dedup is the FR-004 contract ("duplicates removed");
near-duplicate ("08-555 12 34" vs "08-5551234") merging is explicitly out of scope, documented.

## D6 — Progress: ride the existing `progress_hint`

**Decision**: Multi-chunk runs emit additional `ZoneState::Processing` snapshots on the
existing per-zone channel with `progress_hint = "Bearbetar del {i} av {n}…"`; the combine
phase emits `"Sammanställer…"`. Single-chunk runs keep the existing per-zone
`processing_hint()` untouched.

**Rationale**: `ZoneSnapshot.progress_hint` (snapshot.rs:60) is already rendered verbatim by
the frontend (DropZone.tsx:79 — `if (zoneSnap.progress_hint) return zoneSnap.progress_hint`),
and the store just keeps the latest snapshot. **Zero frontend code changes; zero TS type
changes; zero new event channels.** The two new Swedish strings are user-facing → humanizer
review required.

## D7 — Failure + cancellation semantics

**Decision**: Each per-chunk and combine `generate` is raced against the job's existing
`cancel_token` (same `tokio::select!` as today, sammanfatta.rs:228), with an additional
`is_cancelled()` check between chunks. Any chunk/combine error → `finalize_with_failure(…,
ModelError)`; the sidecar write happens only after the full combined output exists (today's
structure already guarantees no partial file). The existing 180 s reqwest timeout
(client.rs:108) bounds each chunk individually.

**Rationale**: all-or-nothing falls out of the existing pipeline shape; no new failure
variants, no new Swedish error copy (Principle VIII satisfied with existing states).

## D8 — Anonymisera specifics

**Decision**: pii_sweep keeps running on the **combined** output (it already runs on
`response_text` after the model step — the combine happens before that point). The FR-014
multi-chunk disclaimer is a Swedish paragraph prepended to the combined output *before* the
sweep-warning prepend, following the exact pattern of the spec-014 warning paragraph
(sammanfatta.rs:258-266). New user-facing string → humanizer review.

## D9 — Test seam

**Decision**: wiremock already fakes `/api/generate` per test (tests/common/mod.rs,
`run_zone_pipeline_checked`). For multi-chunk tests: mount a responder that returns
sequenced responses (wiremock supports `respond_with` closures / `up_to_n_times` mounts)
and assert request **count** (chunks + combine) and that each request body carries
`options.num_ctx = 8192` and the spec-022 framing. Long-document fixtures are generated
programmatically (txt/md with sentinel sentences at start/middle/end) — no new binary
fixtures needed for the chunking tests; existing per-zone .docx fixtures keep covering the
single-chunk path.

## D10 — What does NOT change

- No new crates (chunking is std-only; wiremock/serde already in tree).
- No new Tauri commands, no new event channels, no settings fields, no SettingsSnapshot change.
- No frontend code changes (D6); Playwright smoke gains one progress-hint assertion using the
  existing mock-bridge emit surface.
- No new outbound traffic; generate still targets the local client base_url only
  (Principle I/III intact — `options` is a request-body addition to the same localhost call).
