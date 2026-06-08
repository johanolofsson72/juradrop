# Feature Specification: Postnummer Anonymisering — Deterministic Postcode Scrub + Address Anchor

**Feature Branch**: `045-postnummer-anonymisering`

**Created**: 2026-06-08

**Status**: Draft

**Input**: User description: "Field finding from beta tester Meja (2026-06-08): she asked whether anonymization should also cover addresses and postcodes. Investigation of the codebase showed: street addresses ARE already in the anonymisera system prompt ('Ersätt varje adress med Adress 1, Adress 2') but handled ONLY by the fuzzy 4b model with no deterministic scrub and no residue safety net; Swedish postnummer are not covered ANYWHERE — not in the prompt, not in pii_scrub, not in pii_sweep. Decision (Johan): (1) add postnummer to BOTH layers per the spec-014/039 shared-pattern discipline — deterministic scrub of the canonical 'NNN NN' spaced form to [Postnr N] before the model AND the pii_sweep residue net; (2) use a surviving postnummer in the model output as an address-line ANCHOR in the sweep warning so a leaked street address gets flagged. The scrub must be precise — only the canonical spaced grouping (three digits, single space, two digits) so it does not corrupt money amounts, case numbers, dates or other 5-digit tokens; unspaced bare 5-digit strings stay the model's job. Same field-bug-from-Meja lineage as specs 038/039/040/041/042."

## Clarifications

### Session 2026-06-08

- Q: Which postnummer form does the deterministic scrub match? → A: **Only the canonical spaced grouping `NNN NN`** (three digits, single ASCII space, two digits), word-boundaried. This grouping is distinctive in Swedish text: money amounts group from the right in threes (`11 435` = `NN NNN`), which is the opposite grouping, so the spaced postnummer form rarely collides. Unspaced `NNNNN` is deliberately NOT scrubbed — a bare 5-digit run is indistinguishable from an amount/reference number and scrubbing it would corrupt the document; those stay the model's job plus the static disclaimer (same "no unreliable pattern" stance the spec-014 design note takes for street addresses).
- Q: Placeholder format? → A: `[Postnr N]`, mirroring the spec-014/039 bracketed indexed convention (`[Personnr N]`, `[Telefon N]`, `[E-post N]`). Same value → same index everywhere in the document, first-occurrence order. Added to the sweep's `RE_PLACEHOLDER` mask so `[Postnr N]` never counts as residue.
- Q: Over-redaction tolerance for the spaced form (false positives — e.g. an amount that happens to be grouped `NNN NN`)? → A: Accept over-redaction, consistent with the spec-014/039 decision. For an anonymization tool, replacing a non-personal number is the safe failure direction. The spaced-grouping constraint already makes false positives rare; no postnummer range validation (no `1xx xx–9xx xx` whitelist) in v1 — shape-based only, same discipline as the personnummer no-Luhn decision.
- Q: How does the address anchor surface? → A: When the sweep finds residual postnummer in the model OUTPUT, the existing Swedish warning paragraph reports them AND frames them as a likely-leaked address line for the student to re-check. Street addresses themselves remain model-only (no reliable regex); the surviving postnummer is the cheapest honest signal that an address line slipped through. No separate UI surface — it extends the existing `warning_paragraph` sentence.
- Q: Does the postnummer scrub run for other zones? → A: No — Anonymisera only, identical to spec 039. Every other zone receives byte-identical input (a summary that reads `[Postnr 1]` instead of the city's postcode would be wrong).
- Q: Must the first digit be constrained (any digit vs `1-9`)? → A: **First digit MUST be `1-9`** (`[1-9]\d{2}<sep>\d{2}`). Real Swedish postnummer span 10000–98499 and never begin with 0, so the `0`-leading band carries zero true postnummer. Excluding it also avoids stealing leading-`0` phone-area fragments (`012 34` matches the spec-014 phone shape) — keeping the two patterns from fighting over the same span and preserving the single-source/agreement property.
- Q: Which separator(s) between the `NNN` and `NN` groups? → A: **A regular ASCII space OR a non-breaking space (U+00A0)** — exactly one separator char, no double/tab forms. `.docx` exported from Word routinely encodes the postnummer separator as NBSP, so an ASCII-space-only pattern would miss the most common real-world document source. Both chars are treated as the canonical spaced grouping; everything else (no separator, double space, tab) stays out of scope (the model's job).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Canonical postnummer can never survive anonymization (Priority: P1)

A law student drops a stämningsansökan whose party block reads `Storgatan 5, 114 35 Stockholm` on Anonymisera. Today the postnummer `114 35` passes straight through — the prompt never mentions it and no regex touches it. After this feature, every canonical spaced postnummer is replaced in code, deterministically, before the model is involved — the output cannot contain it regardless of model quality or tier.

**Why this priority**: This is the field finding, and it is the one zone whose whole job is privacy. A postnummer plus a street name a student then shares re-identifies a household.

**Independent Test**: Drop a document containing `114 35` (mock model echoing its input); verify the output contains `[Postnr 1]`, zero raw `114 35`, and the spec-014 warning banner is absent.

**Acceptance Scenarios**:

1. **Given** a document containing `Storgatan 5, 114 35 Stockholm`, **When** dropped on Anonymisera, **Then** the output contains `[Postnr 1]` in place of `114 35` and none of the raw digits.
2. **Given** the same postnummer appearing three times, **When** anonymized, **Then** all three occurrences carry the SAME index (`[Postnr 1]`), and a second distinct postnummer gets `[Postnr 2]`.
3. **Given** a postnummer alongside a personnummer, telefon and e-post, **When** anonymized, **Then** all four categories are replaced with their respective `[Postnr N]` / `[Personnr N]` / `[Telefon N]` / `[E-post N]` placeholders and none of the raw values remain.
4. **Given** a long multi-chunk document with the same postnummer in chunk 1 and chunk 3, **When** anonymized, **Then** both occurrences carry the same `[Postnr N]` index (global numbering across chunks, because the scrub runs on the whole text before chunking — the spec-038/039 order).

---

### User Story 2 - The scrub does NOT corrupt non-postcode numbers (Priority: P1)

The deterministic scrub must replace only the canonical spaced postnummer grouping and leave money amounts, case numbers, dates and other numeric tokens byte-identical. Over-eager 5-digit matching would mangle a domslut.

**Why this priority**: A scrub that corrupts `15 000 kronor` or `T 4521-25` is worse than the leak it prevents — it silently alters legal content. Precision is the load-bearing constraint of the whole feature.

**Independent Test**: Scrub a document with an amount (`15 000`), a case number (`T 4521-25`), a year range (`2015–2020`) and a bare 5-digit reference (`11435`); assert the output is byte-identical to the input for those tokens (zero postnummer replaced).

**Acceptance Scenarios**:

1. **Given** the amount `15 000 kr` (grouped `NN NNN`), **When** scrubbed, **Then** it is unchanged — the grouping is not the postnummer `NNN NN` shape.
2. **Given** the case number `T 4521-25`, **When** scrubbed, **Then** it is unchanged.
3. **Given** the bare unspaced `11435`, **When** scrubbed, **Then** it is unchanged (unspaced is out of scope — model's job).
4. **Given** the canonical `114 35`, **When** scrubbed, **Then** it IS replaced — proving the spaced-grouping boundary is the discriminator.

---

### User Story 3 - The model is told to preserve [Postnr N] (Priority: P2)

The anonymisera system prompt must name `[Postnr N]` alongside the existing `[Personnr N]` / `[Telefon N]` / `[E-post N]` placeholders so the model preserves it verbatim instead of "helpfully" rewriting it.

**Why this priority**: Without the preserve instruction, a small model may turn `[Postnr 1]` into a plausible-looking postcode, re-leaking the structure the scrub removed.

**Independent Test**: Unit-assert the updated prompt names `[Postnr N]` in its already-anonymized-placeholders list; pipeline-assert (mock echo) that `[Postnr 1]` passes through unharmed.

**Acceptance Scenarios**:

1. **Given** the updated system prompt, **When** inspected, **Then** its placeholder-preservation sentence lists `[Postnr N]` together with the three existing bracketed forms.
2. **Given** a scrubbed document, **When** the model transforms it, **Then** `[Postnr 1]` appears unmodified in the output (pipeline test with echoing mock).

---

### User Story 4 - A leaked address line is flagged via its surviving postnummer (Priority: P2)

The spec-014 sweep keeps running on the final combined output. When it finds a residual postnummer — one the model fabricated, or an unspaced form the scrub deliberately did not touch that the model echoed — the Swedish warning reports it AND frames it as a likely-leaked address line for the student to re-check.

**Why this priority**: Defense in depth for the address category, which has no reliable regex. The surviving postnummer is the cheapest honest anchor that a street address may have slipped through.

**Independent Test**: Mock model output containing `114 35` → warning banner present, counts the postnummer, and the sentence flags it as a possible address.

**Acceptance Scenarios**:

1. **Given** a model response that introduces `114 35`, **When** the sidecar is produced, **Then** the warning banner reports the postnummer and frames it as a possible address line to review.
2. **Given** a clean run (only `[Postnr N]` placeholders, no raw postnummer), **Then** no warning banner — the placeholders never count as residue.
3. **Given** residual postnummer together with a residual telefonnummer, **When** the warning is built, **Then** both categories appear in the Swedish list join, with the postnummer carrying the address framing.

---

### Edge Cases

- The same postnummer in spaced vs unspaced form (`114 35` vs `11435`) — only the spaced form is scrubbed; the unspaced form is left for the model. Distinct handling is documented, not a bug.
- A money amount grouped exactly as `NNN NN` (rare in Swedish, which groups from the right) — replaced (over-redaction accepted per clarification; the spaced postnummer grouping is the discriminator and false positives are accepted in the safe direction).
- Postnummer straddling a chunk boundary cannot occur for the scrub category: the scrub runs on the WHOLE extracted text before chunking (spec 038/039 order: extract → scrub → chunk).
- `[Postnr 1]` must survive chunking: the boundary cascade cuts at paragraph/sentence/whitespace and never splits a bracketed token; the pathological char-fallback edge is accepted as vanishing, identical to the spec-039 placeholder reasoning.
- Postnummer adjacent to a framing marker or punctuation (`114 35,Stockholm` / `…SLUTAR---114 35`) — word boundary + the leftmost-longest sweep handle it, same as the spec-039 markers test.
- The scrub counter and value→index mapping for postnummer live in memory for one run and are never persisted or logged (Principle I).
- A double-spaced or tab-separated form (`114  35`) — NOT matched by the single-space canonical pattern; treated as out of scope (model's job), consistent with the "precise spaced grouping only" decision.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For the Anonymisera zone only, the system MUST replace every match of the canonical spaced Swedish postnummer pattern in the extracted document text BEFORE any model pass, with bracketed indexed placeholders `[Postnr N]`. The pattern is: word boundary, a first digit `1-9`, two more digits, exactly one separator that is either an ASCII space or a non-breaking space (U+00A0), two digits, word boundary (`\b[1-9]\d{2}[\x{00A0} ]\d{2}\b` — the character class is one NBSP escape plus one literal space; written escaped so a literal NBSP cannot be normalized away).
- **FR-002**: Identical matched postnummer values MUST receive the same index everywhere in the document; distinct values receive sequential indices in first-occurrence order, in the same registry style as the existing categories.
- **FR-003**: The postnummer scrub MUST run on the whole extracted text before chunking (spec 038/039), so indices are globally consistent across chunks.
- **FR-004**: The scrub MUST NOT replace unspaced 5-digit runs, money amounts grouped `NN NNN`, dash-bearing case numbers, date forms, leading-`0` spaced 5-digit forms (reserved to the phone pattern), or double-/tab-separated forms — only the canonical spaced grouping with a `1-9` first digit and a single space/NBSP separator. Non-matching numeric tokens MUST be byte-identical in the output.
- **FR-005**: The postnummer pattern MUST be defined ONCE (a single `RE_POSTNUMMER` in `pii_sweep`) and consumed by both the scrub (replace) and the sweep (warn), so detect-and-replace can never disagree with detect-and-warn (the spec-014/039 shared-pattern discipline).
- **FR-006**: The Anonymisera system prompt MUST be extended so its placeholder-preservation instruction lists `[Postnr N]` alongside the existing `[Personnr N]` / `[Telefon N]` / `[E-post N]` bracketed forms.
- **FR-007**: `[Postnr N]` MUST be added to the sweep's placeholder mask so it never counts as residual postnummer.
- **FR-008**: The spec-014 output sweep MUST count residual postnummer and, when any are found, the Swedish warning paragraph MUST report them AND frame them as a likely-leaked address line to re-check.
- **FR-009**: Every other zone MUST receive byte-identical input (no postnummer scrub outside Anonymisera).
- **FR-010**: The postnummer value→index mapping MUST exist only in memory for the duration of the run — never persisted, never logged (Principle I).
- **FR-011**: Postnummer scrub replacement MUST be UTF-8-safe (Swedish characters adjacent to a match must never be corrupted).
- **FR-012**: The new warning copy (the address-anchor framing) MUST be humanizer-reviewed Swedish, consistent with the existing `warning_paragraph` tone.

### Key Entities

- **Postnummer match**: A canonical spaced Swedish postcode (`NNN NN`) in the extracted text; contributes one entry to the scrub registry and, if it survives into output, one count to the sweep findings.
- **Scrub registry (extended)**: The existing in-memory value→(category, index) map gains a Postnr category; first-occurrence-ordered, stack-bound for one run.
- **Sweep findings (extended)**: The existing `PiiFindings` struct gains a postnummer count; drives both the warning presence and the address-anchor framing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For any input document, the Anonymisera output contains ZERO canonical spaced postnummer (`NNN NN`) that were present in the input (deterministic — holds on every tier, every run).
- **SC-002**: For a document containing an amount (`15 000`), a case number (`T 4521-25`), a date/year-range, and a bare unspaced `11435`, the scrubbed output is byte-identical to the input for those tokens (zero false-positive replacements).
- **SC-003**: Repeated postnummer values map to one stable index per document, including across chunks of a long document.
- **SC-004**: A model-fabricated or echoed residual postnummer in the output triggers the spec-014 warning banner with the address-line framing.
- **SC-005**: All non-Anonymisera zones produce byte-identical results to pre-045 for the same input and mock responses.
- **SC-006**: The full existing test suite stays green (no regressions in the chunked-pipeline, scrub, or sweep tests).

## Assumptions

- The `NNN NN` spaced grouping is distinctive enough in Swedish legal text (where amounts group `NN NNN` from the right) that false positives are rare and acceptable in the safe over-redaction direction — the same trade-off specs 014 and 039 already made for their categories.
- Unspaced postnummer and free-text street addresses remain the model's job: no deterministic pattern for them is worth the false-positive rate (the spec-014 design note already says exactly this for addresses). The surviving-postnummer anchor is the honest partial signal for the address category.
- The single-pattern-source discipline (one `RE_POSTNUMMER`, consumed by scrub + sweep) is mandatory so the spec-039 "detect-and-replace agrees with detect-and-warn by construction" property extends to postnummer.
- The new warning copy is user-facing Swedish → the humanizer gate applies. No UI layout change → the frontend-design gate is not triggered (the warning is existing sidecar text, only the sentence content changes).
- Track: light (no new state machine, no new concurrency — one more category in an existing pure text transformation plus one extended warning sentence). `/tla` expected to be skipped at the triviality gate, identical to specs 039 and 044.
