// Spec 051 — session state for the startup card. The decision is made once
// per app session (the first time the zone grid shows); the prefs it
// persists make the NEXT launch show the next tip.

import { create } from 'zustand';
import { version as APP_VERSION } from '../../package.json';
import {
  decideCard,
  loadPrefs,
  savePrefs,
  type StartupCard,
  type StartupPrefs,
} from './startup-prefs';
import { RELEASE_NOTES, STARTUP_TIPS } from './startup-strings';
import { useStatusStore } from './status-store';

interface StartupStore {
  prefs: StartupPrefs;
  card: StartupCard;
  decided: boolean;
  dismissed: boolean;
  /** Decide this session's card. Idempotent — only the first call acts. */
  init: (runningVersion?: string) => void;
  nextTip: () => void;
  dismiss: () => void;
  setTipsEnabled: (on: boolean) => void;
}

export const useStartupStore = create<StartupStore>((set, get) => ({
  prefs: loadPrefs(),
  card: { kind: 'none' },
  decided: false,
  dismissed: false,
  init: (runningVersion = APP_VERSION) => {
    if (get().decided) return;
    const { card, next } = decideCard({
      prefs: loadPrefs(),
      runningVersion,
      // A fresh install consents during this session; an existing install
      // (the upgrade case) never does. The frontend's default status is
      // not_asked until the backend answers, so the wizard mounting is NOT
      // a reliable first-run signal — consent actually given is.
      freshInstall: useStatusStore.getState().consentGivenThisSession,
      tipCount: STARTUP_TIPS.length,
      notes: RELEASE_NOTES,
    });
    savePrefs(next);
    set({ card, prefs: next, decided: true });
  },
  nextTip: () => {
    const { card, prefs, dismissed } = get();
    if (card.kind !== 'tip' || dismissed) return;
    const index = (card.index + 1) % STARTUP_TIPS.length;
    // FR-003 — the tip just revealed is "seen": next launch starts after it.
    const next = { ...prefs, nextTip: (index + 1) % STARTUP_TIPS.length };
    savePrefs(next);
    set({ card: { kind: 'tip', index }, prefs: next });
  },
  dismiss: () => set({ dismissed: true }),
  setTipsEnabled: (on) => {
    const next = { ...get().prefs, tipsEnabled: on };
    savePrefs(next);
    set({ prefs: next });
  },
}));
