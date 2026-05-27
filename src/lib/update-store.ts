// Spec 007 / T012 — Zustand slice mirroring UpdateStatus.
//
// Subscribes to the juradrop://update-status Tauri event at module
// load time (idempotent — the bridge layer ensures one listener per
// app instance). React components read from the slice via the hook.

import { create } from 'zustand';

import type { UpdateStatus } from './tauri-bridge';
import { subscribeUpdateStatus } from './tauri-bridge';

interface UpdateStoreState {
  status: UpdateStatus;
  setStatus: (s: UpdateStatus) => void;
}

export const useUpdateStore = create<UpdateStoreState>((set) => ({
  status: { state: 'unknown' },
  setStatus: (s) => set({ status: s }),
}));

// Singleton subscription: registered once on first import. Bridge
// layer guarantees a single listener — if this module is hot-reloaded
// in dev, the old listener is leaked but harmless.
let subscribed = false;
export function ensureUpdateStatusSubscription(): void {
  if (subscribed) return;
  subscribed = true;
  void subscribeUpdateStatus((status) => {
    useUpdateStore.getState().setStatus(status);
  });
}
