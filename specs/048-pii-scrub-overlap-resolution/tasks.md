# Tasks — Spec 048 PII-scrub overlap resolution

Dependency-ordered. Privacy core → hardened tier.

- [x] **T001/T002** Rewrite the overlap-resolution block of `scrub_structured_pii`.
  Implemented as a **streaming leftmost cursor** (superseded the originally-planned
  batch gap re-scan: the cursor form is correct AND linear-time, and it fixes a
  harder triple-glue fragmentation the batch left behind). Comparator later
  simplified to leftmost-only after the mutation gate proved the length/category
  tiebreak was dead code given the pattern array order.
- [x] **T003** Updated the limitation test → `postnummer_adjacent_phone_is_scrubbed_by_gap_rescan`:
  asserts `[Postnr 1] [Telefon 1]` + clean sweep.
- [x] **T004** Functional unit tests: canonical glued case, postnummer-glued-to-
  personnummer, three-way glued chain, first-pass-identity on a non-glued document.
- [x] **T005** Destructive suite: boundary (single-char gap, string ends), UTF-8
  adjacency across a gap, idempotence on new output, same-value-same-index across
  a gap-resolved span.
- [x] **T006** Re-enabled `scrub_output_leaves_no_sweepable_residue` with a
  **bare-space-joined** generator (prose-only workaround retired); +2 personnummer
  fragment forms (adversarial-review F2).
- [x] **T007** Stress test: 1000× glued postnummer+phone → terminates, all replaced,
  clean.
- [x] **T008** Gates GREEN: 562 cargo + 48 scrub (twice) + lint + tsc; clippy
  `-D warnings` + fmt clean.
- [/] **T009** Hardened mutation gate: cargo-mutants (native aarch64) — first run
  24/30 (80%); all 6 misses were dead comparator clauses + 1 equivalent while-bound
  + 1 timeout. Fixed: comparator simplified (dead code removed), `while`→`loop`
  (equivalent removed), F3 debug_assert (kills the timeout). Authoritative re-run
  on final code in progress.
- [x] **T010** Adversarial review (`security-scanner`): 0 CRIT/HIGH/MED, 3 LOW —
  F1 no exploit; F3 zero-length loop guard (FIXED); F2 PBT corpus (FIXED). Surfaced
  via AskUserQuestion → both Fix now.
- [ ] **T011** `/tla` triviality gate (pure deterministic transform, 0 new state —
  skip per 045/046/047 precedent).
- [ ] **T012** Tick register row 048, commit, push, status summary.
