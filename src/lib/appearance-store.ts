// Spec 026 — reactive appearance preference shared by the picker (writes)
// and the App-level theme controller (applies `.dark` + watches the OS).

import { create } from 'zustand';
import { type Appearance, getStoredAppearance, persistAppearance } from './appearance';

interface AppearanceStore {
  appearance: Appearance;
  /** Persist + apply the new preference. */
  setAppearance: (pref: Appearance) => void;
}

export const useAppearanceStore = create<AppearanceStore>((set) => ({
  appearance: getStoredAppearance(),
  setAppearance: (pref) => {
    persistAppearance(pref);
    set({ appearance: pref });
  },
}));
