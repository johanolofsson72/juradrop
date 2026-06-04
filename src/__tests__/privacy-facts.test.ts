// Spec 042 T003 — fact-base pins (contract P-6/P-7/P-8).

import { describe, expect, it } from 'vitest';
import {
  PRIVACY_BADGE_TEXT,
  PRIVACY_NETWORK_USES,
  PRIVACY_NEVER_LEAVES,
} from '@/lib/privacy-facts';

const ALL_FACT_STRINGS = [
  PRIVACY_BADGE_TEXT,
  ...PRIVACY_NEVER_LEAVES,
  ...PRIVACY_NETWORK_USES,
];

describe('privacy fact base', () => {
  it('P-7 — canonical vocabulary: "din dator", never "din Mac"', () => {
    expect(PRIVACY_BADGE_TEXT).toContain('din dator');
    for (const s of ALL_FACT_STRINGS) {
      expect(s, `"${s}" uses the non-canonical "din Mac"`).not.toMatch(/din Mac/);
    }
  });

  it('P-6 — no overclaim: nothing states the app never uses the internet', () => {
    // Overclaim patterns: an absolute app-level no-internet claim.
    // (The wizard's "efter det fungerar allt utan nät" is a SCOPED,
    // true offline-after claim and lives in wizard-strings, allowlisted
    // in WizardCopy tests — not here.)
    for (const s of ALL_FACT_STRINGS) {
      expect(s, `overclaim in "${s}"`).not.toMatch(/aldrig.*internet/i);
      expect(s, `overclaim in "${s}"`).not.toMatch(/ingen internetanslutning/i);
      expect(s, `overclaim in "${s}"`).not.toMatch(/utan internet(?!å)/i);
    }
  });

  it('P-8 — EXACTLY two network uses (Principle I alarm)', () => {
    // If this fails because a third entry appeared: that is a
    // constitutional amendment conversation, not a test update.
    expect(PRIVACY_NETWORK_USES).toHaveLength(2);
    expect(PRIVACY_NETWORK_USES[0]).toMatch(/modell/i);
    expect(PRIVACY_NETWORK_USES[1]).toMatch(/uppdater/i);
  });

  it('F2 — the never-leaves scope covers documents, instructions, results', () => {
    expect([...PRIVACY_NEVER_LEAVES]).toEqual(['dokument', 'instruktioner', 'resultat']);
  });

  it('the badge claim is scoped to user content, not the app', () => {
    // Subject = the documents (what Meja worried about), not "appen".
    expect(PRIVACY_BADGE_TEXT).toMatch(/^Dina dokument/);
    expect(PRIVACY_BADGE_TEXT.endsWith('.')).toBe(true);
  });
});
