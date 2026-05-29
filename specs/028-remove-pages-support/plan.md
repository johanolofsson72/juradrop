# Implementation Plan: Remove .pages support

**Branch**: `main` | **Date**: 2026-05-29 | **Spec**: [spec.md](./spec.md) | **Track**: spec-only

## Summary

Remove the `.pages` input format end to end and replace its failure path with an honest, actionable "Pages stöds inte — exportera till Word/PDF först" message. Removal, not new behaviour → spec-only (no `.allium`, no `/tla`). The constraint is expressed as tests.

## Technical Context

- **Rust** (Tauri core): `InputFormat`, `extract` dispatch, `pages_extract` module, `ZoneFailure`, `sammanfatta` drop routing, `zone_id` hint copy.
- **TS/fixtures**: `DropZone.errors.ts`, `zone-error-strings.json`, `zone-identity.json`, drift tests, drop-zone tests.
- **Docs**: README format list + the Pages paragraph.
- **Net-new deps**: 0 (removal). Check whether any crate became unused (none expected — `.pages` reused `zip`/`quick-xml` shared with `.odt`).

## Constitution Check

- **VIII. Honest Failure States** — ✅ strengthened: a misleading "parse error" becomes an accurate "not supported + here's the fix".
- **V. Swedish-First UI** — ✅ new copy is Swedish + humanizer-reviewed.
- **I. Privacy** — ✅ unaffected (no network/content change). All others unaffected. **PASS.**

## Approach

Repurpose the existing `ZoneFailure::PagesParseError` → `ZoneFailure::PagesUnsupported` (keeps the variant count stable; the spec-025 tag changes `pages_parse_error` → `pages_unsupported`). Remove `InputFormat::Pages` + `pages_extract`. In `sammanfatta`, add an explicit `.pages` check (zip OR dir, case-insensitive) that emits `PagesUnsupported` BEFORE the generic `detect_from_path().is_none()` → `InvalidFormat` fallthrough, so `.pages` gets the specific message. Purge `.pages` from hint copy, the `invalid_format` string, README, fixtures, and tests; keep all three drift sources (Rust ↔ JSON ↔ TS) in lock-step.

## Structure Decision

No new files; one file deleted (`pages_extract.rs`). Edits localised to `src-tauri/src/zones/*` + the fixtures + README + tests.
