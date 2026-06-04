// Spec 013 FR-021 / FR-016a — cross-language drift test (TS side).
//
// Asserts ZONE_HELP_STRINGS matches the JSON fixture byte-for-byte, for
// all 12 zones, short + long. The Rust counterpart
// (src-tauri/tests/help_strings_drift.rs) asserts Rust ↔ JSON, so the
// three stay locked from both directions.

import { describe, expect, it } from 'vitest';

import fixture from '../../src-tauri/tests/fixtures/zone-help-strings.json';
import { INSTRUCTION_HELP, PRIVACY_HELP, ZONE_HELP_STRINGS } from '@/lib/help-strings';
import { ZONE_ORDER } from '@/components/DropZone.identity';

type Entry = { short: string; long: string };
const fixtureMap = fixture as unknown as Record<string, Entry | string>;

describe('zone help strings cross-language drift', () => {
  it('every TS zone entry matches the fixture (short + long)', () => {
    for (const [slug, help] of Object.entries(ZONE_HELP_STRINGS)) {
      const fx = fixtureMap[slug] as Entry | undefined;
      expect(fx, `fixture missing zone '${slug}'`).toBeDefined();
      expect(fx!.short, `${slug} short drift`).toBe(help.short);
      expect(fx!.long, `${slug} long drift`).toBe(help.long);
    }
  });

  it('every fixture zone (except _comment) has a matching TS entry', () => {
    for (const key of Object.keys(fixtureMap)) {
      if (key.startsWith('_')) continue;
      expect(
        ZONE_HELP_STRINGS[key as keyof typeof ZONE_HELP_STRINGS],
        `TS missing zone '${key}'`,
      ).toBeDefined();
    }
  });

  it('covers all 12 zones in ZONE_ORDER', () => {
    expect(Object.keys(ZONE_HELP_STRINGS).sort()).toEqual([...ZONE_ORDER].sort());
  });

  it('respects char budgets (short <= 80, long <= 300)', () => {
    for (const [slug, help] of Object.entries(ZONE_HELP_STRINGS)) {
      expect(help.short.length, `${slug} short over budget`).toBeLessThanOrEqual(80);
      expect(help.long.length, `${slug} long over budget`).toBeLessThanOrEqual(300);
    }
  });

  // Spec 041 — the chrome-level instruction-field entry (underscore-
  // prefixed, skipped by the per-zone iterations) pinned explicitly:
  // TS ↔ JSON. The Rust side pins Rust ↔ JSON.
  it('instruction help matches the fixture (title + body)', () => {
    const fx = fixtureMap['_instruction_help'] as
      | { title: string; body: string }
      | undefined;
    expect(fx, 'fixture missing _instruction_help').toBeDefined();
    expect(fx!.title).toBe(INSTRUCTION_HELP.title);
    expect(fx!.body).toBe(INSTRUCTION_HELP.body);
  });

  // Spec 042 — the chrome-level privacy entry, same discipline, plus
  // the P-5/P-7 content rules (canonical vocabulary, both network uses).
  it('privacy help matches the fixture and names both network uses', () => {
    const fx = fixtureMap['_privacy_help'] as
      | { title: string; body: string }
      | undefined;
    expect(fx, 'fixture missing _privacy_help').toBeDefined();
    expect(fx!.title).toBe(PRIVACY_HELP.title);
    expect(fx!.body).toBe(PRIVACY_HELP.body);
    expect(PRIVACY_HELP.body).toContain('din dator');
    expect(PRIVACY_HELP.body.toLowerCase()).toContain('modell');
    expect(PRIVACY_HELP.body.toLowerCase()).toContain('uppdater');
    expect(PRIVACY_HELP.body).not.toMatch(/din Mac/);
  });
});
