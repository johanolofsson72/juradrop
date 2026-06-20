# Spec 048 — PII-scrub overlap resolution (gap re-scan)

**Track:** full **[hardened]** (privacy core — Anonymisera scrub)
**Provenance:** H1 integration-hardening checkpoint, property-based test finding
(2026-06-20, `scrub_output_leaves_no_sweepable_residue` against a bare-space-joined
generator). Disposition: Johan via `AskUserQuestion` → NEW ROW 048, hardened.

## Problem

The Anonymisera input-side scrub (`scrub_structured_pii`, spec 039/045/046/047)
collects PII candidates from the whole document with `find_iter`, then resolves
overlaps **leftmost-longest in a single pass**. A candidate that loses the overlap
contest is discarded outright — its clean, non-overlapping sub-span is never
reconsidered.

This leaves a real (if narrow) gap. When a phone number's digit run is
whitespace-adjacent to an **earlier** postnummer with no separating
non-`[\s-]` character — e.g. `"100 00 01-000 00 00"` — `find_iter`'s greedy phone
match **bridges the boundary**: it starts inside the postnummer's trailing digits
and runs into the phone. That bridging span overlaps the postnummer span, loses the
leftmost-longest contest, and is dropped. The phone's clean sub-span
(`01-000 00 00`) is never re-examined, so the scrub emits `[Postnr 1] 01-000 00 00`
— the phone survives in cleartext going **into** the model.

**No silent leak exists today.** The independent output-side residue sweep
(`scan_residual_pii`, spec 014) nets the surviving phone and fires the Swedish
"double-check" warning, and nothing leaves the Mac (Principle I holds via the
spec-030 CSP wall). But defense-in-depth is not an excuse for an incomplete scrub:
the scrub should be complete on its own, so the model never sees the PII at all.
The H1 PBT generator was deliberately weakened (prose separators only) to dodge
this case — that weakening is itself a finding to retire.

## Goal

Make the leftmost-longest sweep **complete**: after the first pass, re-scan the
byte ranges left uncovered for further matches, and repeat until stable. An
overlapping-but-discarded candidate's clean sub-span inside a gap is then
reconsidered and replaced. Then re-enable the strong PBT property
(bare-space-joined generator) and prove it green.

## Scope

In scope:
- `src-tauri/src/zones/pii_scrub.rs` — `scrub_structured_pii` overlap resolution only.
- Re-enabling `scrub_output_leaves_no_sweepable_residue` with a bare-space generator.
- Updating `postnummer_adjacent_phone_is_netted_by_sweep` to reflect the completed
  scrub (the scrub now catches the phone; the sweep finds nothing).

Out of scope (unchanged by design):
- The regex patterns themselves (`pii_sweep::RE_*`) — shared with the sweep; no edit.
- The output-side sweep `scan_residual_pii` — stays as the independent net.
- Every other zone — receives byte-identical input (Anonymisera only).
- Dispatch, prompt assembly, chunking — untouched.

## Functional requirements

- **FR-001** — The scrub MUST replace every spec-014/045/046/047-shaped candidate
  whose span is reachable, including a candidate that lost the first-pass overlap
  contest but has a clean (non-overlapping) sub-span. After the scrub, the output
  contains **zero** matches of the shared PII patterns for realistic
  prose-or-whitespace-separated input.
- **FR-002** — No regression: for any input the pre-048 scrub already handled
  cleanly, the new resolution MUST produce identical output. Implemented as a
  streaming leftmost cursor (find leftmost match in the remainder → commit →
  advance), which yields the pre-048 result for non-glued input and additionally
  scrubs the previously-leaking glued cases. All existing scrub tests pass
  unchanged except the one that documented the known limitation.
  - Note (mutation-gate finding): the comparator's length/category tiebreak was
    proven to be unreachable dead code given the deliberate pattern array order
    (RE_ADRESS_FULL before RE_ADRESS; category order = array order). It was
    removed; ties are resolved by array order, pinned by the existing tie tests.
    KEEP the array ordering when adding a pattern.
- **FR-003** — First-occurrence indexing (same matched value → same index, dense,
  per category, document order) MUST be preserved across the multi-pass resolution.
- **FR-004** — The resolution MUST terminate on any input (gaps shrink
  monotonically; never panics, never hangs) and never corrupt adjacent UTF-8.
- **FR-005** — Privacy (Principle I): no new persistence, no logging of matched
  values, no new outbound traffic. The registry stays stack-local for one run.
- **FR-006** — The output-side sweep stays unchanged and still runs on the final
  combined output as the independent net for fabricated/unmatched PII.

## Threat model

See `## Threat model` below (hardened requirement) — STRIDE over the scrub seam.

## Clarifications

### Session 2026-06-20

- Q: When the gap re-scan finds a candidate that ITSELF overlaps another
  gap candidate, how is that resolved? → A: Same leftmost-longest rule
  (start asc, len desc, category priority asc), applied per pass; the losers
  create sub-gaps the next pass picks up. One uniform rule, no special case.
- Q: Does the gap re-scan run the regexes on substrings (slices) of the original
  text, or on the full text with kept spans excluded? → A: On slices of the
  **uncovered gaps**. All shared patterns are `\b`-anchored at both ends and every
  kept span ends/begins at a `\b` boundary (its match edge), so a gap slice begins
  and ends on a non-word boundary — a match found in the slice is a valid match at
  the same absolute position in the full text. No spurious boundary matches.
- Q: Could the re-scan re-discover an already-kept span and double-count? → A: No.
  Re-scan operates only on uncovered gaps, which are disjoint from kept spans by
  construction; a kept span's bytes are never inside a gap.
- Q: Termination guarantee? → A: Each pass either covers ≥1 additional byte
  (strictly shrinking the total uncovered length, which is bounded by `text.len()`)
  or finds nothing and breaks. Worst-case passes ≤ `text.len()`; in practice 1–2.
- Q: Does re-enabling the strong PBT generator (bare-space joins) risk flakiness
  from regex catastrophic backtracking on adversarial input? → A: No. The `regex`
  crate is finite-automaton based (no backtracking, linear time); the existing
  `scrub_never_panics` PBT over arbitrary Unicode already exercises that.

## Threat model (STRIDE over the scrub seam)

The scrub is a pure `&str -> ScrubOutcome` function with one trust boundary: the
untrusted extracted document text flows in. No I/O, no network, no persistence.

- **Spoofing** — N/A: no identity/auth surface in a pure transform.
- **Tampering** — A crafted document cannot make the scrub *drop* coverage: the
  multi-pass loop only ever ADDS replacements; a hostile input that previously
  leaked a glued phone is now MORE covered, not less. Mitigation: FR-002 first-pass
  identity + the gap re-scan is monotone.
- **Repudiation** — N/A (no logging, by Principle I design).
- **Information disclosure** — THE risk class. Threat: PII reaching the model in
  cleartext. Pre-048 the glued-phone case leaked into the model (netted only by the
  output sweep). Mitigation: this spec closes the scrub gap; the output sweep
  remains as the second layer; both share one pattern source so they cannot
  disagree. Residual: PII shapes the patterns deliberately don't match (unspaced
  5-digit postnummer, suffix-less streets, names) stay the model's job + the static
  disclaimer + the sweep anchor — unchanged, documented limitation.
- **Denial of service** — Threat: a pathological document making the resolution
  loop run unbounded or the regex hang. Mitigation: finite-automaton regex (linear
  time, no backtracking) + monotone gap shrink (≤ `text.len()` passes) + the
  spec-024 file-size cap upstream. Stress test added (large glued-PII payload).
- **Elevation of privilege** — N/A: no privilege boundary; single-user desktop app.

No threat is left without a mitigation.

## Scenarios

See `specs/SCENARIOS.md` — Anonymisera feature, SC-ids for the scrub gap-resolution
(success / boundary / adversarial), added by this spec.

## Definition of done

- Gap re-scan implemented; `"100 00 01-000 00 00"` scrubs to `[Postnr 1] [Telefon 1]`.
- Strong PBT property re-enabled with a bare-space-joined generator, green.
- All existing Rust tests green (`cargo test`); the one documenting the old
  limitation updated to the completed behaviour.
- clippy `-D warnings`, `cargo fmt --check`, eslint, `tsc --noEmit` clean.
- **Hardened additions:** threat model (above), expanded destructive + stress
  suite, hard mutation-kill gate (`cargo-mutants` on `pii_scrub.rs`, native
  aarch64), adversarial review (`security-scanner` agent). All findings surfaced
  per `validation-followup.md`.
- Register row ticked, committed, pushed.
