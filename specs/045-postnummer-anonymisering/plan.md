# Implementation Plan: Postnummer Anonymisering — Deterministic Postcode Scrub + Address Anchor

**Branch**: `045-postnummer-anonymisering` (register row; work on `main`) | **Date**: 2026-06-08 | **Spec**: [spec.md](spec.md)

## Summary

Add Swedish postnummer as a fourth deterministic category to the existing spec-039
scrub + spec-014 sweep, reusing the single-pattern-source discipline. The scrub replaces
every canonical spaced postnummer (`\b[1-9]\d{2}[\x{00A0} ]\d{2}\b`) with `[Postnr N]`
BEFORE the model, whole-text before chunking, same value → same index globally. The sweep
counts residual postnummer and frames them as a likely-leaked address line in the warning.
The prompt's preserve-verbatim list gains `[Postnr N]`. Zero dispatch changes — both call
sites (`sammanfatta.rs:244` scrub, `:432` sweep) already route through the two modules.

## Technical Context

**Language**: Rust only (src-tauri) — zero frontend, zero TS changes.
**Dependencies**: none new (regex already in tree; the new `RE_POSTNUMMER` lives beside the existing `RE_*`).
**Testing**: cargo unit (scrub + sweep) + wiremock integration (anonymisera pipeline); vitest/Playwright unaffected.
**Performance**: one more regex pass over ≤288k chars — negligible vs model latency.
**Privacy**: postnummer value→index map in memory only; scrubbed text already wrapped in `Redacted` at the call site (FR-010). No new outbound.

## Constitution Check — PASS ×9 (pre + post design)

- **I (Privacy)**: STRENGTHENED — canonical postnummer can no longer reach the sidecar; registry never persisted/logged (FR-010). No new network call → Principle I wall intact.
- **VIII (Honest failure)**: the sweep net grows; over-redaction (the rare `NNN NN`-grouped amount) chosen over under-redaction — the safe direction for the privacy zone. The address anchor is an honest partial signal, not a false promise of full address detection.
- **V (Swedish UI)**: one new user-facing Swedish sentence fragment (the address-anchor warning copy) → **humanizer gate applies** (FR-012). No UI layout/component change → frontend-design gate NOT triggered (sidecar text only).
- **II/III/IV/VI/VII/IX**: untouched surfaces.

## Design

### pii_sweep.rs (the single pattern source + the warning)

1. **`RE_POSTNUMMER`** (new `pub(crate)` `LazyLock<Regex>`): `r"\b[1-9]\d{2}[\x{00A0} ]\d{2}\b"`.
   First digit `1-9` (real postnummer span 10000–98499, never lead with 0, and the 0-band
   stays reserved to `RE_PHONE` so the two never fight a span — clarify Q). Separator is
   exactly one ASCII space OR NBSP (U+00A0) — Word `.docx` exports commonly use NBSP
   (clarify Q). `\b` on both ends so the pattern never matches inside a longer digit run.
2. **`PiiFindings`** gains `pub postnummer: usize`; `total()` and `is_clean()` include it.
3. **`scan_residual_pii`** counts `RE_POSTNUMMER.find_iter(&masked)`.
4. **`RE_PLACEHOLDER`** gains `Postnr`: `\[(?:Person|Personnr|Adress|Telefon|E-post|Postnr)[^\]]*\]` (FR-007) so `[Postnr N]` never counts as residue.
5. **`warning_paragraph`**: add a `"{n} postnummer"` part ("postnummer" is identical sv singular/plural). When `f.postnummer > 0`, append the address-anchor sentence after the existing one. Humanizer-reviewed Swedish (FR-012).

### pii_scrub.rs (the deterministic replacer)

1. **`Category`** gains `Postnr = 3` with `label() => "Postnr"`.
2. Candidate collection loop adds `(&*RE_POSTNUMMER, Category::Postnr)`. Registries array `[Vec<&str>; 3] → [Vec<&str>; 4]`.
3. **`ScrubOutcome`** gains `pub postnummer: usize`.
   No-overlap note: a `[1-9]`-leading spaced postnummer can never collide with `RE_PHONE`
   (requires leading 0) nor `RE_PERSONNUMMER` (10–12 contiguous digits; the space breaks the
   run), so the leftmost-longest sweep places it cleanly; the tiebreak slot is defensive only.

### prompts/anonymisera.rs

Extend the placeholder-preservation sentence: the bracketed list `[Personnr 1], [Telefon 2]
och [E-post 1]` gains `[Postnr 1]`. Model-facing Swedish; no behavior beyond verbatim preservation.

### What does NOT change

Dispatch (both call sites already route through the modules), writers, chunking, snapshots,
frontend, settings, fixtures. The scrub stays Anonymisera-gated (FR-009) by the existing
`if self.id == ZoneId::Anonymisera` guard — no new gate needed.

## Test plan

**Unit — pii_sweep.rs**: detects `114 35` (space) and `114\u{00A0}35` (NBSP); does NOT detect
`11435` (unspaced), `012 34` (leading 0 — phone's), `15 000` amount grouping, `T 4521-25`;
`[Postnr 1]` masked (not residue); warning lists postnummer + carries the address framing;
warning omits postnummer when count 0.
**Unit — pii_scrub.rs**: `114 35` → `[Postnr 1]`; same value → same index; distinct → sequential;
NBSP form replaced; amount/case-number/unspaced left byte-identical (SC-002); UTF-8 adjacency;
scrubbed output clean per the sweep (DetectAndReplaceAgree); idempotence; all-four-categories
document (postnummer + personnummer + telefon + epost).
**Integration (wiremock, anonymisera)**: (a) echo-mock — input `Storgatan 5, 114 35 Stockholm`
→ sidecar has `[Postnr 1]`, zero `114 35`, no warning banner (SC-001); (b) fabricated `114 35`
in model output → warning banner with address framing (SC-004); (c) multi-chunk same postnummer
in two chunks → one index (SC-003); (d) non-anonymisera zone with a postnummer-laden doc → prompt
contains the RAW `114 35` (SC-005 byte-identical input proof).

## Execution order

1. pii_sweep.rs: `RE_POSTNUMMER` + `PiiFindings.postnummer` + mask + `scan` + warning (humanizer copy) + unit tests
2. pii_scrub.rs: `Category::Postnr` + registries widen + `ScrubOutcome.postnummer` + unit tests
3. prompts/anonymisera.rs: placeholder list + pinning-test update
4. integration tests (anonymisera pipeline)
5. full gates (cargo test, clippy -D warnings, fmt; vitest/playwright unaffected but run)
