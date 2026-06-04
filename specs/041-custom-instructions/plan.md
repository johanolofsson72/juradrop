# Implementation Plan: Custom Instructions (per-drop user guidance)

**Branch**: `main` (register rule: solo direct-push) | **Date**: 2026-06-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/041-custom-instructions/spec.md` (+ `spec.allium`)

## Summary

Add a single, always-visible, never-persisted instruction field to the frontend; thread its trimmed value (≤ 500 chars) through `dispatch_to_zone` into every model pass as a **trusted prompt slot** that sits between the zone's task instruction and the spec-022 anti-injection guard. Empty instruction ⇒ byte-identical prompts to today. Document content stays inside the DOKUMENT delimiters in all cases; deterministic machinery (039 scrub, 014 sweep, disclaimers) is instruction-blind by construction.

## Technical Context

**Language/Version**: Rust 1.7x (Tauri 2.x core) + TypeScript 5 / React 18 frontend

**Primary Dependencies**: existing only — no new crates, no new npm packages. `frame_prompt` (prompts/framing.rs), chunked dispatch (zones/sammanfatta.rs), Zustand (UI state), shadcn/Tailwind (field UI)

**Storage**: NONE — the instruction is in-memory React/Zustand state + per-job pinned values. SettingsSnapshot stays 2-field (spec 010 privacy invariant untouched)

**Testing**: cargo test (unit + wiremock integration), vitest (component/store/bridge), Playwright (e2e via mocked IPC bridge), /tla after browser tests (full track)

**Target Platform**: macOS desktop (Tauri 2, WKWebView)

**Project Type**: desktop-app (existing structure: `src/` React + `src-tauri/` Rust)

**Performance Goals**: zero added latency on the default path (string concat only); no extra model passes

**Constraints**: spec-038 context budget MUST keep holding with a max-length instruction (`worst_case_prompt_fits_generate_num_ctx_budget` extended by `MAX_INSTRUCTION_CHARS`); Principle I (localhost-only, no persistence, no logging of content)

**Scale/Scope**: 1 new React component + 1 tiny store; ~6 Rust files touched; 5 `frame_prompt` call sites threaded; 3-way help mirror; ~25–30 new tests

## Constitution Check

*GATE: evaluated pre-Phase-0 and re-checked post-design — PASS on all nine.*

| Principle | Verdict | Evidence |
|---|---|---|
| I. Privacy by Architecture | **PASS — strengthened surface** | Instruction travels only inside the existing localhost `/api/generate` body. No new outbound calls, no persistence (FR-007), no logging (enum-only diagnostics + Redacted wrap unchanged), no echo into sidecar (FR-016). |
| II. Zero-CLI Install | PASS | Pure UI + prompt assembly; no install-path change. |
| III. Local-Only Inference | PASS | Same `127.0.0.1:11434` client; `GENERATE_NUM_CTX` unchanged. |
| IV. Single-User Desktop App | PASS | In-memory state only; SettingsSnapshot untouched (2 fields). |
| V. Swedish-First UI, English-First Code | PASS | Field label/placeholder/help in Swedish (humanizer-gated); code/comments English. The prompt lead-in is model-facing Swedish (same register as combine.rs). |
| VI. Native macOS Feel | PASS | frontend-design skill gates the field UI; system font, subtle motion, design-system/MASTER.md. |
| VII. Bundled Sidecar | PASS | No sidecar lifecycle change. |
| VIII. Honest Failure States | PASS | No new failure states needed: the cap is preventive (input refuses past 500 + counter), not an error path. Field content survives failures (FR-015) so retry is honest. |
| IX. Open Source, Free | PASS | n/a |

**Violations**: none. Complexity Tracking: empty.

## Project Structure

### Documentation (this feature)

```text
specs/041-custom-instructions/
├── spec.md / spec.allium    # done (clarified + elicited)
├── plan.md                  # this file
├── research.md              # Phase 0
├── data-model.md            # Phase 1
├── quickstart.md            # Phase 1 (manual real-model verification)
├── contracts/
│   └── instruction-slot.md  # prompt-assembly + IPC contract
└── tasks.md                 # /speckit-tasks output
```

### Source Code (repository root)

```text
src-tauri/src/
├── prompts/
│   ├── framing.rs           # MODIFY: frame_prompt gains user_instruction: Option<&str>;
│   │                        #   new INSTRUCTION_LEAD_IN + MAX_INSTRUCTION_CHARS consts; tests
│   └── combine.rs           # MODIFY: budget test adds MAX_INSTRUCTION_CHARS to worst case
├── sidecar/commands.rs      # MODIFY: dispatch_to_zone gains instruction: Option<String>;
│                            #   normalize (trim → cap 500 chars → None-if-empty) here
├── zones/sammanfatta.rs     # MODIFY: handle_drop + dispatch + reduce_partials thread
│                            #   user_instruction through all 5 frame_prompt call sites
└── help/zone_help.rs        # MODIFY: chrome/general help mentions the field (mirror 1/3)

src/
├── components/
│   ├── InstructionField.tsx # NEW: input + counter + clear (frontend-design gated)
│   └── App.tsx              # MODIFY: mount field above grid; OS-drop path reads store
├── lib/
│   ├── instruction-store.ts # NEW: Zustand, NO persist middleware, trim helper
│   ├── tauri-bridge.ts      # MODIFY: dispatchToZone(zoneId, paths, instruction);
│   │                        #   pickFileForZone reads store at pick time
│   └── help-strings.ts      # MODIFY: mirror 3/3
└── lib/zone-help-strings.json (or src-tauri equivalent fixture)  # mirror 2/3

src-tauri/tests/
├── zone_pipeline_instruction.rs  # NEW: wiremock integration (all-passes, byte-identity,
│                                 #   generera, adversarial document)
└── common/mod.rs                 # MODIFY (additive): harness accepts an instruction

tests/e2e/
└── instruction.spec.ts      # NEW: Playwright functional + destructive scenarios
```

**Structure Decision**: existing two-tree desktop layout; no new directories beyond one component, one store, one integration test file, one e2e spec.

## Design decisions (Phase 0 summary — full rationale in research.md)

1. **Slot shape**: `frame_prompt(zone, system_prompt, document, user_instruction: Option<&str>)`. `None` reproduces the current format strings **character-for-character** (SC-002 is a format-string identity, provable by the existing framing tests passing unchanged plus new identity tests). `Some(instr)` inserts `\n\n{INSTRUCTION_LEAD_IN}\n{instr}` after the system prompt, before the guard (document zones) / before INSTR_BEGIN (Generera).
2. **Lead-in**: model-facing Swedish const `INSTRUCTION_LEAD_IN` ("Extra önskemål från användaren för den här körningen — följ dem så långt de inte strider mot uppgiften ovan:") — same register as combine.rs prompts; gives the model an explicit precedence rule (task > user instruction) so an instruction cannot redefine the zone into something else entirely, while still steering output.
3. **Normalization point**: the Tauri command (`dispatch_to_zone`) trims, caps at 500 **chars** (char-boundary safe), and maps empty→`None` — defense in depth against a bypassed frontend cap (destructive category 3). Frontend `maxLength=500` is the UX cap; Rust is the enforcement.
4. **Pinning**: instruction passes by value through `handle_drop` → `dispatch` (same mechanism as the spec-010 `model_id` pin). No DropJob struct change needed; immutability falls out of move semantics.
5. **Frontend state**: new tiny Zustand store (`instruction-store.ts`), no `persist` middleware (its absence IS FR-007 on the frontend, pinned by a vitest). Bridge reads the store at dispatch/pick time so both entry paths (OS drop in App.tsx, Välj fil in pickFileForZone) pin the same way.
6. **Budget**: extend `worst_case_prompt_fits_generate_num_ctx_budget` with `MAX_INSTRUCTION_CHARS + INSTRUCTION_LEAD_IN.len()`. Pre-verified: +~560 chars ≈ +140 tokens on a worst case currently ≤ 8192 with >300 tokens of slack — holds. If it ever fails, the test's own message governs the fix.
7. **Cross-side cap pin**: Rust `MAX_INSTRUCTION_CHARS = 500` + TS `MAX_INSTRUCTION_CHARS = 500`, each pinned by a test on its side asserting the literal 500 (the established drift-fixture pattern, scaled to one number).
8. **Reduce/condense naming**: `reduce_partials` already has `instruction`/`final_instruction` params (zone prompts); the new param is `user_instruction: Option<&str>` everywhere — no semantic collision.

## Phase 1 artifacts

- `data-model.md` — InstructionField (frontend), pinned per-job instruction (Rust), PromptAssembly slot order.
- `contracts/instruction-slot.md` — exact assembled-prompt grammar for all 4 shapes (document/generera × with/without instruction), the IPC parameter contract, and the normalization rules.
- `quickstart.md` — manual real-model verification (Meja's translate-keep-quotes case + privacy disk check).

## Verification mapping (what proves what)

| Requirement | Proof |
|---|---|
| FR-002/005, SC-001/005 | wiremock integration: every recorded `/api/generate` body for a 3-chunk Reduce run contains lead-in + instruction exactly once, above guard |
| FR-003, SC-002 | existing framing + chunked tests pass UNCHANGED; new `none_is_byte_identical` unit tests |
| FR-010, SC-003 | adversarial fixture: document containing fake lead-in/delimiters → fragments stay inside DOC markers (extend run_zone_pipeline_checked forbidden/markers) |
| FR-006 | move-semantics pin + e2e: edit field mid-(mocked)-run → invocation payload unchanged |
| FR-007/008, SC-004 | settings 2-field invariant tests (existing) + no-persist-middleware vitest + enum-only diagnostics (existing static invariant) + quickstart disk grep |
| FR-011 | budget test extension + component maxLength/counter vitest + Playwright paste-600-chars destructive |
| FR-012 | scrub/sweep/disclaimer call sites take no instruction param (compile-time) + anonymisera integration test with instruction set |
| FR-013/014, SC-006 | humanizer gate, 3-way help mirror drift tests, a11y vitest + Playwright keyboard scenario |
| FR-016 | integration: sidecar text lacks instruction/lead-in |
