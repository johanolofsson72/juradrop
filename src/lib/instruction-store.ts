// Spec 041 — per-drop custom instruction (FR-001/FR-007).
//
// In-memory ONLY. This store deliberately has NO persist middleware and
// must never gain one: the instruction is user content with the same
// confidentiality as the dropped document (Principle I). Absence of
// persistence IS the privacy guarantee — restart always starts empty,
// nothing ever touches disk. Pinned by instruction-store.test.ts.
//
// User-input state flowing UI→Rust, which is why it does not live in
// status-store (a one-way mirror of backend ZoneSnapshots, Rust→UI).

import { create } from 'zustand';

/** Hard cap in CHARS — mirrors `MAX_INSTRUCTION_CHARS` in
 *  src-tauri/src/prompts/framing.rs. Both sides pin the literal 500 in
 *  a test so drift fails CI (contract C-9). */
export const MAX_INSTRUCTION_CHARS = 500;

interface InstructionStore {
  /** Raw field contents — capped, untrimmed (Rust trims at the boundary). */
  instruction: string;
  setInstruction: (next: string) => void;
  clear: () => void;
}

export const useInstructionStore = create<InstructionStore>((set) => ({
  instruction: '',
  // Clamp defensively even though the input carries maxLength=500 —
  // programmatic sets (paste interception quirks, tests) hit this path.
  setInstruction: (next) =>
    set({ instruction: Array.from(next).slice(0, MAX_INSTRUCTION_CHARS).join('') }),
  clear: () => set({ instruction: '' }),
}));

/** The value to send across IPC at drop/pick time: trimmed-empty becomes
 *  null (Rust normalizes again — this just keeps payloads clean). */
export function instructionForDispatch(): string | null {
  const raw = useInstructionStore.getState().instruction;
  return raw.trim() === '' ? null : raw;
}
