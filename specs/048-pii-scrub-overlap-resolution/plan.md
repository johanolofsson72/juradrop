# Plan — Spec 048 PII-scrub overlap resolution

## Approach

Replace the single-pass leftmost-longest sweep in `scrub_structured_pii`
(`src-tauri/src/zones/pii_scrub.rs`) with an iterative **gap re-scan**:

1. Maintain `kept: Vec<(Range, &str, Category)>`, sorted by start, non-overlapping.
2. Loop:
   a. Compute the uncovered gaps from `kept` (and full `text.len()`).
   b. For each gap, run all six shared patterns on the gap **slice** and collect
      candidates at their absolute byte offsets.
   c. If no candidates → break (stable).
   d. Leftmost-longest among this pass's candidates (start asc, len desc, category
      asc), append winners to `kept`; if none added → break.
   e. Re-sort `kept` by start.
3. Build the per-category first-occurrence registries from `kept` (start order).
4. Back-to-front byte-range splice, identical to today.

**First pass = whole text = pre-048 behaviour byte-for-byte** (the gap on the first
iteration is `[0, text.len())`). Later passes only fill previously-uncovered ranges,
so the change is a strict superset — backward compatible (FR-002).

### Why slices are safe (clarify Q2/Q3)

All six patterns (`RE_EMAIL`, `RE_PHONE`, `RE_PERSONNUMMER`, `RE_POSTNUMMER`,
`RE_ADRESS_FULL`, `RE_ADRESS`) are `\b`-anchored at both ends, and every kept span
ends/begins on its own match's `\b` boundary. So a gap slice begins and ends on a
non-word boundary → a match found in the slice is a valid match at the same absolute
position in the full text. No spurious boundary matches; no kept span re-discovered.

### Termination (clarify Q4)

Each pass either covers ≥1 more byte (total uncovered length strictly decreases,
bounded by `text.len()`) or finds nothing and breaks. Loop terminates; in practice
1–2 passes.

## Files

- `src-tauri/src/zones/pii_scrub.rs` — rewrite the overlap-resolution block; add a
  private `uncovered_gaps` helper; add unit + property tests.
- `specs/SCENARIOS.md` — add scrub gap-resolution SC-ids (Anonymisera feature).

## Verification

- `cargo test` (lib + integration) green; clippy `-D warnings`, `cargo fmt --check`.
- Hardened: `cargo-mutants` on `pii_scrub.rs` (native aarch64) ≥ 80% kill; expanded
  destructive + stress; `security-scanner` adversarial review.
- `/tla` triviality gate (pure deterministic transform, no new state machine —
  evaluate, expect skip like 045/046/047; `/allium:distill` drift check via `/tla`).
