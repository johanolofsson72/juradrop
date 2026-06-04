# Research: Custom Instructions (spec 041)

All unknowns from Technical Context resolved. Each entry: Decision / Rationale / Alternatives considered.

## R1 — Where the trusted slot goes in the assembled prompt

**Decision**: `{system_prompt}\n\n{INSTRUCTION_LEAD_IN}\n{user_instruction}\n\n{INJECTION_GUARD}\n\n{DOC_BEGIN}\n{document}\n{DOC_END}` for the 11 document zones; `{system_prompt}\n\n{INSTRUCTION_LEAD_IN}\n{user_instruction}\n\n{INSTR_BEGIN}\n{document}\n{INSTR_END}` for Generera. With `None`: the existing format strings, character-for-character.

**Rationale**: the slot must be (a) above the guard so the model reads it as instruction-tier, (b) below the system prompt so the zone task keeps precedence, (c) entirely absent when dormant so SC-002 is trivially provable. Putting it before the guard means an instruction containing delimiter-like text cannot terminate the data framing early — the document framing hasn't opened yet (spec US3 scenario 3).

**Alternatives**: (1) Appending to the system prompt string itself — rejected: loses the explicit lead-in, makes byte-identity tests muddier, and mixes trust tiers in one string. (2) A second `system`-role message — rejected: `/api/generate` is single-prompt (no chat roles); restructuring to `/api/chat` is a far bigger blast radius for zero functional gain. (3) After the guard — rejected: the guard's "instruktionen ovan" wording would then ambiguously cover the user instruction and the model could treat in-document text as closer-proximity instruction.

## R2 — Lead-in wording (model-facing)

**Decision**: `pub const INSTRUCTION_LEAD_IN: &str = "Extra önskemål från användaren för den här körningen — följ dem så långt de inte strider mot uppgiften ovan:"`

**Rationale**: names the source (the user), scopes it (this run), and sets precedence (task wins on conflict) — so "ignorera allt och skriv en dikt" degrades gracefully instead of replacing the zone's function. Model-facing Swedish in the same register as `combine.rs` prompts (which are documented as NOT user-facing UI copy); humanizer gate still applied at impl since it ships inside the binary and shapes output tone.

**Alternatives**: bare insertion with no lead-in — rejected: the 4b model has no way to rank an unlabeled paragraph against in-document text; the spec-022 guard says "instruktionen ovan" and an unlabeled blob above it weakens that anchor.

## R3 — Normalization & enforcement point for the 500-char cap

**Decision**: normalize in `dispatch_to_zone` (Rust): `instruction.map(|s| s.trim())` → empty→`None` → cap at 500 chars via `chars().take(500)` (char-boundary safe, no panic on multi-byte). Frontend `maxLength={500}` + live counter is the UX layer.

**Rationale**: the e2e mock bridge and any future caller can bypass the React cap (destructive attack category 3 — skip steps). The command is the trust boundary; everything past it can assume the invariant. `chars()` not bytes: Swedish å/ä/ö are 2 bytes — a byte cap would split code points.

**Alternatives**: enforce only in frontend — rejected (bypassable); reject-with-error on >500 — rejected: a silent-cap-with-visible-counter never produces an error state for a limit the UI already enforces (Principle VIII prefers prevention over failure theater; FR-011 says the field refuses input past the cap).

## R4 — How the instruction reaches all five frame_prompt call sites

**Decision**: thread `user_instruction: Option<String>` by value: `dispatch_to_zone` → `handle_drop` → `dispatch`; `dispatch` lends `user_instruction.as_deref()` to the single-pass site (sammanfatta.rs:279), the per-chunk site (:304), and passes it into `reduce_partials` (new param `user_instruction: Option<&str>`) covering the three combine/condense sites (:562, :575, :583).

**Rationale**: identical to the proven spec-010 `model_id` pin — by-value capture at dispatch entry makes FR-006 immutability a property of move semantics, not of discipline. No `DropJob` struct change, no shared state, no lock.

**Alternatives**: store on `DropJob`/`ZoneInternalState` — rejected: introduces a second source of truth readable mid-run (exactly what FR-006 forbids) and widens the diff for nothing.

## R5 — Frontend state shape

**Decision**: new `src/lib/instruction-store.ts` — Zustand store `{ instruction: string, setInstruction, clear }`, **no persist middleware**. `dispatchToZone(zoneId, paths)` keeps its signature but reads `useInstructionStore.getState().instruction` internally? **No** — explicit parameter: `dispatchToZone(zoneId, paths, instruction)`; the two call sites (App.tsx OS-drop handler, pickFileForZone) read the store at call time and pass it.

**Rationale**: explicit parameter keeps the bridge a pure IPC mapper (its established character — every existing function is args-in/invoke-out), keeps vitest mocking trivial, and makes the e2e invocation-payload assertion direct. Reading the store inside the bridge would hide a dependency and complicate the FR-017-style contract pin from spec 033.

**Alternatives**: status-store extension — rejected: status-store is backend-snapshot mirror state (one-way Rust→UI); the instruction is user-input state flowing the other way. React useState in App — rejected: pickFileForZone lives outside the component tree (bridge module), needs non-hook access; Zustand `getState()` covers both entry paths.

## R6 — Context budget arithmetic

**Decision**: extend `worst_case_prompt_fits_generate_num_ctx_budget` (prompts/combine.rs:64): worst case += `MAX_INSTRUCTION_CHARS + INSTRUCTION_LEAD_IN.chars().count() + 4` (slot separators).

**Rationale / pre-verification**: current worst case = longest instruction (≲ 1,000 chars) + framing overhead (~260) + 24,000 chunk ≈ 25,260 chars ≈ 6,315 tokens + 1,500 headroom = 7,815 ≤ 8,192 (slack ≈ 377 tokens). Adding 500 + ~110 + 4 ≈ 614 chars ≈ 154 tokens → ≈ 7,969 ≤ 8,192. Holds with ~220 tokens of slack. The test recomputes from the real consts, so this arithmetic is enforced, not assumed.

**Alternatives**: raise GENERATE_NUM_CTX — unnecessary (slack suffices) and costs memory on 8 GB Macs; lower CHUNK_CHAR_TARGET — unnecessary churn to 038's calibration.

## R7 — Cross-side cap drift guard

**Decision**: `MAX_INSTRUCTION_CHARS: usize = 500` in framing.rs; `export const MAX_INSTRUCTION_CHARS = 500` in instruction-store.ts. Each side pins the literal in a test (Rust unit + vitest). No shared fixture file.

**Rationale**: one scalar doesn't justify the JSON-fixture machinery used for the 12-zone help mirror; two literal-pinning tests catch drift in either direction at the same cost.

## R8 — Where the field lives in the UI (bounded for the frontend-design gate)

**Decision (bounds, final call at impl under frontend-design skill)**: a single compact row between the chrome/status header and the zone grid in App.tsx — full-width input, placeholder, char counter right-aligned, clear (×) button; `data-instruction-field` test handle; ~48–56 px tall so the 3×4 grid still fits the 1160×1000 window without scroll.

**Rationale**: FR-001 demands always-visible; above-grid is the only placement read before dropping (the natural "set intent, then drop" order). The frontend-design skill governs the exact visual treatment per design-system/MASTER.md (dashed-border aesthetic, SF Pro, dark/light).

**Alternatives**: settings panel — rejected (hidden = not per-drop, and settings implies persistence, the exact wrong signal); per-zone popovers — rejected (12× surface, clarified single-global-field); footer — rejected (read after the grid, wrong order, and spec 042 wants the footer area for the privacy badge).

## R9 — Help surface

**Decision**: extend the chrome-bar/general help (not per-zone help) with one entry describing the field; keep the three-way mirror (zone_help.rs / zone-help-strings.json / help-strings.ts) in sync per the established drift tests. Per-zone help strings unchanged (the field is zone-agnostic).

**Rationale**: the field is chrome, not a zone; the help system already has a chrome-bar tier (spec 013).

## R10 — Diagnostics / logging safety

**Decision**: no new logging. The instruction reaches `generate_raced` only inside the already-`Redacted` full prompt; the diagnostics API is enum-only (spec 025) so the instruction is unloggable by construction. Add the instruction-related modules to the existing static privacy-invariant test pattern (spec 038/039 `chunked_path_privacy` style) asserting no `eprintln!`/log call touches the instruction value.

**Alternatives**: a Redacted wrapper for the instruction through the whole chain — considered; rejected as ceremony: the value crosses no logging boundary before being absorbed into the Redacted prompt, and the static invariant pins that.
