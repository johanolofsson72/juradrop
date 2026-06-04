# Contracts: chunking module + generate-request change (038)

## 1. `zones::chunking` module contract (pure, std-only)

```rust
pub const CHUNK_CHAR_TARGET: usize = 24_000;
pub const MAX_CHUNKS: usize = 12;

pub enum CombineStrategy { Reduce, Concat, Aggregate, CondenseThenStructure, Exempt }

pub struct ChunkPlan {
    pub chunks: Vec<String>,   // 1..=MAX_CHUNKS, each <= CHUNK_CHAR_TARGET chars, none blank
    pub was_capped: bool,      // input exceeded MAX_CHUNKS * CHUNK_CHAR_TARGET
}

/// Split `text` (already blank-line-collapsed by extraction) into a plan.
/// Boundary cascade: paragraph ("\n\n") -> sentence (Swedish-abbreviation guard:
/// t.ex., bl.a., m.m., dvs., osv., kap., s.k., p.g.a., m.fl., jfr, prop., bet.)
/// -> whitespace -> char boundary (UTF-8-safe last resort).
/// Whitespace-only slices are dropped. Order preserved.
pub fn split_into_chunks(text: &str) -> ChunkPlan;

/// Deterministic in-order join for Concat zones ("\n\n" separator).
pub fn merge_concat(parts: &[String]) -> String;

/// Deterministic structural merge for Aggregate zones (per-zone rules:
/// kontakter heading-grouped bullet dedup; kallor/identifiera strip-dedup-renumber;
/// forklara term-key dedup). Exact-trim matching only.
pub fn merge_aggregate(zone: ZoneId, parts: &[String]) -> String;
```

**Guarantees (unit-test enforced):**
- G1 `split("")`/whitespace-only → never called (extraction rejects EmptyText first); defensive: returns 0-chunk plan treated as EmptyText upstream
- G2 text ≤ CHUNK_CHAR_TARGET → exactly 1 chunk, content identical to input (single-pass path)
- G3 joins of `chunks` reproduce the processed prefix (no loss, no reorder, no mid-word cuts except the pathological no-whitespace fallback)
- G4 `chunks.len() <= MAX_CHUNKS`; `was_capped` true iff prefix < full text
- G5 Swedish abbreviations never create sentence boundaries
- G6 multi-byte chars (å/ä/ö/é) never split mid-char
- G7 `merge_aggregate` output contains each distinct (exact-trim) item exactly once

## 2. `ZoneId::combine_strategy()` (zone_id.rs)

Exhaustive 12-arm match. Pinned by test:

| reduce | concat | aggregate | condense_then_structure | exempt |
|---|---|---|---|---|
| sammanfatta, punktlista | tillengelska, tillsvenska, forenkla, anonymisera | kontakter, kallor, identifiera, forklara | strukturera | generera |

## 3. Ollama generate request (sidecar/client.rs) — body change

Before:
```json
{ "model": "gemma3:4b", "prompt": "…", "stream": false }
```

After (every generate call — single-pass, chunk pass, combine pass, condense pass):
```json
{ "model": "gemma3:4b", "prompt": "…", "stream": false,
  "options": { "num_ctx": 8192 } }
```

Wiremock contract test: every `/api/generate` request body deserializes with
`options.num_ctx == 8192`. No other Ollama API change; same localhost base_url.

## 4. Zone event surface (UNCHANGED shape)

`ZoneSnapshot { state, disabled, failure, job_id, progress_hint }` — multi-chunk runs emit
*more* Processing snapshots (one per part + one for combine) on the existing
`juradrop://zone/<slug>` channel, with progress_hint values:
`"Bearbetar del {i} av {n}…"` then `"Sammanställer…"`. Single-chunk runs: identical
emissions to pre-038. TS `ZoneSnapshot` type untouched.

## 5. Prompt framing (spec 022 — UNCHANGED mechanics, new call sites)

Every chunk pass and every model combine/condense pass routes through
`prompts::frame_prompt(zone, instruction, content)` so document-derived content always sits
inside DOKUMENT markers under the injection guard (FR-007). Generera keeps its
INSTRUKTIONER framing and is never chunked.
