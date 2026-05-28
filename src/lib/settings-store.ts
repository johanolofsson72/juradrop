// Spec 010 / T012 — Zustand store mirroring SettingsSnapshot and
// TierPullState. Mounted once at App.tsx via `ensureSettingsSubscription`.
//
// Reads the persisted snapshot via `get_settings` at first mount and
// subscribes to `juradrop://status` so the Smart-tier pull state
// follows the spec 008 wizard's existing signal.

import { create } from 'zustand';

import type {
  SettingsSnapshot,
  TierPullState,
} from './settings-types';
import {
  getSettings,
  getTierPullState,
  setModelTier as invokeSetModelTier,
} from './tauri-bridge';
import type { ModelTier } from './settings-types';

interface SettingsStoreState {
  snapshot: SettingsSnapshot | null;
  pullState: TierPullState | null;
  setSnapshot: (s: SettingsSnapshot) => void;
  setPullState: (p: TierPullState) => void;
  /**
   * Optimistic tier switch — updates the local snapshot before the
   * Rust persist round-trip completes so the radio UI feels instant.
   * On error, reverts.
   */
  selectTier: (tier: ModelTier) => Promise<void>;
  /** Re-fetch from Rust. Used after pull events and after first mount. */
  refresh: () => Promise<void>;
}

export const useSettingsStore = create<SettingsStoreState>((set, get) => ({
  snapshot: null,
  pullState: null,
  setSnapshot: (s) => set({ snapshot: s }),
  setPullState: (p) => set({ pullState: p }),
  selectTier: async (tier) => {
    const previous = get().snapshot;
    if (previous) {
      set({ snapshot: { ...previous, model_tier: tier } });
    }
    try {
      await invokeSetModelTier(tier);
    } catch (e) {
      if (previous) set({ snapshot: previous });
      throw e;
    }
  },
  refresh: async () => {
    const [snap, pull] = await Promise.all([
      getSettings().catch(() => null),
      getTierPullState().catch(() => null),
    ]);
    if (snap) set({ snapshot: snap });
    if (pull) set({ pullState: pull });
  },
}));

let subscribed = false;
export function ensureSettingsSubscription(): void {
  if (subscribed) return;
  subscribed = true;
  // First mount: fetch initial state.
  void useSettingsStore.getState().refresh();
  // No need to subscribe to juradrop://status here — components that
  // care about pull state call refresh() at the right moments (e.g.
  // after a Ladda ned completes, the panel re-renders and re-reads).
}
