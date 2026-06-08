# Implementation Plan: Gatuadress Anonymisering — Deterministic Street-Address Scrub (+ phone-tail fix)

**Branch**: `046-gatuadress-anonymisering` (register row; work on `main`) | **Date**: 2026-06-08 | **Spec**: [spec.md](spec.md)

## Summary

Add Swedish street addresses as a fifth deterministic category to the spec-039/045 scrub +
spec-014 sweep, and fix the pre-existing `RE_PHONE` three-group ceiling. The street scrub
replaces every `Capital + known-suffix + house-number` match with `[Adress N]` before the
model, whole-text before chunking, same value → same global index. The prompt's
preserve-verbatim list gains `[Adress N]` while keeping the free-text "Adress 1/2" fallback.
Zero dispatch changes — both call sites already route through `pii_scrub` / `pii_sweep`.

## Technical Context

**Language**: Rust only (src-tauri) — zero frontend, zero TS changes.
**Dependencies**: none new (regex already in tree).
**Testing**: cargo unit (scrub + sweep) + wiremock integration; vitest/Playwright unaffected.
**Performance**: two regex changes (one new pass, one widened) over ≤288k chars — negligible.
**Privacy**: street value→index map in memory only; scrubbed text already `Redacted` at the call site. No new outbound.

## Constitution Check — PASS ×9 (pre + post design)

- **I (Privacy)**: STRENGTHENED — matched street addresses can no longer reach the sidecar; the phone fix closes a partial-number leak. Registry never persisted/logged (FR-011). No new network call.
- **VIII (Honest failure)**: over-redaction within the included suffix set chosen over under-redaction; unmatched streets stay the model's job + disclaimer (honest about the limit).
- **V (Swedish UI)**: residual-street warning copy is user-facing Swedish → **humanizer gate applies** (FR-013). No UI layout change → frontend-design gate NOT triggered.
- **II/III/IV/VI/VII/IX**: untouched.

## Design

### Verified regexes (validated against a battery before coding)

**RE_ADRESS** (new `pub(crate)` in pii_sweep.rs):
```
\b[A-ZÅÄÖ][a-zåäöA-ZÅÄÖ]*(?:gatan|gata|vägen|väg|gränden|gränd|stigen|stig|torget|torg|allén|allé|backen|backe|liden|lid|kajen|kaj|stranden|strand|brinken|brink|hamnen|hamn|esplanaden|esplanad|promenaden|promenad|gången|gång)\s+\d{1,3}(?:\s?[A-Za-zÅÄÖåäö])?\b
```
- Capital initial → proper-noun gate (drops `plan 3`, `vägen 3 meter`).
- Suffixes longest-first within families (`gatan` before `gata`); excluded ambiguous: `plan/led/ring/park/plats`.
- Required `\s+\d{1,3}` house number (drops `Storgatan är avstängd`); optional `(?:\s?[A-Za-z])?` trailing letter whose closing `\b` prevents grabbing the first letter of a following word (`Storgatan 5 och` → `Storgatan 5`).
- Compound multi-word streets (`Sankt Eriksgatan 5`) capture the street+number span (`Eriksgatan 5`); the leading word stays harmlessly — documented edge.

**RE_PHONE** (widened): the national branch gains an optional third trailing group:
```
\b 0 \d{1,3} [\s-]? \d{2,4} [\s-]? \d{2,4} (?:[\s-]? \d{2,4})? \b
```
Captures `070-123 45 67` in full (no `67` tail); `08-555 12 34` and the `+46` branch unchanged.

### pii_sweep.rs
- `RE_ADRESS` static (single source, consumed by scrub + sweep).
- Widen `RE_PHONE`'s national branch (one line).
- `PiiFindings` gains `pub adress: usize`; `total()`/`is_clean()` include it; `scan_residual_pii` counts it.
- `RE_PLACEHOLDER` gains `Adress` (already present as `Adress` — VERIFY: the existing mask lists `Adress`, so `[Adress N]` is ALREADY masked; confirm and add only if absent).
- `warning_paragraph`: add a `"{n} adress(er)"` part (sv plural: 1 adress / N adresser) when `f.adress > 0`. Humanizer-reviewed (FR-013).

### pii_scrub.rs
- `Category` gains `Adress = 4` with `label() => "Adress"`.
- Candidate loop adds `(&*RE_ADRESS, Category::Adress)`; registries `[;4] → [;5]`.
- `ScrubOutcome` gains `pub adress: usize`.
- Overlap: street match ends at the house number (before the comma); postnummer starts after — non-overlapping. The leftmost-longest sweep + category tiebreak place both on one line.

### prompts/anonymisera.rs
- Add `[Adress N]` to the preserve-verbatim bracket list.
- KEEP the existing "Ersätt varje adress med Adress 1/2" sentence as the fallback for streets the regex misses (FR-007) — do not remove it.

### What does NOT change
Dispatch, writers, chunking, snapshots, frontend, settings, fixtures.

## Test plan

**Unit — pii_scrub.rs**: the four field streets → `[Adress N]`; `Lillgatan 12B` letter form; `Köpmangatan 3 A` spaced letter; same street twice → same index; precision negatives (`plan 3`, `Plan 3`, `Storgatan är avstängd`, `vägen 3 meter`, `motorled 4`, `Storgatan 5 och Lillgatan` → only first) byte-identical; UTF-8 adjacency; phone `070-123 45 67` → `[Telefon 1]` no tail; `08-555 12 34` unchanged; all-five-categories doc clean per sweep.
**Unit — pii_sweep.rs**: RE_ADRESS detect/negatives mirror; `[Adress N]` masked; widened phone detect; warning lists adress (1 adress / 2 adresser).
**Integration (wiremock)**: the spec-045 field doc echo-mock → all four streets `[Adress N]`, zero raw streets, `070-123 45 67` fully scrubbed; multi-chunk same street → one index; other-zone byte-identity (raw street + raw phone reach Sammanfatta).
**Prompt pinning**: prompt names `[Adress N]` AND keeps the free-text fallback sentence.

## Execution order

1. pii_sweep.rs: RE_ADRESS + widen RE_PHONE + PiiFindings.adress + mask/scan + warning (humanizer copy) + unit tests
2. pii_scrub.rs: Category::Adress + registries widen + ScrubOutcome.adress + unit tests (incl. phone-no-tail, precision)
3. prompts/anonymisera.rs: add [Adress N] to preserve list, keep fallback + pinning test
4. integration tests (the field doc + multi-chunk + byte-identity)
5. full gates (cargo test, clippy -D warnings, fmt; vitest/playwright/eslint/tsc)
