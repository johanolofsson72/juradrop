# Contract: Kontakter per-person output + deterministic merge (spec 040)

Supersedes the Kontakter rows of `specs/038-chunked-summarization/contracts/chunking.md` (the per-category Aggregate merge). All other zones' merge contracts are untouched (SC-005).

## 1. Instruction contract (KONTAKTER_SYSTEM_PROMPT — steered, not guaranteed)

The prompt const MUST demand, testably-by-inspection:

| # | Demand | Spec |
|---|---|---|
| I-1 | One `## ` heading per person (the person's name) | FR-001 |
| I-2 | Bullets labeled `Adress:` / `Personnummer:` / `Telefon:` / `E-post:` | FR-002 |
| I-3 | Unattributable details under a final `## Övriga uppgifter`; never guess an owner | FR-003 |
| I-4 | Omit `## Övriga uppgifter` when everything is attributed; no `(inga)` placeholders | FR-004 |
| I-5 | No greeting / meta-commentary ("skriv bara") | FR-005 |
| I-6 | Extraction scope: names + the four categories only | FR-002 (clarified) |

The heading literal `## Övriga uppgifter` is a shared `const` used by both prompt text and merge (single source of truth — prompt and merge can never disagree).

## 2. Merge contract (`merge_kontakter(parts: &[String]) -> String` — deterministic, guaranteed)

Given ≥2 part results (single-part never reaches the merge; FR-012):

| # | Guarantee | Spec |
|---|---|---|
| M-1 | Sections keyed by exact trimmed heading text; same heading across parts → ONE section | FR-006 |
| M-2 | Person sections in first-seen order; canonical category order removed | FR-006, FR-010 |
| M-3 | `## Övriga uppgifter` pinned last, wherever/whenever first seen | FR-007 |
| M-4 | Lines before any heading in a part (incl. whole heading-less parts) → Övriga section | FR-008 |
| M-5 | Per-section exact-trim dedup, first-seen line order; NO cross-section dedup | FR-006 (clarified) |
| M-6 | A person section with zero lines renders as a bare heading (not dropped) | FR-009 |
| M-7 | An empty Övriga section (no unattributed content) is omitted | FR-004 |
| M-8 | Output = sections joined with blank lines: heading, blank, lines (bare heading when no lines) | format stability |
| M-9 | Pure function of its inputs — no I/O, no logging of content | Principle I |

## 3. Out of contract

- Model output quality on the single-part path (pass-through; prompt-steered only).
- Name-variant unification ("David Dahl" vs "D. Dahl" → separate sections; accepted limitation).
- Any scrubbing/redaction (spec-039 boundary: anonymisera-only).
