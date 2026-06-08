# Implementation Plan: Hel-rads-adress — Whole-Line Address Collapse + Bracket Fix

**Branch**: `047-hel-rads-adress` (register row; work on `main`) | **Date**: 2026-06-08 | **Spec**: [spec.md](spec.md)

## Summary

Add `RE_ADRESS_FULL` (street + optional comma + spaced-or-unspaced postnummer + city) so a
complete Swedish address line collapses to one `[Adress N]` via the existing leftmost-longest
sweep, and remove the clashing free-text "Adress 1/2" prompt instruction so the model keeps the
`[Adress N]` brackets. Both address patterns share `Category::Adress`. Partial street-only and
standalone postnummer behaviour is unchanged. Zero dispatch changes.

## Technical Context

**Language**: Rust only. **Dependencies**: none new. **Testing**: cargo unit + wiremock integration.
**Privacy**: unchanged — raw address removed before the model regardless of placeholder rendering (FR-010).

## Constitution Check — PASS ×9

- **I (Privacy)**: STRENGTHENED — whole address lines (incl. city + unspaced postnummer) now removed deterministically. No new outbound.
- **VIII (Honest failure)**: removing the model fallback for suffix-less streets is honest (regex > 4b model; disclaimer covers the rest).
- **V (Swedish UI)**: prompt is model-facing; the only user-facing copy is the unchanged sweep warning. No new copy → humanizer gate not triggered. No UI change → frontend-design gate not triggered.
- **II/III/IV/VI/VII/IX**: untouched.

## Design

### Verified pattern (validated against a battery)

Extract the spec-046 street body to a shared `const STREET_BODY` (single source), then:
- **`RE_ADRESS`** (rebuilt from `STREET_BODY`): `\b{STREET_BODY}\b` — unchanged behaviour.
- **`RE_ADRESS_FULL`** (new): `\b{STREET_BODY}\s*,?\s+[1-9]\d{2}[\x{00A0} ]?\d{2}\s+[A-ZÅÄÖ][a-zåäö]+\b`
  — street + optional comma + postnummer (spaced/NBSP/unspaced, `[1-9]` first) + one capitalized city word.

Build the patterns via string concat (`String::from(r"\b") + STREET_BODY + …`) to avoid `format!`
brace-escaping of `\d{2}` / `\x{00A0}`.

### pii_scrub.rs
- Candidate loop adds `(&*RE_ADRESS_FULL, Category::Adress)` BEFORE `(&*RE_ADRESS, Category::Adress)`.
  Both feed `Category::Adress`; the leftmost-longest sweep (start asc, len DESC, category asc) keeps
  the longer whole-line span and discards the street/postnummer sub-spans. No new category, no
  registry-width change (still `[;5]`).
- The whole-line value (`"Storgatan 5, 114 35 Stockholm"`) is the registry key → same line twice = same index.

### pii_sweep.rs
- `RE_ADRESS_FULL` is SCRUB-ONLY (a "grab-more" superset). The sweep keeps using `RE_ADRESS` for
  residual-street detection — a leaked full line's street part is still caught, no double-count.
  `STREET_BODY` extraction is the only sweep edit.

### prompts/anonymisera.rs
- DELETE the "Ersätt varje adress som inte redan är en platshållare med \"Adress 1\", \"Adress 2\". "
  sentence. Keep `[Adress N]` in the preserve-verbatim list. Update the comment (spec 047): the
  regex now owns addresses; removing the instruction stops the model stripping `[Adress N]` brackets.

### What does NOT change
Dispatch, writers, chunking, RE_POSTNUMMER (stays spaced-only), RE_PHONE, snapshots, frontend.

## Test plan

**Unit — pii_scrub.rs**: `Storgatan 5, 114 35 Stockholm` → `[Adress 1]` (whole line, no `[Postnr]`,
no city); `Lökgatan 1, 32456 Stockholm` (unspaced) → `[Adress 1]`; NBSP `Lillgatan 12B, 412 96
Göteborg` → `[Adress 1]`; comma-less `Vasagatan 1 111 20 Stockholm` → `[Adress 1]`; same line twice
→ same index; street-only `Storgatan 5 (kontoret)` → `[Adress 1]`; standalone `114 35` → `[Postnr 1]`;
bare `11435`/`15 000`/`T 4521-25` unchanged; multi-line field doc → 4 distinct `[Adress N]`, zero
raw streets/cities/postnummer; UTF-8 city adjacency.
**Unit — pii_sweep.rs**: `STREET_BODY` refactor keeps existing RE_ADRESS detection green.
**Unit — prompts**: prompt has NO free-text "Adress 1/2" instruction; still lists `[Adress N]`.
**Integration (wiremock)**: the field doc → prompt has the 4 lines as `[Adress 1..4]`, zero raw
street/city; multi-chunk same line → one index; other-zone byte-identity (raw line reaches Sammanfatta).

## Execution order
1. pii_sweep.rs: extract `STREET_BODY` const, rebuild `RE_ADRESS` from it, add `RE_ADRESS_FULL` + unit tests
2. pii_scrub.rs: add `RE_ADRESS_FULL` candidate (before `RE_ADRESS`) + unit tests
3. prompts/anonymisera.rs: delete free-text instruction + update pinning test
4. integration tests (field doc whole-line, multi-chunk, byte-identity)
5. full gates
