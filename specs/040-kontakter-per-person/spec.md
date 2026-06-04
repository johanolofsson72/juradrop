# Feature Specification: Kontakter grouped per person

**Feature Branch**: `040-kontakter-per-person`

**Created**: 2026-06-04

**Status**: Draft

**Input**: User description: "Spec 040 — kontakter-per-person (light track). Field UX feedback from beta tester Meja (2026-06-04): the Kontakter zone groups its output per CATEGORY (## Namn / ## Adresser / …) as the prompt demands; should group per PERSON (## David Dahl → his address/phone/email) so details are linked to their owner. Design for 4b-model mispairing: unattributable details land in an 'Övriga uppgifter' section rather than being force-paired."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Contact details grouped under their owner (Priority: P1)

A law student drops a case document containing several people (parties, counsel, witnesses) onto the Kontakter zone. Today the result file lists all names in one section, all phone numbers in another, all addresses in a third — so the student must manually re-pair which phone belongs to which person, which defeats the zone's purpose ("vem är vem i ett ärende"). After this change, the result groups everything by person: one section per person, with that person's address, phone number, e-mail, and personnummer listed under their name.

**Why this priority**: This is the entire feature — direct field feedback from the first external beta tester. Per-category output makes the zone nearly useless for documents with more than one person.

**Independent Test**: Drop a document mentioning two people with distinct contact details; the result file contains one section per person with that person's details under it, not category sections.

**Acceptance Scenarios**:

1. **Given** a document mentioning "David Dahl, tel 070-123 45 67, david@example.se" and "Eva Ek, Storgatan 1, 211 34 Malmö", **When** it is dropped on Kontakter, **Then** the result contains a "## David Dahl" section listing his phone and e-mail and a "## Eva Ek" section listing her address — and no "## Namn" / "## Adresser" / "## Telefonnummer" category sections.
2. **Given** a person appears in the document with a name only and no other details, **When** processed, **Then** that person still appears as their own section (the name itself is extracted information; it must not be dropped because the person has no further details).
3. **Given** each detail under a person, **When** rendered, **Then** it carries a category label (e.g. "Telefon: 070-123 45 67", "Adress: Storgatan 1, 211 34 Malmö") so the reader knows what kind of detail it is without guessing.

---

### User Story 2 - Unattributable details are never force-paired (Priority: P2)

The document contains an orphan detail — a phone number in a footer, an address with no nearby name. The local model cannot reliably attribute it. The result must place such details in a final "## Övriga uppgifter" section instead of guessing an owner or silently dropping them. A wrong pairing in a legal context is actively harmful (the student may call the wrong party); fabricated attribution is worse than no attribution (Principle VIII — honest output).

**Why this priority**: This is the safety design for the small local model's known mispairing weakness. Without it, the per-person format would invite fabricated pairings.

**Independent Test**: Process a document with an orphan phone number far from any name; the result contains the number under "## Övriga uppgifter" as the last section.

**Acceptance Scenarios**:

1. **Given** a document with a detail that cannot be attributed to a person, **When** processed, **Then** the detail appears under "## Övriga uppgifter" and that section is the LAST section of the result.
2. **Given** a document where every detail is attributable, **When** processed, **Then** no "## Övriga uppgifter" section appears (empty sections are omitted, matching the zone's existing convention).

---

### User Story 3 - Long documents merge per person, not per fragment (Priority: P3)

A long document (multi-part processing, introduced in spec 038) mentions the same person in different parts — David Dahl's phone number on page 2, his e-mail on page 41. The combined result must contain exactly ONE "## David Dahl" section holding both details, with duplicates removed, and "## Övriga uppgifter" still last in the combined output.

**Why this priority**: Long documents are exactly where Kontakter earns its keep, and the multi-part combine step must not undo the per-person grouping the model produced per part.

**Independent Test**: Feed the combine step two part-results that both contain a "## David Dahl" section with overlapping and distinct details; the combined output has one "## David Dahl" section with the union of details, deduplicated, and any "## Övriga uppgifter" content pinned last.

**Acceptance Scenarios**:

1. **Given** part 1 yields "## David Dahl" with a phone and part 3 yields "## David Dahl" with an e-mail, **When** combined, **Then** the result has exactly one "## David Dahl" section containing both details.
2. **Given** the same detail for the same person appears in two parts, **When** combined, **Then** it appears once in the result.
3. **Given** part 1 yields an "## Övriga uppgifter" section and part 2 yields new person sections, **When** combined, **Then** "## Övriga uppgifter" is the final section of the combined result, after every person section.
4. **Given** a person section with a heading but no detail lines in any part, **When** combined, **Then** the person's heading is preserved in the result (a found name is information; the combine step must not discard it).

---

### User Story 4 - Help text describes the new output shape (Priority: P4)

The zone's help text currently tells the user the result lists "namn, adresser, personnummer, telefonnummer och e-post var för sig" (each category separately). After this change that description is wrong. Both places where this help text lives must describe the per-person grouping, in natural Swedish, and stay word-for-word identical to each other (they are mirror copies guarded by an existing drift test).

**Why this priority**: Small but user-facing; stale help text actively misleads after the behavior change.

**Independent Test**: Open the Kontakter zone help; the long description mentions grouping per person, not per category, and matches its mirror copy exactly.

**Acceptance Scenarios**:

1. **Given** the updated app, **When** the user reads Kontakter's long help text, **Then** it describes details grouped under each person and no longer says "var för sig" about categories.
2. **Given** the two mirrored copies of the help text, **When** compared, **Then** they are identical (existing drift guard stays green).

---

### Edge Cases

- A document whose ONLY content is unattributable details (no names at all): the result is a single "## Övriga uppgifter" section.
- A document with no contact information at all: existing zone behavior for empty extraction results applies unchanged (this spec does not alter it).
- The model emits the same person heading with different surrounding whitespace across parts: headings are matched after trimming, so they merge into one section.
- The model emits a person literally named or a heading exactly equal to "Övriga uppgifter": it is treated as the catch-all section and pinned last (exact-heading collision is accepted; a person actually named "Övriga uppgifter" does not exist in practice).
- Name variants across parts ("David Dahl" in part 1, "D. Dahl" in part 3): matched by exact heading text only; variants produce separate sections. This is an accepted model-quality limitation — fuzzy name unification risks merging two genuinely different people, which is worse (documented limitation, not a defect).
- Detail lines that arrive before any heading in a part result (model disobedience): folded into "## Övriga uppgifter" — by definition they have no attributed owner. (Replaces the previous behavior of a heading-less leading section.)
- A combine step where one part is empty or contains only blank lines: contributes nothing; combining proceeds with the remaining parts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Kontakter zone MUST instruct the model to group extracted contact details per person: one second-level heading per person (the person's name as the heading), with that person's details as bullet lines under the heading.
- **FR-002**: Each detail bullet MUST carry a Swedish category label prefix — Adress, Personnummer, Telefon, E-post — so a detail's kind is explicit (e.g. "- Telefon: 070-123 45 67").
- **FR-003**: The zone MUST instruct the model to place details it cannot confidently attribute to a person under a final "## Övriga uppgifter" section, and MUST explicitly forbid guessing an owner for an uncertain detail (no force-pairing).
- **FR-004**: The zone MUST instruct the model to omit "## Övriga uppgifter" entirely when every detail is attributed, and to omit detail bullets it has no content for (no "(inga)" placeholders) — preserving the zone's existing empty-sections-omitted convention.
- **FR-005**: The existing no-greeting guardrail (output starts directly with the list, no greeting or meta-commentary) MUST be preserved in the rewritten instruction.
- **FR-006**: The multi-part combine step for Kontakter MUST merge sections by exact trimmed heading text: person sections in first-seen order, detail lines deduplicated per section by exact trimmed match, preserving first-seen line order.
- **FR-007**: The combine step MUST pin the "## Övriga uppgifter" section (exact trimmed heading match) to the END of the combined output, after all person sections, regardless of which part produced it or where it was first seen.
- **FR-008**: The combine step MUST fold detail lines that appear before any heading in a part result into the "## Övriga uppgifter" section (they are unattributed by definition), replacing the previous heading-less leading section.
- **FR-009**: The combine step MUST preserve a person section whose heading was seen but which has no detail lines (a found name is extracted information and must not be silently dropped).
- **FR-010**: The previous canonical category-heading ordering (Namn, Adresser, Personnummer, Telefonnummer, E-post) MUST be removed from the combine step — those headings no longer have special status and, if a model still emits one, it merges like any other heading in first-seen order.
- **FR-011**: Both mirrored copies of the Kontakter long help text MUST be updated to describe per-person grouping in natural Swedish, MUST remain word-for-word identical to each other, and MUST pass the existing drift guard. The Swedish copy passes the humanizer review gate before shipping.
- **FR-012**: The single-part path (short documents) MUST remain a pass-through of the model's output, unchanged by this spec — only the instruction text changes what the model produces.
- **FR-013**: This spec MUST NOT add any PII scrubbing or redaction to the Kontakter zone — extracting contact details verbatim is the zone's purpose; the deterministic PII replacement introduced for Anonymisera (spec 039) stays anonymisera-only.
- **FR-014**: The change MUST introduce no new outbound network calls, no new dependencies, and no UI changes beyond the help text (Principle I; same single localhost inference path).

### Key Entities

- **Person section**: a second-level heading whose text is a person's name, holding zero or more category-labeled detail bullets belonging to that person.
- **Övriga uppgifter section**: the single catch-all section for unattributed details; identified by its exact heading text; always last when present; omitted when empty.
- **Part result**: the model's output for one part of a long document (spec 038); the unit the combine step consumes.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a document with ≥2 persons with distinct details, the result file groups 100% of attributed details under their owner's section — zero category sections (Namn/Adresser/Personnummer/Telefonnummer/E-post) appear as top-level grouping.
- **SC-002**: For part results containing an unattributable detail, the combined output places it under "## Övriga uppgifter" as the final section in 100% of runs (deterministic combine behavior, verifiable with fixed part inputs).
- **SC-003**: For a long document where the same person heading appears in N parts, the combined result contains exactly 1 section for that heading, with the union of its deduplicated details — no detail lost, none duplicated (deterministic, verifiable with fixed part inputs).
- **SC-004**: Both copies of the Kontakter help text describe per-person grouping and are byte-identical to each other; the existing drift guard passes.
- **SC-005**: All previously passing checks for unrelated zones remain green — the combine behavior of every other zone is byte-identical to before this change.

## Assumptions

- The model-facing instruction can only *steer* the model; per-person grouping quality on real documents is model-dependent (gemma3:4b vs larger tiers). The deterministic guarantees of this spec live in the combine step and the instruction text; acceptance of model-output quality follows the project's existing convention for model-quality concerns (tested with canned model outputs, manually spot-checked with the real model).
- Heading matching is by exact trimmed text only. Name variants ("David Dahl" vs "D. Dahl") produce separate sections — accepted limitation; fuzzy unification could merge two real people and is rejected as more harmful (Principle VIII).
- Detail lines before any heading are unattributed by definition and belong in "Övriga uppgifter" (supersedes the previous heading-less leading section in the combine step).
- A person section with a bare heading and no details is preserved (a found name is information). The previous combine step dropped empty sections; for per-person output this would silently delete people, so the behavior changes deliberately.
- "## Övriga uppgifter" is reserved as the catch-all heading; an actual person with that exact name is accepted as a non-case.
- Existing behavior for documents with no extractable contacts is out of scope and unchanged.
- No new interactive UI is introduced; the existing browser-test suite's zone coverage continues to apply, with assertions updated only where they pin the old category headings.
