// Spec 027 — Zustand store for on-demand tier downloads.
//
// Backend-owned: the pull runs as a Rust task and streams progress on
// `juradrop://settings/tier-download`. This store only REFLECTS that state
// (subscribe + hydrate on mount), so a download survives the panel closing
// and reopening (FR-011). On completion it asks the settings store to
// re-read the pull-state so the row flips to a selectable radio (FR-005).

import { create } from 'zustand';

import { useSettingsStore } from './settings-store';
import type { ModelTier } from './settings-types';
import {
  cancelTierDownload,
  getTierDownloadState,
  startTierDownload,
  subscribeTierDownload,
  type TierDownloadEvent,
  type TierDownloadFailure,
} from './tauri-bridge';

/** A transient refusal from `start_tier_download` (not a stream failure):
 *  the AI wasn't ready, or another tier is already downloading. Shown on
 *  the row until the user retries. */
export interface TierStartRefusal {
  tier: ModelTier;
  reason: 'not_ready' | 'busy' | 'already_pulled';
}

interface TierDownloadStoreState {
  /** The active (downloading) or failed (error) tier, or null. At most one. */
  current: TierDownloadEvent | null;
  /** A transient start-refusal to surface on the clicked row. */
  refusal: TierStartRefusal | null;
  /** True while any tier is downloading — disables the other tier's button. */
  isAnyDownloading: () => boolean;
  applyEvent: (e: TierDownloadEvent) => void;
  start: (tier: ModelTier) => Promise<void>;
  cancel: (tier: ModelTier) => Promise<void>;
  /** Retry === start from the error state (FR-007, unlimited, user-initiated). */
  retry: (tier: ModelTier) => Promise<void>;
}

function mapRefusal(tier: ModelTier, err: unknown): TierStartRefusal {
  const msg = String(err);
  const reason: TierStartRefusal['reason'] = msg.includes('busy')
    ? 'busy'
    : msg.includes('already_pulled')
      ? 'already_pulled'
      : 'not_ready';
  return { tier, reason };
}

export const useTierDownloadStore = create<TierDownloadStoreState>((set, get) => ({
  current: null,
  refusal: null,
  isAnyDownloading: () => get().current?.phase === 'downloading',
  applyEvent: (e) => {
    if (e.phase === 'done') {
      // Completed — clear the slot and re-read pull-state so the row flips
      // to a selectable radio without a panel reload (FR-005).
      set({ current: null, refusal: null });
      void useSettingsStore.getState().refresh();
      return;
    }
    if (e.phase === 'cancelled') {
      // Clear the slot. Spec 027 /tla GAP-1: a cancel that races a
      // just-completed pull leaves the model genuinely on disk, so re-read
      // pull-state too — if it turns out the model IS installed, the row
      // corrects to a selectable radio immediately instead of waiting for
      // the next panel open.
      set({ current: null, refusal: null });
      void useSettingsStore.getState().refresh();
      return;
    }
    // downloading | error — reflect it; clear any stale refusal.
    set({ current: e, refusal: null });
  },
  start: async (tier) => {
    set({ refusal: null });
    try {
      await startTierDownload(tier);
    } catch (err) {
      set({ refusal: mapRefusal(tier, err) });
    }
  },
  cancel: async (tier) => {
    await cancelTierDownload(tier).catch(() => {});
  },
  retry: async (tier) => {
    set({ refusal: null });
    try {
      await startTierDownload(tier);
    } catch (err) {
      set({ refusal: mapRefusal(tier, err) });
    }
  },
}));

let subscribed = false;
/** Mount once (App.tsx). Hydrates current state + subscribes to the stream. */
export function ensureTierDownloadSubscription(): void {
  if (subscribed) return;
  subscribed = true;
  void getTierDownloadState()
    .then((state) => {
      if (state) useTierDownloadStore.getState().applyEvent(state);
    })
    .catch(() => {});
  void subscribeTierDownload((e) => useTierDownloadStore.getState().applyEvent(e));
}

export type { TierDownloadFailure };
