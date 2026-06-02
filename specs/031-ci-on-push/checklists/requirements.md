# Specification Quality Checklist: CI on push + pull request

**Created**: 2026-06-02 · **Feature**: [spec.md](../spec.md) · **Track**: spec-only

## Content Quality
- [x] Focused on developer/process value
- [x] All mandatory sections completed
- [x] No [NEEDS CLARIFICATION] markers remain

## Requirement Completeness
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Edge cases identified (cold cache, tag push, externalBin compile dependency)
- [x] Scope clearly bounded (no build/sign/release — that stays in release.yml)
- [x] Dependencies + assumptions identified

## Notes
- Spec-only track: no `.allium`, no `/tla`, no browser tests (CI YAML is not an interactive UI surface).
- The load-bearing constraint (CI must `fetch-ollama.sh` before Rust steps because `tauri-build` validates `externalBin`) was verified empirically: moving `binaries/` aside makes `cargo check` fail with "resource path 'binaries/ollama-…' doesn't exist".
- All items pass iteration 1.
