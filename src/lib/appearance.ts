// Spec 026 — appearance preference: Ljust / Mörkt / Följ systemet.
//
// The app moved from Tailwind `darkMode: 'media'` (pure OS-driven) to
// `darkMode: 'class'`. This module owns the one-way mapping
//   preference + OS state  ->  the `.dark` class on <html>.
// The default is `system`, which mirrors the OS — reproducing the old
// prefers-color-scheme behavior so nothing changes unless the user opts in.

export type Appearance = 'light' | 'dark' | 'system';

export const APPEARANCE_KEY = 'juradrop-appearance';

/** Read the persisted preference; defaults to `system` (and on any anomaly). */
export function getStoredAppearance(): Appearance {
  if (typeof window === 'undefined') return 'system';
  try {
    const v = window.localStorage?.getItem(APPEARANCE_KEY);
    if (v === 'light' || v === 'dark' || v === 'system') return v;
  } catch {
    // localStorage can throw in locked-down contexts; fall back to system.
  }
  return 'system';
}

/** Whether the OS currently prefers dark. */
export function systemPrefersDark(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-color-scheme: dark)').matches
  );
}

/** Resolve whether dark should be active for a preference + the current OS. */
export function resolveDark(pref: Appearance): boolean {
  return pref === 'dark' || (pref === 'system' && systemPrefersDark());
}

/** Apply the resolved theme by toggling `.dark` on the document root. */
export function applyAppearance(pref: Appearance): void {
  if (typeof document === 'undefined') return;
  document.documentElement.classList.toggle('dark', resolveDark(pref));
}

/** Persist the preference (best-effort) and apply it immediately. */
export function persistAppearance(pref: Appearance): void {
  if (typeof window !== 'undefined') {
    try {
      window.localStorage?.setItem(APPEARANCE_KEY, pref);
    } catch {
      // best-effort — a non-persisted choice still applies for this session.
    }
  }
  applyAppearance(pref);
}
