# Data Model: Custom Instructions (spec 041)

No persisted entities. Three in-memory shapes, one per layer.

## 1. InstructionField (frontend, Zustand)

```ts
// src/lib/instruction-store.ts — NO persist middleware (FR-007 frontend half)
interface InstructionStore {
  instruction: string;            // raw field contents, UI-capped at 500 chars
  setInstruction(next: string): void;  // clamps to MAX_INSTRUCTION_CHARS
  clear(): void;                  // one-action clear (FR-013)
}
export const MAX_INSTRUCTION_CHARS = 500;
```

- Lifecycle: created empty at app boot (FR — restart starts empty falls out of no-persistence), survives run failures/cancels untouched (FR-015 — nothing in the run path writes to it).
- Derived UI values: `charCount = instruction.length` (counter), `atCap = charCount >= 500`.
- NOT in status-store: status-store mirrors backend snapshots (Rust→UI); this is user-input state (UI→Rust).

## 2. Pinned per-run instruction (Rust, by-value)

```rust
// crosses IPC in dispatch_to_zone, normalized AT the boundary:
//   trim → cap chars().take(MAX_INSTRUCTION_CHARS) → empty ⇒ None
user_instruction: Option<String>
```

- Flow: `dispatch_to_zone(…, instruction: Option<String>)` → normalize → `handle_drop(…, user_instruction)` → `dispatch(…, user_instruction)` → `as_deref()` at each `frame_prompt` site and into `reduce_partials`.
- Immutability (FR-006): by-value move at dispatch entry — the same pin mechanism as spec-010 `model_id`. No struct field, no lock, nothing for a mid-run edit to reach.
- `None` semantics: dormant — the prompt slot is ABSENT (not empty-string), guaranteeing byte-identity (FR-003).

## 3. PromptAssembly (Rust, pure function output)

```rust
// src-tauri/src/prompts/framing.rs
pub const MAX_INSTRUCTION_CHARS: usize = 500;
pub const INSTRUCTION_LEAD_IN: &str = "Extra önskemål från användaren för den här körningen — följ dem så långt de inte strider mot uppgiften ovan:";

pub fn frame_prompt(
    zone: ZoneId,
    system_prompt: &str,
    document: &str,
    user_instruction: Option<&str>,   // NEW — pre-normalized, never empty Some("")
) -> String
```

Slot order (the contract — see contracts/instruction-slot.md for the exact grammar):

| # | Slot | Trust | Present when |
|---|---|---|---|
| 1 | system/task prompt (zone, combine, or condense) | trusted | always |
| 2 | `INSTRUCTION_LEAD_IN` + user instruction | trusted | `Some(_)` |
| 3 | `INJECTION_GUARD` | — | all zones except Generera |
| 4 | `DOC_BEGIN … DOC_END` (document zones) / `INSTR_BEGIN … INSTR_END` (Generera) | UNTRUSTED content inside | always |

Invariants carried (from spec.allium):

- **DocumentStaysData**: document content appears only inside slot 4 — slots 1–3 are compile-time constants + the pinned instruction.
- **AllPassesCarryInstruction**: all 5 call sites receive the same `Option<&str>` for one run.
- **DormantMeansAbsent**: `None` ⇒ output equals the pre-041 format strings char-for-char.
- **ContextBudgetHoldsAtCap**: budget test sums slot 1 (max) + lead-in + 500 + framing + CHUNK_CHAR_TARGET ≤ GENERATE_NUM_CTX × 4 chars/token − headroom.

## State transitions

None added. The zone state machine (idle → processing → success/error, spec 003) is untouched; the instruction is payload, not state. DropJob status transitions in spec.allium restate the existing machine for TLA grounding only.

## Relationships

```
InstructionField (UI) --read at drop/pick time--> dispatchToZone(zoneId, paths, instruction)
                                                       │ IPC
dispatch_to_zone --normalize--> user_instruction: Option<String>
                                                       │ move
handle_drop → dispatch → { single-pass | per-chunk ×N | combine/condense ×M } → frame_prompt(…, Some/None)
```
