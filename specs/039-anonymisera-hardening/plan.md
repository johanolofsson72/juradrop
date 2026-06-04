# Implementation Plan: Anonymisera Hardening — Deterministic Structured-PII Replacement

**Branch**: `039-anonymisera-hardening` (register row; work on `main`) | **Date**: 2026-06-04 | **Spec**: [spec.md](spec.md)

## Summary

Structured PII (personnummer/telefon/e-post) is replaced deterministically in code BEFORE
the model sees the document — Anonymisera only, whole-text before chunking, bracketed
indexed placeholders matching the spec-014 sweep mask, same value → same index globally.
The prompt is extended (preserve placeholders verbatim; categories restated), the shared
email pattern is widened for å/ä/ö (FR-009, fixes scrub + sweep together), and the sweep
keeps running on combined output as the independent net.

## Technical Context

**Language**: Rust only (src-tauri) — zero frontend changes, zero TS changes.
**Dependencies**: none new (regex already in tree; patterns reused from pii_sweep).
**Testing**: cargo unit (scrub) + wiremock integration (extended zone_pipeline_chunked
patterns / dedicated anonymisera tests); vitest/Playwright unaffected.
**Performance**: three regex passes over ≤288k chars — negligible vs model latency.
**Privacy**: value→index map in memory only; scrubbed text wrapped in `Redacted`
immediately after scrub (same discipline as extraction).

## Constitution Check — PASS ×9 (pre + post design)

- **I (Privacy)**: STRENGTHENED — structured PII can no longer reach the sidecar for
  matched shapes; registry never persisted/logged (FR-007). No new outbound.
- **VIII (Honest failure)**: sweep net unchanged; over-redaction chosen over under-redaction.
- **V (Swedish UI)**: no new UI copy (placeholders follow the established spec-014 format);
  prompt text is model-facing. Humanizer + frontend-design gates not triggered (no UI code).
- II/III/IV/VI/VII/IX: untouched surfaces.

## Design

### New code

`src-tauri/src/zones/pii_scrub.rs` (new, pure module — sibling of pii_sweep):

```rust
pub struct ScrubOutcome {
    pub text: String,
    pub personnummer: usize,  // distinct values replaced
    pub telefon: usize,
    pub epost: usize,
}
/// Replace every spec-014-shaped personnummer/phone/email with
/// "[Personnr N]" / "[Telefon N]" / "[E-post N]". Same value -> same N
/// (first-occurrence order, per category). Pure, UTF-8-safe.
pub fn scrub_structured_pii(text: &str) -> ScrubOutcome
```

Implementation: per category, `find_iter` over the text collecting (range, value);
replace back-to-front (byte-range splicing preserves UTF-8 and avoids offset drift);
`Vec<(String, usize)>` registry per category for value→index (first-occurrence).
Order of categories: email FIRST, then phone, then personnummer — an email can contain
digits but a phone/personnummer match inside an already-replaced email span is impossible
after replacement; processing the most-specific/longest patterns first avoids overlap
(emails contain dots+digits; phone/pnr never contain '@'). Phone vs personnummer overlap
(e.g. "0701234567" could shape-match both): phone runs before personnummer; spans already
replaced cannot re-match (placeholder text contains no digits).

### Pattern sharing (FR-009 + DetectAndReplaceAgree)

The three regexes move to `pub(crate)` accessors in pii_sweep.rs (single source);
`RE_EMAIL` widened: `[\w.+-]` → `[\wåäöÅÄÖ.+-]` for the local part (and domain labels
keep ASCII — Swedish IDN domains are punycode on the wire; local-part is where names
live). Sweep tests gain an å-email case.

### Dispatch integration (sammanfatta.rs)

After extraction, before `split_into_chunks` (FR-003), zone-gated:

```rust
let extracted_text = if self.id == ZoneId::Anonymisera {
    Redacted::new(pii_scrub::scrub_structured_pii(extracted.raw.as_inner()).text)
} else { extracted.raw  /* moved, byte-identical */ };
```

(Plus content-free diagnostics: nothing — counts not logged; keeping FR-007 simple.)

### Prompt (prompts/anonymisera.rs)

Rewrite ANONYMISERA_SYSTEM_PROMPT: keep Person A/Företag X/Adress 1 conventions and the
same-identity-same-placeholder instruction; REMOVE the personnummer instruction (now
pre-replaced); ADD: bracketed placeholders `[Personnr N]`, `[Telefon N]`, `[E-post N]`
are already anonymized — keep them exactly as written. Model-facing Swedish.

### What does NOT change

Writers, sweep call site (still on combined output), chunking, snapshots, frontend,
fixtures-drift surfaces, settings. Zero new Swedish UI strings.

## Test plan

Unit (pii_scrub.rs): replacement of all three categories + shapes; same-value-same-index;
distinct values sequential; first-occurrence order; å-email full replacement (FR-009);
UTF-8 adjacency (åäö around matches); phone-vs-personnummer overlap precedence; empty/
no-match text identity; idempotence (scrubbing scrubbed text is a no-op).
Sweep: å-email detection test (widened pattern).
Integration (tests/zone_pipeline_anonymisera.rs or chunked file): (a) echo-mock —
input PII → sidecar has placeholders, zero raw values, NO warning banner (SC-001/AS3);
(b) fabricated-PII mock → warning banner (SC-003); (c) multi-chunk same-phone-two-chunks
→ one index (SC-002/FR-003); (d) non-anonymisera zone with PII-laden doc → prompt
contains RAW values (SC-004 byte-identical input proof).

## Execution order

1. pii_sweep.rs: widen RE_EMAIL + expose patterns + å test
2. pii_scrub.rs: module + unit tests
3. prompts/anonymisera.rs: prompt rewrite + pinning test updates
4. dispatch wiring (zone-gated, pre-chunking)
5. integration tests
6. full gates
