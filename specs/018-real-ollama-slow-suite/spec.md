# Feature Specification: Real-Ollama slow suite

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: Draft
**Track**: Spec-only (test-only; no behavior change, no new entities/state → no `.allium`, no `/tla`).

**Input**: Every zone-pipeline test mocks `/api/generate`, so nothing verifies the actual Swedish system prompts produce sane output against the real `gemma3:4b`. A prompt regression or a model-version bump would ship silently. Add a gated slow suite that runs one REAL inference per zone against a running local Ollama on the spec-013 fixtures, asserting loose, deterministic-where-possible properties (sidecar created, non-empty, disclaimer present for disclaimer zones). It runs `#[ignore]`'d — like `sidecar_roundtrip` — because it needs the model present; normal `cargo test` stays fast and offline.

## Why this spec exists

Recommendation #3. The fixtures from spec 013 are ideal real inputs. A hardware-gated suite catches the class of regression mocks can't: the prompts themselves drifting, or a model upgrade changing output shape. It skips cleanly when Ollama/model is absent, so it's safe to keep in-tree.

## What's IN scope

| Item | Type |
|---|---|
| `tests/real_ollama_zones.rs` — one `#[ignore]`'d test looping all 9 zones | Test |
| Skip-cleanly guard (no Ollama / no `gemma3:4b` → eprintln + return, never fail) | Test |
| Real pipeline per zone on the committed fixture against `127.0.0.1:11434` | Test |
| Loose assertions: sidecar created + non-empty + disclaimer present for disclaimer zones | Test |
| Update spec-013 `ignore_audit.rs` expected count 1 → 2 (+ reason) | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Exact-output assertions | Real model output is non-deterministic; assert shape/presence, not content |
| Running in CI / on every `cargo test` | Needs the ~3GB model + minutes of inference; `#[ignore]`'d hardware-only |
| Auto-pulling the model | The skip guard tells the user to pull; no silent 3GB download in a test |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: One test per zone or one looping test? → A: **One looping `#[ignore]`'d test.** Keeps the ignore-audit count low (1→2) and shares the skip guard; per-zone `println!` reports progress.
- Q: What to assert on non-deterministic output? → A: **Shape + presence:** sidecar exists at the canonical path, content non-empty, source byte-identical, and the deterministic disclaimer paragraph present for disclaimer zones. No content-matching.
- Q: Behaviour when Ollama/model absent? → A: **Skip cleanly** (eprintln + return), mirroring `sidecar_roundtrip`. Never fail a run just because the hardware isn't present.

## Requirements

- **FR-001**: `src-tauri/tests/real_ollama_zones.rs` MUST contain ONE `#[ignore]`'d async test (with a `// HARDWARE:` reason comment) looping all 9 zones.
- **FR-002**: It MUST target a real Ollama at `127.0.0.1:11434` (explicit `with_base_url`, not the debug seam) and skip cleanly (eprintln + return) if `list_tags` errors or `gemma3:4b` is absent.
- **FR-003**: For each zone it MUST run the real `handle_drop` on the committed fixture, wait (generous timeout) for the sidecar, and assert: sidecar created with the zone's suffix, content non-empty, source byte-identical, disclaimer present for disclaimer zones.
- **FR-004**: `ignore_audit.rs` (spec 013 SC-004) MUST be updated: expected `#[ignore]` count 1 → 2, with a comment naming both (`sidecar_roundtrip` + `real_ollama_zones`). Both MUST carry a `// HARDWARE:` reason.
- **FR-005**: Normal `cargo test` MUST stay green + fast (the new test is skipped). Net new deps: 0.

## Success Criteria

- **SC-001**: `cargo test` (no `--ignored`) stays green; the slow test is ignored.
- **SC-002**: The slow test compiles and, run with `--ignored` on a machine without the model, skips cleanly (no failure).
- **SC-003**: `ignore_audit` passes with the updated count of 2, both justified.
- **SC-004**: Net new deps: 0.
