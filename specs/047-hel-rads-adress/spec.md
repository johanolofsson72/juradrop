# Feature Specification: Hel-rads-adress — Whole-Line Address Collapse + Bracket Fix

**Feature Branch**: `047-hel-rads-adress`

**Created**: 2026-06-08

**Status**: Draft

**Input**: User description: "Second live test (Johan, 2026-06-08 10:17, same field doc on real gemma3:4b): spec 046 scrubs the street but produces a fragmented line — 'Adress 1, [Postnr 1] Stockholm' — and the model STRIPPED the brackets ([Adress 1] → Adress 1) because the prompt's free-text instruction 'Ersätt varje adress med Adress 1' competes with the [Adress N] placeholder. Johan's ask: anonymize the WHOLE address line (street + postnummer + city) into a single [Adress N], e.g. 'Lökgatan 1, 32456 Stockholm' → '[Adress 1]'. Decision (AskUserQuestion): REMOVE the free-text 'Adress 1/2' instruction from the prompt so [Adress N] keeps its brackets like the other placeholders (the regex is now more reliable than the 4b model anyway); the cost is that suffix-less streets (Polhem 3, Box 1234) lose their model fallback and rely on the disclaimer. The whole-line pattern must also catch an UNSPACED 5-digit postnummer (32456) when it sits between a street and a city — unambiguous in that context, unlike a standalone 5-digit run."

## Clarifications

### Session 2026-06-08

- Q: What does the whole-line pattern match? → A: A street (the spec-046 `RE_ADRESS` body: Capital + known suffix + house number) + an optional comma + a postnummer that may be SPACED or UNSPACED (`[1-9]\d{2}`, optional single space/NBSP, `\d{2}`) + a city (one capitalized word). The whole span → a single `[Adress N]`. The unspaced 5-digit form is accepted HERE because the street-before/city-after context disambiguates it from an amount (which standalone `RE_POSTNUMMER` cannot, hence its spaced-only rule stays).
- Q: How does the whole-line pattern interact with the spec-045/046 partials? → A: `RE_ADRESS_FULL` and the partial `RE_ADRESS`/`RE_POSTNUMMER` all produce candidates; the leftmost-longest sweep keeps the longest, so a complete line collapses to one `[Adress N]` and the street/postnummer sub-spans inside it are discarded. A street WITHOUT a trailing postnummer+city still falls to `RE_ADRESS` → `[Adress N]`; a postnummer NOT preceded by a street still falls to `RE_POSTNUMMER` → `[Postnr N]`. Both address patterns share `Category::Adress` (one index series).
- Q: Is the city folded into the placeholder? → A: Yes — the city (one capitalized word) is part of the `[Adress N]` span and disappears. A multi-word city ("Upplands Väsby") keeps only its first word in the span; the trailing word is left (low-risk city fragment, no reliable pattern) — documented edge.
- Q: What happens to the prompt? → A: REMOVE the free-text "Ersätt varje adress med 'Adress 1', 'Adress 2'" sentence entirely. `[Adress N]` stays in the preserve-verbatim placeholder list (added in 046), so the model treats it exactly like `[Postnr N]` — no competing instruction, brackets preserved. Suffix-less streets are no longer model-handled; the disclaimer + the postnummer/street sweep cover residue.
- Q: Does removing the instruction change the privacy guarantee? → A: No. The deterministic scrub removes the raw address BEFORE the model regardless of what the model does with the placeholder; the bracket-stripping was cosmetic, not a leak. Removing the instruction only makes the output cleaner and more consistent.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A full address line collapses to one placeholder (Priority: P1)

A law student drops a document with `Lökgatan 1, 32456 Stockholm`. Today (046) it becomes `Adress 1, [Postnr 1] Stockholm` (fragmented, city left, brackets stripped). After this feature the whole line becomes `[Adress 1]`.

**Why this priority**: This is the direct field request. A single clean `[Adress N]` reads better, hides the city, and catches the unspaced postnummer that would otherwise leak.

**Independent Test**: Scrub `Lökgatan 1, 32456 Stockholm` → `[Adress 1]` (whole span, including the unspaced postnummer and city).

**Acceptance Scenarios**:

1. **Given** `Storgatan 5, 114 35 Stockholm`, **When** scrubbed, **Then** the whole line → `[Adress 1]` (no separate `[Postnr]`, no leftover city).
2. **Given** `Lökgatan 1, 32456 Stockholm` (UNSPACED postnummer), **When** scrubbed, **Then** the whole line → `[Adress 1]`.
3. **Given** the same full address line twice, **When** scrubbed, **Then** both → the same `[Adress N]` index.
4. **Given** `Lillgatan 12B, 412 96 Göteborg` (NBSP postnummer, house letter), **When** scrubbed, **Then** the whole line → `[Adress N]`.

---

### User Story 2 - Partial forms still work; standalone numbers unaffected (Priority: P1)

The whole-line pattern must not break the spec-045/046 partials: a street with no city still → `[Adress N]`, a standalone postnummer still → `[Postnr N]`, and amounts/case-numbers are still never touched.

**Why this priority**: Regression guard — folding must be additive, not a replacement that loses coverage.

**Independent Test**: `Storgatan 5 är avstängd` → unchanged (no number-less issue); `Storgatan 5 (utan ort)` → `[Adress 1]` (street-only); standalone `114 35` → `[Postnr 1]`; `15 000 kr` → unchanged.

**Acceptance Scenarios**:

1. **Given** a street with a house number but no following postnummer+city (`Storgatan 5 (kontoret)`), **When** scrubbed, **Then** → `[Adress 1]` (street-only fallback).
2. **Given** a standalone postnummer not preceded by a street (`postnr 114 35`), **When** scrubbed, **Then** → `[Postnr 1]`.
3. **Given** `15 000 kr`, `T 4521-25`, `11435` (bare, no address context), **When** scrubbed, **Then** unchanged.

---

### User Story 3 - The output keeps clean brackets (Priority: P2)

With the free-text instruction removed, the model preserves `[Adress N]` verbatim like every other placeholder, so the output is consistent.

**Why this priority**: Cosmetic consistency + it removes the only prompt clash. The privacy guarantee never depended on it, but a clean `[Adress 1]` is what the student expects.

**Independent Test**: The prompt no longer contains the free-text "Adress 1/2" instruction; it still lists `[Adress N]` in the preserve set.

**Acceptance Scenarios**:

1. **Given** the updated prompt, **When** inspected, **Then** it does NOT contain a free-text "Ersätt varje adress med 'Adress 1'" instruction, AND it still names `[Adress N]` in the preserve-verbatim list.

---

### Edge Cases

- A multi-word city (`Upplands Väsby`) — only the first word is in the span; the trailing word is left (low-risk fragment; no reliable pattern). Documented.
- A street + postnummer with NO city (`Storgatan 5, 114 35` end of line) — the full pattern needs a city, so this falls to street-only `[Adress N]` + the postnummer `[Postnr N]` (the 046/045 behavior). Acceptable — rare.
- Comma-less line (`Vasagatan 1 111 20 Stockholm`) — matched (the comma is optional).
- The whole-line span and the partial spans overlap; leftmost-longest keeps the longest (the full line), discarding the sub-spans (load-bearing — same mechanism that resolves phone-vs-personnummer in 039).
- Unspaced postnummer is ONLY caught inside the whole-line context; standalone `32456` stays untouched (the spec-045 spaced-only rule is unchanged — context is what makes it safe here).
- The `[Adress N]` registry lives in memory for one run; never persisted or logged (Principle I).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: For the Anonymisera zone only, the system MUST replace every whole Swedish address line (street per the spec-046 `RE_ADRESS` body + optional comma + a postnummer that may be spaced or unspaced + a city = one capitalized word) in the extracted text BEFORE the model, with a single `[Adress N]`.
- **FR-002**: The whole-line postnummer sub-pattern MUST accept an unspaced 5-digit form (`[1-9]\d{2}\d{2}`) in addition to the spaced/NBSP form, BECAUSE the street-before/city-after context disambiguates it. The standalone `RE_POSTNUMMER` (spec 045) MUST remain spaced-only.
- **FR-003**: `RE_ADRESS_FULL` and the partial `RE_ADRESS`/`RE_POSTNUMMER`/`RE_PHONE`/… MUST all feed the existing multi-category leftmost-longest sweep, so a complete address line collapses to one `[Adress N]` and the sub-spans inside it are discarded; partial forms outside a full line keep their existing placeholders.
- **FR-004**: Identical whole-line address strings MUST receive the same `[Adress N]` index; the whole-line and street-only matches share `Category::Adress` (one first-occurrence index series).
- **FR-005**: The whole-line scrub MUST run on the whole extracted text before chunking (global indices), like every other category.
- **FR-006**: The Anonymisera system prompt MUST NOT contain a free-text "Ersätt varje adress med 'Adress 1'" instruction; `[Adress N]` MUST remain in the preserve-verbatim placeholder list so the model keeps it (no bracket stripping).
- **FR-007**: Every other zone MUST receive byte-identical input (no whole-line scrub outside Anonymisera).
- **FR-008**: The whole-line value→index mapping MUST exist only in memory for the run — never persisted, never logged (Principle I).
- **FR-009**: Whole-line replacement MUST be UTF-8-safe (Swedish characters and city names adjacent to the match must never be corrupted).
- **FR-010**: The change MUST NOT alter the privacy guarantee: the raw address is removed before the model regardless of the placeholder's final rendering.

### Key Entities

- **Whole-line address match**: street + (optional comma) + postnummer (spaced/unspaced) + city; one scrub-registry entry under `Category::Adress`.
- **Scrub registry (unchanged shape)**: `Category::Adress` now receives both whole-line and street-only values; one index series.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `Storgatan 5, 114 35 Stockholm` and `Lökgatan 1, 32456 Stockholm` each scrub to exactly `[Adress 1]` — whole line, city included, no separate `[Postnr]`.
- **SC-002**: A street-only string (no city) still scrubs to `[Adress N]`; a standalone postnummer still scrubs to `[Postnr N]`; `15 000 kr` / `T 4521-25` / bare `11435` remain byte-identical.
- **SC-003**: Repeated whole-line addresses map to one stable `[Adress N]` index, including across chunks.
- **SC-004**: The prompt contains no free-text "Adress 1/2" instruction and still lists `[Adress N]` as a preserved placeholder.
- **SC-005**: All non-Anonymisera zones produce byte-identical results to pre-047.
- **SC-006**: The full existing test suite stays green (no regressions in the 045/046 address/postnummer/phone tests).

## Assumptions

- The street-before/city-after context makes an unspaced 5-digit postnummer unambiguous, so accepting it in the whole-line pattern does not reopen the amount/reference false-positive risk that keeps `RE_POSTNUMMER` spaced-only.
- A one-word city covers the dominant Swedish case; multi-word cities lose a trailing fragment (harmless).
- Removing the free-text address instruction is a net win: the regex (whole-line + street) handles the dominant forms deterministically and the model fallback was both unreliable AND the cause of the bracket-stripping. Suffix-less streets are rare and covered by the disclaimer.
- Track: light — one more regex pattern in the existing `Category::Adress` + a prompt deletion; no new state machine, no concurrency. `/tla` expected to be skipped at the triviality gate (as 045/046).
