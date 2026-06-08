# Specification Quality Checklist: Gatuadress Anonymisering

**Purpose**: Validate specification completeness and quality before planning
**Created**: 2026-06-08
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details that obscure intent (regex shapes are the requirement surface for a hardening spec, as in 045)
- [x] Focused on user value (the address half of the privacy zone) and the live-test evidence
- [x] Written so the behavior is testable by a non-author
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements testable and unambiguous (suffix set enumerated, house-number-required, capitalization, phone-group count)
- [x] Success criteria measurable (SC-001..SC-006 tie to concrete strings)
- [x] Success criteria technology-agnostic at the outcome level
- [x] Acceptance scenarios defined for all four user stories
- [x] Edge cases identified (excluded suffixes, no-number, lowercase, no-suffix streets, city names, phone over-extension)
- [x] Scope bounded (included vs excluded suffixes; streets without suffix stay model's job)
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] Every FR has acceptance coverage
- [x] User scenarios cover the primary flows (scrub, precision, prompt, phone-fix)
- [x] Meets the measurable outcomes
- [x] No implementation leakage beyond the named modules being extended (pii_scrub/pii_sweep/anonymisera.rs)

## Notes

- Light track per `.claude/rules/specs.md`: two deterministic regex additions/extensions in the existing transformation; no new state machine, no concurrency.
- Direct descendant of 045 — same field-bug lineage (Meja's question → Johan's live test). The address half of the original two-part question is now answered structurally, not left to the 4b model.
