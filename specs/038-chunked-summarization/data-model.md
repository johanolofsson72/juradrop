# Data Model: Chunked Processing for Long Documents (038)

All types live in Rust (src-tauri); nothing crosses the IPC boundary except the existing
`ZoneSnapshot` (whose shape is unchanged — progress rides the existing `progress_hint`).

## CombineStrategy (enum, zones/chunking.rs)

```text
Reduce                  -- Sammanfatta, Punktlista
Concat                  -- TillEngelska, TillSvenska, Forenkla, Anonymisera
Aggregate               -- Kontakter, Kallor, Identifiera, Forklara
CondenseThenStructure   -- Strukturera
Exempt                  -- Generera (input is instructions, never chunked)
```

- Mapping is an exhaustive `match` in `ZoneId::combine_strategy()` (zone_id.rs) — the
  compiler enforces that a future 13th zone declares its strategy (mirrors the
  spec.allium `StrategyMatchesZone` invariant).

## ChunkPlan (struct, zones/chunking.rs)

| Field | Type | Rules |
|---|---|---|
| `chunks` | `Vec<String>` | 1..=12 entries; each ≤ CHUNK_CHAR_TARGET chars (char-counted); never whitespace-only; index order = document order |
| `was_capped` | `bool` | true iff the extracted text exceeded EXTRACT_CEILING_CHARS and chunks cover only the prefix |

Invariants (unit-test enforced, mirroring spec.allium):
- `CeilingBound`: `chunks.len() <= 12`
- `ChunksCoverDocumentInOrder`: joining chunks (with their original separators) reproduces
  the processed prefix of the input text
- `ChunkNeverEmpty`: no chunk is whitespace-only
- Boundary kinds: paragraph (`\n\n`) preferred → sentence (Swedish-abbreviation-guarded) →
  whitespace → char (UTF-8-boundary-safe last resort)

## Constants

| Name | Value | Home | Replaces |
|---|---|---|---|
| `CHUNK_CHAR_TARGET` | 24_000 | zones/chunking.rs | (new — same value as old TRUNCATION_CHAR_LIMIT) |
| `EXTRACT_CEILING_CHARS` | 288_000 | zones/extract.rs | TRUNCATION_CHAR_LIMIT (renamed, 12×) |
| `GENERATE_NUM_CTX` | 8192 | sidecar/client.rs | (new — Ollama left at default before) |

`ExtractedText.was_truncated` keeps its name and writer wiring; its meaning tightens to
"exceeded the 288k extraction memory bound".

**Cap ownership (analyze F1)**: boundary-aware splitting yields chunks *smaller* than
CHUNK_CHAR_TARGET on average, so ≤288k chars can produce >12 raw slices. **Chunking owns the
user-facing cap**: `split_into_chunks` keeps the first 12 chunks and sets
`ChunkPlan.was_capped = true` when it drops a tail. The disclaimer flag passed to the writers
is the OR of both signals: `extracted.was_truncated || plan.was_capped` — the truncation
disclaimer fires iff content was genuinely skipped at either layer (FR-006/FR-013, Principle
VIII). The extraction ceiling (288_000) remains as a coarse memory bound only and never
drives the disclaimer on its own.

## GenerateRequest (modified, sidecar/client.rs)

```text
GenerateRequest {
    model: String,
    prompt: String,
    stream: bool,            -- always false (unchanged)
    options: GenerateOptions -- NEW
}
GenerateOptions { num_ctx: u32 }   -- always GENERATE_NUM_CTX
```

## Run orchestration (no new struct — control flow in DropZone::dispatch)

The spec.allium `ChunkedRun` state machine maps onto the existing dispatch control flow:

| Allium state | Implementation reality |
|---|---|
| planning | `split_into_chunks()` call (synchronous, after extraction) |
| processing_chunks | the sequential per-chunk loop; per-iteration Processing snapshot with `progress_hint = "Bearbetar del {i} av {n}…"`; each generate raced vs cancel_token |
| combining | strategy dispatch: Reduce/CondenseThenStructure → one more framed model call (raced vs cancel); Concat/Aggregate → deterministic in-process merge; snapshot hint "Sammanställer…" |
| writing | existing writer + `write_atomically` tail (unchanged) |
| succeeded / failed | existing Success / finalize_with_failure paths (unchanged) |

Single-chunk plans bypass progress snapshots and combine entirely — byte-identical to the
pre-038 path (SC-004).

## Aggregate merge rules (deterministic, zones/chunking.rs)

| Zone | Per-chunk output shape (per its prompt) | Merge rule |
|---|---|---|
| Kontakter | `## Kategori` headings + `- ` bullets | Group bullets under the union of headings (canonical order: Namn, Adresser, Personnummer, Telefonnummer, E-post); dedup bullets exact-trim |
| Kallor | numbered list | Strip numbering → dedup exact-trim → renumber |
| Identifiera | numbered lines | Strip numbering → dedup exact-trim → renumber |
| Forklara | term–explanation lines | Dedup on the term key (text before first `:`/`–`/`-`); first occurrence wins |

Near-duplicate merging (e.g. differently formatted phone numbers) is out of scope —
documented limitation, exact-match contract per FR-004.

## New user-facing strings (Swedish, humanizer-gated)

| String | Surface |
|---|---|
| `Bearbetar del {i} av {n}…` | progress_hint during multi-chunk loop |
| `Sammanställer…` | progress_hint during combine phase |
| anonymisera multi-chunk disclaimer paragraph (final copy via humanizer) | prepended to combined Anonymisera output when chunk_count > 1 (FR-014) |

No changes to: ZoneSnapshot shape, ZoneFailure variants, TS types, settings, fixtures-drift
key counts (verify in analyze — the disclaimer paragraph is response-body text, not a
ZoneFailure string).
