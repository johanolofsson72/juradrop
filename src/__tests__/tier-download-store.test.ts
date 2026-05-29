import { describe, expect, it, beforeEach, vi } from 'vitest';

// Spec 027 — tier-download store: reflects backend stream events, maps
// start-refusals, and refreshes pull-state on completion.

const startMock = vi.fn();
const cancelMock = vi.fn();
const refreshMock = vi.fn();
const getStateMock = vi.fn(() => Promise.resolve<unknown>(null));

vi.mock('@/lib/tauri-bridge', () => ({
  startTierDownload: (tier: string) => startMock(tier),
  cancelTierDownload: (tier: string) => cancelMock(tier),
  getTierDownloadState: () => getStateMock(),
  subscribeTierDownload: () => Promise.resolve(() => {}),
}));

vi.mock('@/lib/settings-store', () => ({
  useSettingsStore: { getState: () => ({ refresh: refreshMock }) },
}));

import {
  useTierDownloadStore,
  ensureTierDownloadSubscription,
} from '@/lib/tier-download-store';
import type { TierDownloadEvent } from '@/lib/tauri-bridge';

function ev(partial: Partial<TierDownloadEvent>): TierDownloadEvent {
  return {
    tier: 'Stor',
    phase: 'downloading',
    percent: 0,
    completed: 0,
    total: 0,
    failure: null,
    ...partial,
  };
}

beforeEach(() => {
  startMock.mockReset().mockResolvedValue(undefined);
  cancelMock.mockReset().mockResolvedValue(undefined);
  refreshMock.mockReset();
  getStateMock.mockReset().mockResolvedValue(null);
  useTierDownloadStore.setState({ current: null, refusal: null });
});

describe('applyEvent', () => {
  it('reflects a downloading event as current + isAnyDownloading', () => {
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'downloading', percent: 40 }));
    expect(useTierDownloadStore.getState().current?.percent).toBe(40);
    expect(useTierDownloadStore.getState().isAnyDownloading()).toBe(true);
  });

  it('on done: clears current AND refreshes pull-state (FR-005)', () => {
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'downloading' }));
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'done' }));
    expect(useTierDownloadStore.getState().current).toBeNull();
    expect(refreshMock).toHaveBeenCalledTimes(1);
  });

  it('on cancelled: clears current AND refreshes pull-state (GAP-1 cancel-at-completion)', () => {
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'downloading' }));
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'cancelled' }));
    expect(useTierDownloadStore.getState().current).toBeNull();
    // A cancel that raced a completed pull leaves the model installed; the
    // refresh corrects the row immediately instead of waiting for reopen.
    expect(refreshMock).toHaveBeenCalledTimes(1);
  });

  it('on error: keeps the errored tier as current with its failure', () => {
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'error', failure: 'disk_full' }));
    const c = useTierDownloadStore.getState().current;
    expect(c?.phase).toBe('error');
    expect(c?.failure).toBe('disk_full');
    expect(useTierDownloadStore.getState().isAnyDownloading()).toBe(false);
  });

  it('coalesces rapid progress ticks (cadence) — store always holds the latest', () => {
    for (let p = 0; p <= 100; p += 5) {
      useTierDownloadStore.getState().applyEvent(ev({ phase: 'downloading', percent: p }));
    }
    expect(useTierDownloadStore.getState().current?.percent).toBe(100);
  });
});

describe('start / retry / cancel', () => {
  it('start invokes the backend command for the tier', async () => {
    await useTierDownloadStore.getState().start('Snabb');
    expect(startMock).toHaveBeenCalledWith('Snabb');
    expect(useTierDownloadStore.getState().refusal).toBeNull();
  });

  it('start maps a not_ready rejection to a refusal on that tier (FR-010)', async () => {
    startMock.mockRejectedValueOnce(new Error('not_ready'));
    await useTierDownloadStore.getState().start('Stor');
    expect(useTierDownloadStore.getState().refusal).toEqual({ tier: 'Stor', reason: 'not_ready' });
  });

  it('start maps a busy rejection (FR-009 belt-and-braces)', async () => {
    startMock.mockRejectedValueOnce(new Error('busy'));
    await useTierDownloadStore.getState().start('Snabb');
    expect(useTierDownloadStore.getState().refusal?.reason).toBe('busy');
  });

  it('retry restarts the pull from the error state', async () => {
    useTierDownloadStore.getState().applyEvent(ev({ phase: 'error', failure: 'network' }));
    await useTierDownloadStore.getState().retry('Stor');
    expect(startMock).toHaveBeenCalledWith('Stor');
  });

  it('cancel invokes the backend cancel command', async () => {
    await useTierDownloadStore.getState().cancel('Stor');
    expect(cancelMock).toHaveBeenCalledWith('Stor');
  });
});

describe('ensureTierDownloadSubscription — hydration (FR-011 / GAP-2)', () => {
  it('hydrates current from a non-null getTierDownloadState on mount', async () => {
    // Survives panel close/reopen: on mount the store re-reads the
    // backend-owned download state. A download in flight must reappear.
    getStateMock.mockResolvedValueOnce(
      ev({ tier: 'Stor', phase: 'downloading', percent: 73, completed: 6e9, total: 8.1e9 }),
    );
    ensureTierDownloadSubscription();
    // Let the getTierDownloadState().then(...) microtask flush.
    await new Promise((r) => setTimeout(r, 0));
    expect(useTierDownloadStore.getState().current?.tier).toBe('Stor');
    expect(useTierDownloadStore.getState().current?.percent).toBe(73);
  });
});
