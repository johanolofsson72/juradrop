import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ZONE_IDENTITIES,
  ZONE_ORDER,
  type ZoneIdentity,
} from '../components/DropZone.identity';
import type { ZoneId } from '@/lib/tauri-bridge';

// Spec 004 / T034 + T035 — TS-side cross-language identity drift
// assertion. Reads the same fixture the Rust side reads
// (src-tauri/tests/fixtures/zone-identity.json) and verifies
// ZONE_IDENTITIES matches byte-for-byte. If a future PR drifts one
// side of the boundary, one of these two tests fails loudly.

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.resolve(
  __dirname,
  '../../src-tauri/tests/fixtures/zone-identity.json',
);

interface FixtureRow {
  slug: string;
  title: string;
  hint_copy: string;
  sidecar_suffix: string;
  processing_hint: string;
  has_disclaimer: boolean;
}

interface Fixture {
  [zoneId: string]: FixtureRow | string;
}

function loadFixture(): Fixture {
  const raw = fs.readFileSync(FIXTURE_PATH, 'utf-8');
  return JSON.parse(raw) as Fixture;
}

const EXPECTED_ZONE_IDS: ZoneId[] = [
  'sammanfatta',
  'tillengelska',
  'tillsvenska',
  'punktlista',
  'anonymisera',
  'forenkla',
];

describe('DropZone identity table', () => {
  it('exposes exactly the six ZoneId variants — no extras', () => {
    const keys = Object.keys(ZONE_IDENTITIES).sort();
    const expected = [...EXPECTED_ZONE_IDS].sort();
    expect(keys).toEqual(expected);
  });

  it('ZONE_ORDER lists every zone exactly once in left-to-right reading order', () => {
    expect(ZONE_ORDER).toHaveLength(EXPECTED_ZONE_IDS.length);
    // Row 1 = sammanfatta, tillengelska, tillsvenska
    // Row 2 = punktlista, anonymisera, forenkla
    expect(ZONE_ORDER[0]).toBe('sammanfatta');
    expect(ZONE_ORDER[1]).toBe('tillengelska');
    expect(ZONE_ORDER[2]).toBe('tillsvenska');
    expect(ZONE_ORDER[3]).toBe('punktlista');
    expect(ZONE_ORDER[4]).toBe('anonymisera');
    expect(ZONE_ORDER[5]).toBe('forenkla');
  });

  it('every entry has every required field', () => {
    EXPECTED_ZONE_IDS.forEach((id) => {
      const entry: ZoneIdentity = ZONE_IDENTITIES[id];
      expect(entry.slug).toBe(id);
      expect(entry.title.length).toBeGreaterThan(0);
      expect(entry.hintCopy.length).toBeGreaterThan(0);
      expect(entry.sidecarSuffix.length).toBeGreaterThan(0);
      expect(entry.processingHint.length).toBeGreaterThan(0);
      expect(typeof entry.hasDisclaimer).toBe('boolean');
    });
  });

  it('only Anonymisera and Förenkla carry the FR-013/014 disclaimer flag', () => {
    EXPECTED_ZONE_IDS.forEach((id) => {
      const expected = id === 'anonymisera' || id === 'forenkla';
      expect(ZONE_IDENTITIES[id].hasDisclaimer).toBe(expected);
    });
  });

  it('Anonymisera sidecar suffix is the past-participle "anonymiserad"', () => {
    expect(ZONE_IDENTITIES.anonymisera.sidecarSuffix).toBe('anonymiserad');
  });

  it('every Swedish copy field is ≤ 80 characters — SwedishCopy invariant', () => {
    EXPECTED_ZONE_IDS.forEach((id) => {
      const entry = ZONE_IDENTITIES[id];
      expect(entry.title.length).toBeLessThanOrEqual(80);
      expect(entry.hintCopy.length).toBeLessThanOrEqual(80);
      expect(entry.processingHint.length).toBeLessThanOrEqual(80);
    });
  });

  it('no Swedish copy starts with "Error:" — NoEnglishPrefix invariant', () => {
    EXPECTED_ZONE_IDS.forEach((id) => {
      const entry = ZONE_IDENTITIES[id];
      expect(entry.title.startsWith('Error:')).toBe(false);
      expect(entry.hintCopy.startsWith('Error:')).toBe(false);
      expect(entry.processingHint.startsWith('Error:')).toBe(false);
    });
  });
});

describe('Cross-language identity drift (T035)', () => {
  // Loads the same JSON fixture the Rust drift test reads. Any change
  // to a Rust ZoneId::associated() function or a TS ZONE_IDENTITIES
  // entry that doesn't also update the fixture fails one of the two
  // sides — forcing the human to keep all three in sync.

  it('fixture file is on disk where both languages expect it', () => {
    expect(fs.existsSync(FIXTURE_PATH)).toBe(true);
  });

  it('every TS ZONE_IDENTITIES entry matches the fixture byte-for-byte', () => {
    const fixture = loadFixture();
    EXPECTED_ZONE_IDS.forEach((id) => {
      const entry = ZONE_IDENTITIES[id];
      const expected = fixture[id] as FixtureRow | undefined;
      expect(expected).toBeDefined();
      if (!expected) return; // type narrowing
      expect(entry.slug).toBe(expected.slug);
      expect(entry.title).toBe(expected.title);
      expect(entry.hintCopy).toBe(expected.hint_copy);
      expect(entry.sidecarSuffix).toBe(expected.sidecar_suffix);
      expect(entry.processingHint).toBe(expected.processing_hint);
      expect(entry.hasDisclaimer).toBe(expected.has_disclaimer);
    });
  });

  it('fixture has exactly 6 ZoneIdentity rows + 1 _comment field', () => {
    const fixture = loadFixture();
    const keys = Object.keys(fixture).sort();
    expect(keys).toEqual([
      '_comment',
      'anonymisera',
      'forenkla',
      'punktlista',
      'sammanfatta',
      'tillengelska',
      'tillsvenska',
    ]);
  });
});
