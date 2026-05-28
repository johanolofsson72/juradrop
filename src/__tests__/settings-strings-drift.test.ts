// Spec 010 / T047 — cross-language drift test (TS side).
//
// Asserts that the SETTINGS_PANEL_STRINGS constant matches the JSON
// fixture byte-for-byte. Adding a string on one side without the
// other fails CI from both directions (Rust counterpart in
// src-tauri/tests/settings_strings_drift.rs).

import { describe, expect, it } from 'vitest';

import fixture from '../../src-tauri/tests/fixtures/settings-panel-strings.json';
import {
  SETTINGS_PANEL_STRINGS,
  type SettingsPanelStringKey,
} from '@/lib/settings-panel-strings';

describe('SettingsPanel cross-language strings drift', () => {
  it('every TS key has a matching fixture entry with the same value', () => {
    const fixtureMap = fixture as unknown as Record<string, string>;
    for (const [key, value] of Object.entries(SETTINGS_PANEL_STRINGS)) {
      expect(fixtureMap[key], `fixture missing key '${key}'`).toBe(value);
    }
  });

  it('every fixture key (except _comment) has a matching TS entry', () => {
    const fixtureMap = fixture as unknown as Record<string, string>;
    for (const key of Object.keys(fixtureMap)) {
      if (key === '_comment') continue;
      const tsValue = SETTINGS_PANEL_STRINGS[key as SettingsPanelStringKey];
      expect(tsValue, `TS missing key '${key}'`).toBe(fixtureMap[key]);
    }
  });

  it('tier helpers are pinned to Clarification Q3 and fit the 80-char cap', () => {
    expect(SETTINGS_PANEL_STRINGS.tier_snabb_helper).toBe(
      'Snabbast och minst. Bra för korta texter.',
    );
    expect(SETTINGS_PANEL_STRINGS.tier_smart_helper).toBe(
      'Standardvalet. Bra balans mellan fart och kvalitet.',
    );
    expect(SETTINGS_PANEL_STRINGS.tier_stor_helper).toBe(
      'Bästa kvaliteten. Tar längre tid och mer plats på disken.',
    );
    for (const s of [
      SETTINGS_PANEL_STRINGS.tier_snabb_helper,
      SETTINGS_PANEL_STRINGS.tier_smart_helper,
      SETTINGS_PANEL_STRINGS.tier_stor_helper,
    ]) {
      expect([...s].length).toBeLessThanOrEqual(80);
    }
  });
});
