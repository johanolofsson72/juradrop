# Feature Specification: Anonymisera Hardening — Deterministic Structured-PII Replacement

**Feature Branch**: `039-anonymisera-hardening`

**Created**: 2026-06-04

**Status**: Draft

**Input**: User description: "Field bug from beta tester Meja (2026-06-04, screenshot IMG_2908): Anonymisera only reliably replaces names — a raw personnummer (19850312-1234), phone numbers, e-mail addresses and street addresses survived into the 'anonymized' output, with the app's own warning banner admitting '2 personnummer, 3 e-postadresser och 3 telefonnummer' remained. Root causes: (1) the anonymisera system prompt never mentions telefonnummer or e-post at all; (2) even prompted categories (addresses) leak because a 4b model is unreliable; (3) the spec-014 sweep DETECTS residue with battle-tested regexes but only warns — it never replaces. Structured PII (personnummer, telefonnummer, e-post) follows fixed patterns and must be replaced deterministically in code; the model should only handle fuzzy PII (names, organizations, free-text addresses)."

## Clarifications

### Session 2026-06-04

- Q: Replace structured PII before or after the model pass? → A: **Before** (pre-LLM scrub of the extracted text): what the model never sees it cannot echo back, replacement indices stay globally consistent across chunks (deterministic counter, fixing the spec-038 cross-chunk inconsistency for these categories), and the spec-014 output sweep remains as the independent final net.
- Q: Placeholder format? → A: The bracketed indexed forms the spec-014 sweep already masks: `[Personnr N]`, `[Telefon N]`, `[E-post N]`. Same value → same index everywhere in the document. Name/org/address placeholders stay on the existing prompt convention ("Person A", "Företag X", "Adress 1") — visible-output convention unchanged for the model-handled categories.
- Q: Over-redaction tolerance (false positives — e.g. organisationsnummer match the personnummer shape)? → A: Accept over-redaction; for an anonymization tool, replacing a non-personal number is the safe failure direction, and organisationsnummer arguably *should* be anonymized (the prompt already replaces company names). No Luhn validation — shape-based, consistent with the spec-014 decision.
- Q: Does the scrub run for other zones? → A: No — Anonymisera only. Other zones must keep their input byte-identical (a summary that says "[Telefon 1]" instead of the actual number would be wrong).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Structured PII can never survive anonymization (Priority: P1)

A law student drops a stämningsansökan containing personnummer, phone numbers and e-mail addresses on Anonymisera. Today the model is *asked* to handle personnummer (and isn't even asked about phones/e-mail) and randomly leaks them. After this feature, every string matching the personnummer/telefon/e-post patterns is replaced in code, deterministically, before the model is involved — the output cannot contain them regardless of model quality or tier.

**Why this priority**: This is the field bug, and it is a privacy failure in the one zone whose whole job is privacy. A leaked personnummer in a document the student then shares is the worst outcome this app can produce.

**Independent Test**: Drop a document with known personnummer/phone/e-mail strings on Anonymisera (mock model echoing its input); verify the output contains the bracketed placeholders and zero raw matches, and the spec-014 warning banner is absent.

**Acceptance Scenarios**:

1. **Given** a document containing `19850312-1234`, `070-123 45 67` and `david.dahl@dahl.exempel.se`, **When** dropped on Anonymisera, **Then** the output contains `[Personnr 1]`, `[Telefon 1]`, `[E-post 1]` in their places and none of the raw values.
2. **Given** the same personnummer appearing three times in the document, **When** anonymized, **Then** all three occurrences carry the SAME placeholder index (`[Personnr 1]`), and a second, different personnummer gets `[Personnr 2]`.
3. **Given** a document whose structured PII was fully scrubbed, **When** the model output comes back without fabricated PII, **Then** no "Automatisk kontroll hittade…" warning appears (the sweep finds nothing).
4. **Given** a long multi-chunk document with the same phone number in chunk 1 and chunk 3, **When** anonymized, **Then** both occurrences carry the same `[Telefon N]` index (global numbering across chunks — deterministic, unlike the model's per-chunk name placeholders).

---

### User Story 2 - The model is told about all PII categories and the pre-inserted placeholders (Priority: P2)

The anonymisera system prompt must instruct the model about ALL its categories — including the two it was never told about (telefonnummer, e-post, now pre-replaced) — and must tell it that bracketed placeholders are already-anonymized material to preserve verbatim.

**Why this priority**: Without the placeholder-preservation instruction, a small model may "helpfully" rewrite `[Personnr 1]` into something else; without mentioning the scrubbed categories, it may try to re-redact and mangle surrounding text.

**Independent Test**: Unit-assert the updated prompt names every category and the preserve-placeholders instruction; pipeline-assert (mock echo) that placeholders pass through unharmed.

**Acceptance Scenarios**:

1. **Given** the updated system prompt, **When** inspected, **Then** it instructs: names → "Person A/B", organizations → "Företag X/Y", addresses → "Adress 1/2", and states that bracketed placeholders (`[Personnr N]`, `[Telefon N]`, `[E-post N]`) are already anonymized and must be kept exactly as written.
2. **Given** a scrubbed document, **When** the model transforms it, **Then** placeholders appear unmodified in the output (pipeline test with echoing mock).

---

### User Story 3 - The safety net stays honest (Priority: P3)

The spec-014 output sweep keeps running unchanged on the final combined output: if the model *fabricates* a new personnummer/phone/e-mail (hallucination) or a pattern slips past the scrub, the user still gets the warning banner.

**Why this priority**: Defense in depth — the scrub makes leakage structurally impossible for matched patterns; the sweep covers the unmatchable remainder.

**Independent Test**: Mock model output containing a fabricated phone number → warning banner present, names the category.

**Acceptance Scenarios**:

1. **Given** a fully scrubbed input but a model response that introduces `08-555 12 34`, **When** the sidecar is produced, **Then** the warning banner reports 1 telefonnummer.
2. **Given** a clean run, **Then** no warning banner (the placeholders themselves never count as residue — already guaranteed by the spec-014 masking).

---

### Edge Cases

- The same value in different formats (`19850312-1234` vs `850312-1234`) — distinct matches get distinct indices (no format normalization in v1; shape-based only, documented limitation).
- A personnummer-shaped organisationsnummer (`556677-8899`) — replaced (over-redaction accepted per clarification).
- Phone-number-shaped strings inside case references — replaced if they match the spec-014 phone shape; accepted over-redaction, same trade-off the sweep already made.
- PII straddling a chunk boundary cannot occur for scrub categories: the scrub runs on the WHOLE extracted text before chunking (spec 038 order: extract → scrub → chunk).
- Placeholders must survive chunking: `[Personnr 1]` must never be split mid-placeholder by a chunk cut (boundary cascade cuts at paragraph/sentence/whitespace — a bracketed token is never split by those; the pathological char-fallback could split one, accepted as a vanishing edge case in whitespace-free 24k-char runs).
- Email with Swedish chars (`åsa@exempel.se`) — the spec-014 email regex's `\w` does not match å/ä/ö; partial match replaces the ASCII tail. Accepted v1 limitation (sweep has the same blind spot today); documented.
- Empty document after scrub cannot occur (scrub only substitutes, never deletes).
- The scrub counter and value→index mapping live in memory for the duration of one run and are never persisted or logged (Principle I).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For the Anonymisera zone only, the system MUST replace every match of the established personnummer, telefonnummer and e-post patterns (the spec-014 shapes) in the extracted document text BEFORE any model pass, with bracketed indexed placeholders `[Personnr N]`, `[Telefon N]`, `[E-post N]`.
- **FR-002**: Identical matched values MUST receive the same index everywhere in the document; distinct values receive sequential indices per category, in first-occurrence order.
- **FR-003**: The scrub MUST run on the whole extracted text before chunking (spec 038), so indices are globally consistent across chunks.
- **FR-004**: The Anonymisera system prompt MUST be extended to (a) state that bracketed placeholders are already-anonymized material to preserve verbatim, and (b) keep instructing the model on names/organizations/addresses per the existing conventions.
- **FR-005**: Every other zone MUST receive byte-identical input (no scrub outside Anonymisera).
- **FR-006**: The spec-014 output sweep MUST keep running unchanged on the final (combined) output as the independent net for fabricated or unmatched PII.
- **FR-007**: The value→index mapping MUST exist only in memory for the duration of the run — never persisted, never logged (Principle I).
- **FR-008**: Scrub replacement MUST be UTF-8-safe (Swedish characters adjacent to matches must never be corrupted).

### Key Entities

- **Scrub result**: The scrubbed text + per-category replacement counts (for tests/diagnostics tags only — counts are content-free).
- **Placeholder registry**: In-memory value→(category, index) map for one run; first-occurrence-ordered.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For any input document, the Anonymisera output contains ZERO matches of the personnummer/telefon/e-post patterns that were present in the input (deterministic — holds on every tier, every run).
- **SC-002**: Repeated values map to one stable placeholder index per document, including across chunks of a long document.
- **SC-003**: A model-fabricated PII string in the output still triggers the spec-014 warning banner.
- **SC-004**: All non-Anonymisera zones produce byte-identical results to pre-039 for the same input and mock responses.
- **SC-005**: The full existing test suite stays green (no regressions in the 15 chunked-pipeline tests, incl. the multi-chunk anonymisera test).

## Assumptions

- The spec-014 regex shapes are the single source of truth for "structured PII" — the scrub reuses them (literally the same compiled patterns) so detect-and-replace can never disagree with detect-and-warn.
- Free-text addresses remain the model's job: the existing prompt instruction ("Adress 1, Adress 2") plus the zone disclaimer cover them; no deterministic pattern exists for Swedish addresses worth the false-positive rate.
- The existing `[Person...]`-masking in the sweep already prevents the new placeholders from counting as residue — no sweep change needed.
- No new user-facing Swedish copy: placeholders follow the established spec-014 format; the prompt is model-facing. (Humanizer gate not triggered; no UI change → frontend-design gate not triggered.)
- Track: light (no new state machine, no new concurrency — a pure text transformation inserted at one point in the existing pipeline). `/tla` expected to be skipped at the triviality gate.
