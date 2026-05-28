# Contract: zone-error-strings.json (extended schema)

**Feature**: 009-long-tail-formats
**Date**: 2026-05-28
**File**: `src-tauri/tests/fixtures/zone-error-strings.json`

This fixture is the **single source of truth** for the Swedish error strings rendered by drop zones. Both the Rust side (`src-tauri/src/zones/errors.rs`) and the TS side (`src/components/DropZone.errors.ts`) assert against this file in their drift-detection tests. Changing any value here requires changing both code sides in the same commit.

## C-008 — Schema (post-spec-009)

```json
{
  "_comment": "string — change-tracking comment, ignored by tests",
  "invalid_format":       "string ≤ 80 chars, Swedish",
  "multiple_files":       "string ≤ 80 chars, Swedish",
  "zone_busy":            "string ≤ 80 chars, Swedish",
  "zone_disabled":        "string ≤ 80 chars, Swedish",
  "parse_error":          "string ≤ 80 chars, Swedish",
  "password_protected":   "string ≤ 80 chars, Swedish",
  "empty_text":           "string ≤ 80 chars, Swedish",
  "model_error":          "string ≤ 80 chars, Swedish",
  "save_error":           "string ≤ 80 chars, Swedish",
  "no_extractable_text":  "string ≤ 80 chars, Swedish",
  "unsupported_encoding": "string ≤ 80 chars, Swedish",
  "rtf_parse_error":      "string ≤ 80 chars, Swedish",
  "pages_parse_error":    "string ≤ 80 chars, Swedish",
  "odt_parse_error":      "string ≤ 80 chars, Swedish"
}
```

Total keys: 14 (11 inherited + 3 new in spec 009).

## C-009 — Pinned values (spec 009 deltas)

| Key | Value | Length (chars) |
|---|---|---|
| `invalid_format` (UPDATED) | `Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt` | 80 |
| `rtf_parse_error` (NEW) | `Kunde inte läsa .rtf-filen` | 26 |
| `pages_parse_error` (NEW) | `Kunde inte läsa .pages-filen` | 28 |
| `odt_parse_error` (NEW) | `Kunde inte läsa .odt-filen` | 26 |

## C-010 — Invariants enforced by drift tests

1. **Every Rust enum variant has a JSON key**: for each `ZoneFailure::<variant>`, `serde_json::to_string(&variant)` produces a key present in the JSON. Verified by `tests/long_tail_drift.rs::rust_variants_have_fixture_keys`.
2. **Every JSON key has a Rust enum variant**: each top-level key in the JSON (excluding `_comment`) maps to a `ZoneFailure::<variant>::to_string()`. Verified by `tests/long_tail_drift.rs::fixture_keys_have_rust_variants`.
3. **Rust `Display` value == JSON value**: for each `ZoneFailure` variant, `variant.to_string() == fixture[snake_case_tag]`. Verified by `tests/long_tail_drift.rs::rust_display_matches_fixture`.
4. **TS string value == JSON value**: for each TS key in `DropZone.errors.ts`, the value matches the JSON. Verified by `src/__tests__/DropZone.longtail-formats.test.tsx::ts_strings_match_fixture`.
5. **No value exceeds 80 chars**: verified Rust-side by existing `every_variant_is_at_most_80_chars` test (extended).
6. **No value starts with `Error:` or contains the English word `error` (case-insensitive)**: verified Rust-side by existing `no_variant_starts_with_english_error_prefix` test (extended).
7. **Long-tail keys exist**: `tests/long_tail_drift.rs::long_tail_keys_present` asserts that `rtf_parse_error`, `pages_parse_error`, `odt_parse_error` exist in the JSON.

## C-011 — Change procedure

Editing any value requires the same three changes in one commit:
1. Update the value in `src-tauri/tests/fixtures/zone-error-strings.json`.
2. Update the `#[error("…")]` attribute on the matching variant in `src-tauri/src/zones/errors.rs`.
3. Update the matching string in `src/components/DropZone.errors.ts`.

Failure to update all three in lock-step trips the drift tests (one per language) and CI rejects the commit.
