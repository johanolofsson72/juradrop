// Spec 013 SC-005 → spec 036 — the constitution MUST be bumped to 1.2.0 with a
// Sync Impact Report entry documenting the twelve-zone expansion.

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
  it('is pinned to 1.2.0', () => {
    expect(constitution).toContain('**Version**: 1.2.0');
  });

  it('has a Sync Impact Report entry for the 1.1.0 -> 1.2.0 bump', () => {
    expect(constitution).toMatch(/Version change:\s*1\.1\.0\s*→\s*1\.2\.0/);
  });

  it('enumerates all twelve zones in the intro', () => {
    for (const zone of [
      'Plocka ut kontaktuppgifter',
      'Generera juridisk text',
      'Källförteckning',
      // Spec 036 — study-method zones.
      'Identifiera rättsfrågorna',
      'Strukturera (IRAC)',
      'Förklara begreppen',
    ]) {
      expect(constitution).toContain(zone);
    }
  });
});
