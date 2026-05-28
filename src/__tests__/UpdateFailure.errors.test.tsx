// Spec 007 / T008 — cross-language drift test for the six Swedish
// UpdateFailure strings.
//
// Mirrors spec 003's `SammanfattaZone.errors.test.tsx` pattern: both
// the Rust side (`src-tauri/tests/update_failure_strings.rs`) and this
// vitest side read `src-tauri/tests/fixtures/update-failure-strings.json`
// and assert byte-for-byte equality. If one side drifts, the suite fails.

import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { SWEDISH_UPDATE_FAILURE } from '../components/DropZone.update-errors';
import type { UpdateFailureVariant } from '@/lib/tauri-bridge';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.resolve(
  __dirname,
  '../../src-tauri/tests/fixtures/update-failure-strings.json',
);

type Fixture = Record<UpdateFailureVariant, string> & { _comment: string };

function loadFixture(): Fixture {
  const raw = fs.readFileSync(FIXTURE_PATH, 'utf-8');
  return JSON.parse(raw) as Fixture;
}

const ALL_VARIANTS: UpdateFailureVariant[] = [
  'no_network',
  'manifest_malformed',
  'signature_invalid',
  'download_interrupted',
  'install_failed',
  'unsupported_platform',
];

describe('UpdateFailure cross-language drift (T008)', () => {
  it('fixture has exactly 7 keys (6 variants + _comment)', () => {
    const f = loadFixture();
    expect(Object.keys(f)).toHaveLength(7);
    expect(f._comment).toBeTypeOf('string');
  });

  it('every variant matches the fixture byte-for-byte', () => {
    const f = loadFixture();
    for (const v of ALL_VARIANTS) {
      expect(SWEDISH_UPDATE_FAILURE[v]).toBe(f[v]);
    }
  });

  it.each(ALL_VARIANTS)('%s is non-empty and within 80 chars', (variant) => {
    const copy = SWEDISH_UPDATE_FAILURE[variant];
    expect(copy.length).toBeGreaterThan(0);
    expect([...copy].length).toBeLessThanOrEqual(80);
  });

  it('no variant contains the English word "error"', () => {
    for (const v of ALL_VARIANTS) {
      expect(SWEDISH_UPDATE_FAILURE[v].toLowerCase()).not.toContain('error');
    }
  });

  it('TS side declares every variant the Rust side declares', () => {
    const f = loadFixture();
    const tsKeys = Object.keys(SWEDISH_UPDATE_FAILURE).sort();
    const fixtureKeys = Object.keys(f)
      .filter((k) => k !== '_comment')
      .sort();
    expect(tsKeys).toEqual(fixtureKeys);
  });
});
