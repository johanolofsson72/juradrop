// Spec 052 — release gate. A version must not ship without its in-app
// "Nytt i versionen" notes (spec 051), and the user guide must keep naming
// every zone the app actually has.

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

import { ZONE_IDENTITIES } from '@/components/DropZone.identity';
import { RELEASE_NOTES } from '@/lib/startup-strings';
import { version } from '../../package.json';

describe('release gate (spec 052)', () => {
  it('ships in-app release notes for the version being built', () => {
    expect(RELEASE_NOTES[version]?.length ?? 0).toBeGreaterThan(0);
  });

  it('the Swedish user guide names every zone', () => {
    const guide = readFileSync(path.resolve(__dirname, '../../docs/anvandarguide.md'), 'utf8');
    for (const identity of Object.values(ZONE_IDENTITIES)) {
      expect(guide).toContain(`**${identity.title}**`);
    }
  });
});
