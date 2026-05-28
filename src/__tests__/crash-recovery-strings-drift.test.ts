// Spec 011 / T012 — cross-language drift test for the crash-recovery
// Swedish copy fixture.
//
// Asserts the TS-side mirror of the pinned strings matches the
// fixture byte-for-byte, both fixture strings fit the 80-char cap,
// AND the duplicated `model_error` value matches the existing
// zone-error-strings.json fixture (spec 003 lineage).

import { describe, expect, it } from 'vitest';

import crashFixture from '../../src-tauri/tests/fixtures/crash-recovery-strings.json';
import zoneErrorFixture from '../../src-tauri/tests/fixtures/zone-error-strings.json';

const PINNED_FEL_OVANTAT = 'AI-motorn svarar inte. Starta om JuraDrop.';
const PINNED_MODEL_ERROR = 'AI-motorn svarade inte — försök igen';

describe('Spec 011 crash-recovery strings drift', () => {
  it('fixture fel_ovantat matches the pinned constant', () => {
    expect((crashFixture as Record<string, string>).fel_ovantat).toBe(PINNED_FEL_OVANTAT);
  });

  it('fixture model_error matches the pinned constant', () => {
    expect((crashFixture as Record<string, string>).model_error).toBe(PINNED_MODEL_ERROR);
  });

  it('both fixture strings fit the 80-char cap', () => {
    const fel = (crashFixture as Record<string, string>).fel_ovantat ?? '';
    const model = (crashFixture as Record<string, string>).model_error ?? '';
    expect([...fel].length).toBeLessThanOrEqual(80);
    expect([...model].length).toBeLessThanOrEqual(80);
  });

  it('cross-fixture: model_error matches zone-error-strings.json (no drift between spec 003 + spec 011 fixtures)', () => {
    const crashModelError = (crashFixture as Record<string, string>).model_error;
    const zoneModelError = (zoneErrorFixture as Record<string, string>).model_error;
    expect(crashModelError).toBe(zoneModelError);
  });

  it('fixture has exactly 3 keys (_comment, fel_ovantat, model_error) — no scope creep', () => {
    const keys = Object.keys(crashFixture as Record<string, string>).sort();
    expect(keys).toEqual(['_comment', 'fel_ovantat', 'model_error']);
  });

  it('fel_ovantat contains the recovery instruction (FR-009 — no Swedish error without a way out)', () => {
    expect((crashFixture as Record<string, string>).fel_ovantat).toContain('Starta om JuraDrop');
  });
});
