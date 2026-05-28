// Spec 013 SC-005 — the constitution MUST be bumped to 1.1.0 with a
// Sync Impact Report entry documenting the nine-zone expansion.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const constitution = readFileSync(
  resolve(here, '../../.specify/memory/constitution.md'),
  'utf-8',
);

describe('constitution version (SC-005)', () => {
  it('is pinned to 1.1.0', () => {
    expect(constitution).toContain('**Version**: 1.1.0');
  });

  it('has a Sync Impact Report entry for the 1.0.0 -> 1.1.0 bump', () => {
    expect(constitution).toMatch(/Version change:\s*1\.0\.0\s*→\s*1\.1\.0/);
  });

  it('enumerates all nine zones in the intro', () => {
    for (const zone of [
      'Plocka ut kontaktuppgifter',
      'Generera juridisk text',
      'Källförteckning',
    ]) {
      expect(constitution).toContain(zone);
    }
  });
});
