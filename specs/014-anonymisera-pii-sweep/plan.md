# Implementation Plan: Anonymisera PII-residue sweep (Spec 014)

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: full

## Summary

A pure, local, deterministic regex sweep over Anonymisera's model output detects residual personnummer / e-post / telefon and, when found, prepends a Swedish warning paragraph to the sidecar. Detection only — never edits the text. Net new deps: 0 (`regex` already transitive).

## Constitution Check

- **I. Privacy:** PASS — pure local string scan, zero outbound, reads only the model output. Strengthens the privacy promise (catches output-side leaks).
- **V. Swedish-first:** PASS — warning copy Swedish, via humanizer.
- **VIII. Honest failure:** PASS — the warning is honest about what automatic anonymisation may have missed.
- Gate: PASS, no violations.

## Technical approach

- `src-tauri/src/zones/pii_sweep.rs`:
  - `pub struct PiiFindings { personnummer, email, phone: usize }` + `total()` + `is_clean()`.
  - `pub fn scan_residual_pii(text: &str) -> PiiFindings` — three `regex::Regex` (lazily built via `std::sync::LazyLock`), each `.find_iter().count()`, minus placeholder false-positives.
  - `pub fn warning_paragraph(f: &PiiFindings) -> Option<String>` — builds the Swedish sentence, omitting zero categories; `None` when clean.
- Placeholder exclusion (FR-005): strip `[Personnr N]`/`[Telefon N]`/`[E-post N]` spans before counting, or count then subtract placeholder matches. Chosen: scan a placeholder-masked copy.
- Wire into `sammanfatta.rs` Anonymisera write path: after `response_text`, if `self.id == ZoneId::Anonymisera`, compute findings + prepend warning to the text passed to `build_summary_doc`.
- `regex` → direct dep in Cargo.toml.

## Project structure

```
src-tauri/src/zones/pii_sweep.rs       # NEW
src-tauri/src/zones/sammanfatta.rs     # wire sweep into Anonymisera write
src-tauri/Cargo.toml                   # regex direct dep
src-tauri/tests/zone_pipeline_anonymisera.rs  # +residue + clean integration cases
src-tauri/tests/pii_sweep_strings.rs   # warning-copy pin (optional)
```

## Phases

1. `pii_sweep` module + unit tests (patterns, placeholders, false positives, warning builder).
2. Wire into Anonymisera write path; regex dep.
3. Integration tests (residue → warning; clean → no warning).
4. Full suite + clippy + fmt; `/tla`.
