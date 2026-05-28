# Specification Quality Checklist: Long-tail input formats (.rtf, .pages, .odt)

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-05-28
**Feature**: [Link to spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
  - Crate names (`rtf-parser`, `quick-xml`, `zip`) appear only in Assumptions/research-notes context, not in FRs. FRs say "pure-Rust crate" / "pure-Rust XML parser" without dictating a specific crate.
- [x] Focused on user value and business needs
  - Every user story frames the value (discoverability, honest failure, regression guard).
- [x] Written for non-technical stakeholders
  - User stories use Swedish-law-student language; FRs are testable but readable.
- [x] All mandatory sections completed
  - User Scenarios, Edge Cases, Requirements, Success Criteria, Assumptions all present.

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
  - All FR-level ambiguities resolved via informed guesses; recorded in Assumptions.
- [x] Requirements are testable and unambiguous
  - Each FR pins a measurable outcome (exact Swedish string, exact extension list order, exact char limits).
- [x] Success criteria are measurable
  - SC-001..SC-008 each pin a number or a 100 % outcome.
- [x] Success criteria are technology-agnostic (no implementation details)
  - SCs reference user-observable behavior (sidecar produced, error shown, hint copy fits) not crate names.
- [x] All acceptance scenarios are defined
  - Each user story has Given/When/Then scenarios covering happy and edge paths.
- [x] Edge cases are identified
  - 8 edge cases enumerated: empty text, >24k chars, .pages-as-directory, mixed case, ANSI RTF, ODT macros, password-protected pages, password-protected odt.
- [x] Scope is clearly bounded
  - In: best-effort .rtf/.pages/.odt input + hint copy update + InvalidFormat copy update. Out: writing .pages back; password handling; OCR for image-only PDFs; new state machine.
- [x] Dependencies and assumptions identified
  - 8 assumption bullets cover crate availability, format versions, license audit, no-writer fallback paths.

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
  - FR-001..FR-020 map 1:1 onto either an acceptance scenario, an edge case, or a success criterion.
- [x] User scenarios cover primary flows
  - P1 (.rtf happy path), P1 (corrupt long-tail), P2 (hint copy), P3 (regression guard for unsupported extensions).
- [x] Feature meets measurable outcomes defined in Success Criteria
  - SCs are achievable with the FRs as written; no SC requires a behavior the FRs do not specify.
- [x] No implementation details leak into specification
  - FRs reference language families and license classes, not specific crate versions.

## Notes

- The spec deliberately collapses the password-protected branch into the format-named parse error for long-tail formats (FR-008). This trades one minor false-negative (a `.pages` user who removes the password and re-tries still sees the same error if the parser also chokes on the dialect) for a uniform error surface across the entire long tail. Justified in the Why-this-priority text of US-2 and in the FR-008 rationale.
- The exact Swedish strings (`Kunde inte läsa .rtf-filen` etc.) are pinned at spec time so the cross-language drift fixture (SC-005) has something concrete to test against. They follow the existing `parse_error` pattern (`Kunde inte läsa dokumentet`) for tense and word choice — past conditional, no exclamation, no English loanword.
- The `.pages-as-directory` edge case (legacy Apple Pages < v5) is explicitly routed to `InvalidFormat` rather than format-named error (FR-019) — the user did not drop a file, so "best-effort extraction" cannot meaningfully apply.
- Hint copy ordering (`.docx, .pdf, .txt, .md, .rtf, .pages, .odt`) puts the four spec 005 formats first to preserve user muscle memory for the common case; the long-tail trio reads as a "and also" tail.
