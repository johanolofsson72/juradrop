// Spec 042 — the privacy fact base (contract A, F1–F4).
//
// ONE source of truth for the local-only claims, rendered on four
// surfaces (badge, wizard, help entry, README). The strings here are
// humanizer-reviewed Swedish. Consistency rules are pinned by
// privacy-facts.test.ts:
//   - canonical vocabulary "din dator" (never "din Mac" in app copy)
//   - no surface claims the app never uses the internet (the model
//     download and the update check exist — honesty is the feature)
//   - EXACTLY two network uses. A third entry here means Principle I
//     changed; the failing length pin is the alarm, not a test to "fix".

/** F1+F2 — the badge line (one sentence, the whole claim).
 *  Amended 2026-06-05 (user directive from manual testing): name the
 *  local AI models explicitly — Meja's "it must be fetching from the
 *  internet" belief dies faster when the badge says WHO does the work.
 *  Deliberately NOT "all logik sköts av AI" — parsing/file-writing/the
 *  updater are not AI, and the 042 honesty rule forbids overclaiming. */
export const PRIVACY_BADGE_TEXT =
  'Dina dokument bearbetas av lokala AI-modeller på din dator och lämnar den aldrig.';

/** F2 — what never leaves the computer (the scope of the guarantee). */
export const PRIVACY_NEVER_LEAVES = ['dokument', 'instruktioner', 'resultat'] as const;

/** F3+F4 — the only two network uses, honestly named. */
export const PRIVACY_NETWORK_USES = [
  'AI-modellen laddas ner till din dator en gång, första gången du startar appen.',
  'Appen letar efter uppdateringar. Inget du har skrivit eller släppt skickas med.',
] as const;
