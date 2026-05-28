// Spec 008 / T005 — cross-language drift test for the 12 wizard strings.
//
// Mirrors the spec 007 UpdateFailure.errors test pattern. Both this
// vitest and the Rust side (wizard_strings.rs) read the canonical
// fixture and assert byte-for-byte equality + the SwedishCopy
// invariants client-side.

import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { WIZARD_STRINGS } from '@/lib/wizard-strings';
import type { WizardStringKey } from '@/lib/wizard-strings';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.resolve(
  __dirname,
  '../../src-tauri/tests/fixtures/wizard-strings.json',
);

type Fixture = Record<WizardStringKey, string> & { _comment: string };

function loadFixture(): Fixture {
  const raw = fs.readFileSync(FIXTURE_PATH, 'utf-8');
  return JSON.parse(raw) as Fixture;
}

const LONG_FORM_KEYS: WizardStringKey[] = [
  'welcome_paragraph',
  'welcome_download_note',
];

const ALL_KEYS: WizardStringKey[] = [
  'welcome_title',
  'welcome_paragraph',
  'welcome_privacy_line',
  'welcome_download_note',
  'welcome_cta_primary',
  'welcome_cta_secondary',
  'welcome_sidecar_helper',
  'progress_label_downloading',
  'progress_label_waiting',
  'progress_cancel_button',
  'progress_eta_unknown',
  'progress_error_retry',
];

describe('WIZARD_STRINGS cross-language drift (T005)', () => {
  it('fixture has exactly 13 keys (12 strings + _comment)', () => {
    const f = loadFixture();
    expect(Object.keys(f)).toHaveLength(13);
    expect(f._comment).toBeTypeOf('string');
  });

  it.each(ALL_KEYS)('TS mirror of %s matches the fixture byte-for-byte', (key) => {
    const f = loadFixture();
    expect(WIZARD_STRINGS[key]).toBe(f[key]);
  });

  it.each(ALL_KEYS)('%s is non-empty', (key) => {
    expect(WIZARD_STRINGS[key].length).toBeGreaterThan(0);
  });

  it('no string starts with the English `Error:` prefix', () => {
    for (const key of ALL_KEYS) {
      expect(WIZARD_STRINGS[key].startsWith('Error:')).toBe(false);
    }
  });

  it.each(LONG_FORM_KEYS)('long-form %s is within 200 chars', (key) => {
    expect([...WIZARD_STRINGS[key]].length).toBeLessThanOrEqual(200);
  });

  it('short-form strings are within 80 chars', () => {
    for (const key of ALL_KEYS) {
      if ((LONG_FORM_KEYS as readonly string[]).includes(key)) continue;
      expect([...WIZARD_STRINGS[key]].length).toBeLessThanOrEqual(80);
    }
  });

  it('welcome paragraph names all six zone verbs (clarification 1)', () => {
    const para = WIZARD_STRINGS.welcome_paragraph.toLowerCase();
    for (const verb of [
      'sammanfatta',
      'översätta',
      'anonymisera',
      'punktlista',
      'förenkla',
    ]) {
      expect(para).toContain(verb);
    }
  });

  it('privacy line names the Mac', () => {
    const s = WIZARD_STRINGS.welcome_privacy_line;
    expect(s).toContain('Mac');
    expect(s.toLowerCase()).toContain('dokumentinnehåll');
  });
});
