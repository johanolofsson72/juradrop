// Spec 041 — instruction store behavior + privacy pins (T006/T019).

import { beforeEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  MAX_INSTRUCTION_CHARS,
  instructionForDispatch,
  useInstructionStore,
} from '@/lib/instruction-store';

beforeEach(() => {
  useInstructionStore.getState().clear();
});

describe('instruction store', () => {
  it('starts empty (restart-empty semantics — nothing to restore)', () => {
    expect(useInstructionStore.getState().instruction).toBe('');
  });

  it('setInstruction stores the text', () => {
    useInstructionStore.getState().setInstruction('behåll citaten på svenska');
    expect(useInstructionStore.getState().instruction).toBe('behåll citaten på svenska');
  });

  it('clamps at exactly 500 chars', () => {
    useInstructionStore.getState().setInstruction('a'.repeat(600));
    expect(useInstructionStore.getState().instruction).toHaveLength(500);
  });

  it('clamp is code-point safe for multibyte text', () => {
    useInstructionStore.getState().setInstruction('å'.repeat(600));
    const stored = useInstructionStore.getState().instruction;
    expect(Array.from(stored)).toHaveLength(500);
    expect(stored).toMatch(/^å+$/);
  });

  it('exactly 500 chars passes untouched', () => {
    const exact = 'b'.repeat(500);
    useInstructionStore.getState().setInstruction(exact);
    expect(useInstructionStore.getState().instruction).toBe(exact);
  });

  it('clear() empties the field with no residue', () => {
    useInstructionStore.getState().setInstruction('hemlig strategi');
    useInstructionStore.getState().clear();
    expect(useInstructionStore.getState().instruction).toBe('');
  });

  it('C-9 (TS half) — the cap literal is 500, mirroring framing.rs', () => {
    expect(MAX_INSTRUCTION_CHARS).toBe(500);
  });
});

describe('instructionForDispatch', () => {
  it('empty field dispatches null (dormant)', () => {
    expect(instructionForDispatch()).toBeNull();
  });

  it('whitespace-only dispatches null', () => {
    useInstructionStore.getState().setInstruction('  \n\t ');
    expect(instructionForDispatch()).toBeNull();
  });

  it('non-empty dispatches the raw value (Rust owns trimming)', () => {
    useInstructionStore.getState().setInstruction(' fokusera på domskälen ');
    expect(instructionForDispatch()).toBe(' fokusera på domskälen ');
  });
});

describe('privacy pins (FR-007 frontend half)', () => {
  it('the store module imports no persistence middleware', () => {
    // Source-level assertion in the established drift-test style: the
    // absence of zustand persist IS the never-persisted guarantee.
    const here = dirname(fileURLToPath(import.meta.url));
    const src = readFileSync(resolve(here, '../lib/instruction-store.ts'), 'utf-8');
    // Match real usage, not the comments that document this rule:
    // a persist import/call or any storage API would both be caught.
    expect(src).not.toMatch(/zustand\/middleware/);
    expect(src).not.toMatch(/\bpersist\s*\(/);
    expect(src).not.toMatch(/localStorage|sessionStorage|indexedDB/);
  });
});
