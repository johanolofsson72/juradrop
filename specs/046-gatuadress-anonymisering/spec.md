# Feature Specification: Gatuadress Anonymisering — Deterministic Street-Address Scrub (+ phone-tail fix)

**Feature Branch**: `046-gatuadress-anonymisering`

**Created**: 2026-06-08

**Status**: Draft

**Input**: User description: "Live-test finding (Johan, 2026-06-08): dropped postnummer-adresser-kantfall.docx on the real gemma3:4b. The spec-045 postnummer scrub worked perfectly, but every STREET ADDRESS stayed in cleartext in the output (Storgatan 5, Lillgatan 12B, Vasagatan 1, Hamngatan 8). The anonymisera prompt instructs the model to replace addresses with 'Adress 1' but gemma3:4b ignored it — the same 4b-unreliability lesson as specs 039/044. Worse, the spec-045 address anchor cannot fire because the postnummer (the planned signal) was successfully scrubbed to [Postnr N], so the leaked street address gets no warning either. Decision (Johan): handle street addresses the same way as PII/postnummer — a deterministic RE_ADRESS for the Swedish street form (street name + type suffix -gatan/-vägen/-gränd/-stigen/-allén/-torget + house number with optional letter) → [Adress N], scrubbed BEFORE the model. House number REQUIRED (a bare street word is too ambiguous), capitalization required (lowers false positives), ambiguous bare suffixes (plan/led/ring) excluded ('plan 3' = floor 3). Also fold in a pre-existing latent bug surfaced by the same test: RE_PHONE has only three digit groups after the area code, so '070-123 45 67' loses its last pair ('[Telefon 1] 67'); extend it to capture the full number."

## Clarifications

### Session 2026-06-08

- Q: What anchors a street-address match — the type suffix, and which ones? → A: A capitalized street word ENDING in an unambiguous Swedish street-type suffix, immediately followed by a house number. Included suffixes (longest-first within each family): `gatan/gata`, `vägen/väg`, `gränden/gränd`, `stigen/stig`, `torget/torg`, `allén/allé`, `backen/backe`, `liden/lid`, `kajen/kaj`, `stranden/strand`, `brinken/brink`, `hamnen/hamn`, `esplanaden/esplanad`, `promenaden/promenad`, `gången/gång`. EXCLUDED as too ambiguous (collide with floor/level/other senses): `plan` (våning), `led` (motorled/riktning), `ring`, `park`, `plats` — those stay the model's job. Over-redaction within the included set is accepted in the safe direction (same stance as 014/039/045).
- Q: Is the house number required? → A: Yes — the match MUST end with whitespace + a house number (1–3 digits, optional single trailing letter, optional space before the letter: `12B` / `12 B`). A bare "Storgatan" without a number is NOT redacted (it is too often the street-as-topic, not an address — "Storgatan är avstängd").
- Q: Capitalization? → A: The street word MUST start with a Swedish uppercase letter (`A–Z` + `Å/Ä/Ö`). Swedish street names are proper nouns; requiring the capital removes the bulk of false positives (a lowercase "…vägen 3" mid-sentence is far more likely "vägen 3 meter bort").
- Q: Placeholder format and where does the scrub run? → A: `[Adress N]`, mirroring the bracketed indexed convention; same value → same index, first-occurrence order; Anonymisera ONLY, whole-text before chunking; added to the sweep's `RE_PLACEHOLDER` mask. Note: this DISPLACES the model's "Adress 1/2" convention for matched streets — the deterministic `[Adress N]` is now authoritative and the prompt's free-text address instruction stays only as the fallback for forms the regex cannot catch.
- Q: How does this interact with the spec-045 postnummer scrub on the same line? → A: Both run in the same multi-category leftmost-longest sweep. `Storgatan 5, 114 35 Stockholm` → `[Adress 1], [Postnr 1] Stockholm`. The street word and the postnummer are non-overlapping spans (the address match ends at the house number, before the comma); the city name is intentionally left (low-risk, no reliable pattern).
- Q: The phone-tail fix scope? → A: Extend `RE_PHONE` so a Swedish number formatted with a third trailing group (`0NN-NNN NN NN`, e.g. `070-123 45 67`) is captured in full instead of leaving a 2-digit tail. The existing two-group forms (`08-555 12 34`) must still match unchanged. Detection-and-replacement stay in lockstep (single pattern source).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Swedish street addresses can no longer survive anonymization (Priority: P1)

A law student drops a stämningsansökan with party addresses (`Storgatan 5`, `Lillgatan 12B`, …) on Anonymisera. Today gemma3:4b leaves them in cleartext. After this feature, every street matching the deterministic Swedish street form is replaced in code, before the model — the output cannot contain it regardless of model quality or tier.

**Why this priority**: This is the live-test field finding. A street + (now-scrubbed) postnummer re-identifies a household; leaving the street naked defeats the address half of the zone's job.

**Independent Test**: Drop the spec-045 edge-case doc (echo-mock); every street word + number becomes `[Adress N]`, zero raw street strings remain, and the same street repeated keeps one index.

**Acceptance Scenarios**:

1. **Given** `Storgatan 5, 114 35 Stockholm`, **When** anonymized, **Then** the output reads `[Adress 1], [Postnr 1] Stockholm` (street and postnummer both replaced, city left).
2. **Given** `Lillgatan 12B`, **When** anonymized, **Then** `[Adress N]` (house number with a trailing letter is captured in full).
3. **Given** the same street address appearing twice, **When** anonymized, **Then** both carry the same `[Adress N]` index; a distinct street gets the next index.
4. **Given** a long multi-chunk document with the same street in chunk 1 and chunk 3, **When** anonymized, **Then** both carry the same `[Adress N]` index (whole-text scrub before chunking).

---

### User Story 2 - The scrub does NOT redact non-address words (Priority: P1)

The street pattern must fire only on a capitalized street-suffix word followed by a house number — never on a street mentioned without a number, a lowercase occurrence, or an excluded ambiguous suffix.

**Why this priority**: A scrub that redacts `plan 3` (floor 3), `Storgatan är avstängd` (no number), or `vägen 3 meter` corrupts legal text. Precision is the load-bearing constraint.

**Independent Test**: Scrub text with `plan 3`, `Storgatan är avstängd`, `vägen framåt`, `motorled 4` → all byte-identical (zero `[Adress]`).

**Acceptance Scenarios**:

1. **Given** `plan 3` or `Plan 3` (floor), **When** scrubbed, **Then** unchanged (excluded suffix).
2. **Given** `Storgatan är avstängd` (street word, no house number), **When** scrubbed, **Then** unchanged.
3. **Given** `vägen 3 meter bort` (lowercase, not a proper street name), **When** scrubbed, **Then** unchanged (capitalization required).
4. **Given** `Storgatan 5`, **When** scrubbed, **Then** replaced — proving the capital + suffix + number triad is the discriminator.

---

### User Story 3 - The model is told to preserve [Adress N] (Priority: P2)

The anonymisera system prompt names `[Adress N]` in its preserve-verbatim list, and keeps the free-text "Adress 1/2" instruction only as the fallback for street forms the regex cannot catch.

**Why this priority**: Without the preserve instruction a small model may rewrite `[Adress 1]`; without the fallback instruction, odd street forms (no suffix, PO boxes) would have no handler at all.

**Independent Test**: Assert the prompt lists `[Adress N]` among the bracketed placeholders; echo-mock shows `[Adress 1]` passes through.

**Acceptance Scenarios**:

1. **Given** the updated prompt, **When** inspected, **Then** its placeholder-preservation list names `[Adress N]` alongside `[Personnr/Telefon/Postnr/E-post N]`, and it still instructs free-text address replacement as a fallback.

---

### User Story 4 - A phone number with a third trailing group is captured in full (Priority: P2)

`RE_PHONE` must capture `070-123 45 67` entirely, not leave a `67` tail.

**Why this priority**: The live test showed `[Telefon 1] 67` — a partial scrub that leaks two digits and looks broken. Pre-existing since 039; fixed here because the same test surfaced it.

**Independent Test**: Scrub `070-123 45 67` → `[Telefon 1]` with no trailing digits; `08-555 12 34` still → `[Telefon 1]` (two-group form unchanged).

**Acceptance Scenarios**:

1. **Given** `070-123 45 67`, **When** scrubbed, **Then** `[Telefon 1]` with no residual `67`.
2. **Given** `08-555 12 34` (two trailing groups), **When** scrubbed, **Then** `[Telefon 1]` unchanged from pre-046 behavior.
3. **Given** `+46 70 123 45 67`, **When** scrubbed, **Then** captured in full (the +46 branch already handles ≥4 groups; no regression).

---

### Edge Cases

- A street with an apartment/letter form (`12 B`, `12B`) — captured (optional space + single letter).
- A street whose name does not end in a known suffix (`Polhem 3`, `Box 1234`) — NOT caught by the regex; stays the model's job + the static disclaimer (documented limitation, same as unspaced postnummer in 045).
- City name after the postnummer (`Stockholm`) — intentionally left; no reliable pattern, low re-identification value once street + postnummer are gone.
- The street match and the postnummer match on one line are non-overlapping (street ends at the house number, before the comma); the multi-category leftmost-longest sweep places both.
- A suffix that is also a common word followed by a number (`Plan 3` = floor) — excluded suffix, not matched.
- The `[Adress N]` registry lives in memory for one run; never persisted or logged (Principle I).
- Phone fix must not over-extend across adjacent numbers — the optional third group is bounded and word-boundaried.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For the Anonymisera zone only, the system MUST replace every match of the deterministic Swedish street-address pattern in the extracted text BEFORE any model pass, with `[Adress N]`. The pattern is: word boundary, a Swedish uppercase initial (`A–ZÅÄÖ`), zero or more letters, an included street-type suffix, whitespace, a house number (1–3 digits, optional single space, optional single trailing letter), word boundary.
- **FR-002**: Included suffixes: `gatan/gata`, `vägen/väg`, `gränden/gränd`, `stigen/stig`, `torget/torg`, `allén/allé`, `backen/backe`, `liden/lid`, `kajen/kaj`, `stranden/strand`, `brinken/brink`, `hamnen/hamn`, `esplanaden/esplanad`, `promenaden/promenad`, `gången/gång`. Excluded (too ambiguous): `plan`, `led`, `ring`, `park`, `plats`.
- **FR-003**: The match MUST require the trailing house number; a street word without a number MUST NOT be redacted.
- **FR-004**: Identical matched street strings MUST receive the same `[Adress N]` index everywhere; distinct streets get sequential indices in first-occurrence order.
- **FR-005**: The street scrub MUST run on the whole extracted text before chunking, so indices are globally consistent across chunks.
- **FR-006**: The street pattern MUST be defined once and consumed by both the scrub (replace) and the sweep (so a fabricated/echoed street is detectable) — the 014/039/045 shared-pattern discipline. The sweep MUST count residual street addresses and include them in the warning.
- **FR-007**: The Anonymisera system prompt MUST name `[Adress N]` in its preserve-verbatim list and keep the free-text "Adress 1/2" instruction as the fallback for streets the regex cannot catch.
- **FR-008**: `[Adress N]` MUST be added to the sweep's placeholder mask so it never counts as residue.
- **FR-009**: `RE_PHONE` MUST be extended so a Swedish national number with a third trailing digit group (`0NN-NNN NN NN`) is captured in full; existing two-group forms and the `+46` form MUST still match unchanged (single pattern source — scrub and sweep stay in lockstep).
- **FR-010**: Every other zone MUST receive byte-identical input (no street/phone-change scrub outside Anonymisera; the phone pattern itself is shared but only the Anonymisera scrub rewrites text).
- **FR-011**: The street value→index mapping MUST exist only in memory for the run — never persisted, never logged (Principle I).
- **FR-012**: Street scrub replacement MUST be UTF-8-safe (Swedish characters adjacent to a match must never be corrupted).
- **FR-013**: Any new user-facing Swedish warning copy (residual-street wording) MUST be humanizer-reviewed.

### Key Entities

- **Street-address match**: A capitalized Swedish street word with a known suffix + house number; one scrub-registry entry, one potential sweep count.
- **Scrub registry (extended)**: Gains an `Adress` category; first-occurrence-ordered, stack-bound for one run.
- **Sweep findings (extended)**: Gains a street-address count feeding the warning.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For the spec-045 edge-case document, the Anonymisera output contains ZERO of the four raw street strings (`Storgatan 5`, `Lillgatan 12B`, `Vasagatan 1`, `Hamngatan 8`) — deterministic on every tier.
- **SC-002**: `plan 3`, `Plan 3`, `Storgatan är avstängd`, `vägen 3 meter`, and `motorled 4` are byte-identical after scrub (zero false-positive street redactions).
- **SC-003**: Repeated street addresses map to one stable `[Adress N]` index per document, including across chunks.
- **SC-004**: `070-123 45 67` scrubs to `[Telefon 1]` with no residual digits; `08-555 12 34` and `+46 70 123 45 67` are unaffected.
- **SC-005**: All non-Anonymisera zones produce byte-identical results to pre-046 for the same input and mock responses.
- **SC-006**: The full existing test suite stays green (no regressions in scrub, sweep, chunked-pipeline, or the spec-045 postnummer tests).

## Assumptions

- The capital + known-suffix + house-number triad is distinctive enough in Swedish legal text that false positives are rare and acceptable in the safe over-redaction direction (the 014/039/045 trade-off).
- Streets without a known suffix (`Polhem 3`, `Box 1234`) and city names remain the model's job + the static disclaimer; no deterministic pattern for them is worth the false-positive rate.
- The single-pattern-source discipline (one `RE_ADRESS`, one `RE_PHONE`, each consumed by scrub + sweep) is mandatory so detect-and-replace agrees with detect-and-warn by construction.
- The new residual-street warning copy is user-facing Swedish → humanizer gate applies. No UI layout change → frontend-design gate not triggered.
- Track: light — two more deterministic regex categories/extensions in the existing pure text transformation; no new state machine, no concurrency. `/tla` expected to be skipped at the triviality gate, as in 039/044/045.
