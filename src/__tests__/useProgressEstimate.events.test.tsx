// Spec 050 — the live half of useProgressEstimate: the progress-event
// subscription (now routed through `disposable`, FR-010) and the stale
// label poll it feeds. jsdom has no Tauri host, so these paths had zero
// coverage; here a fake `subscribeProgress` drives real samples.

import { act, cleanup, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const bridge = vi.hoisted(() => ({
  emit: undefined as undefined | ((percent: number) => void),
  unlisten: vi.fn(),
  subscribed: 0,
}));

vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  return {
    ...actual,
    subscribeProgress: (cb: (percent: number) => void) => {
      bridge.subscribed += 1;
      bridge.emit = cb;
      return Promise.resolve(bridge.unlisten);
    },
  };
});

import { useProgressEstimate } from '@/lib/use-progress-estimate';
import { useStatusStore } from '@/lib/status-store';

const TOTAL = 1_000_000;

async function mount(opts = {}) {
  const hook = renderHook(() =>
    useProgressEstimate({ estimatedTotalBytes: TOTAL, windowMs: 10_000, staleMs: 5_000, ...opts }),
  );
  await act(async () => {
    await Promise.resolve();
  });
  return hook;
}

function emitAt(ms: number, percent: number) {
  act(() => {
    vi.setSystemTime(ms);
    bridge.emit!(percent);
  });
}

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: false });
  vi.setSystemTime(1_000_000);
  (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
  bridge.emit = undefined;
  bridge.unlisten.mockReset();
  bridge.subscribed = 0;
  useStatusStore.setState((s) => ({ status: { ...s.status, progress_percent: null } }));
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
});

describe('useProgressEstimate — live progress events', () => {
  it('does not subscribe outside Tauri', async () => {
    delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
    await mount();
    expect(bridge.subscribed).toBe(0);
  });

  it('turns a percent into bytes of the estimated total', async () => {
    const { result } = await mount();
    emitAt(1_000_000, 25);
    expect(result.current.lastByteCount).toBe(250_000);
    expect(result.current.lastPct).toBe(25);
    expect(result.current.lastProgressAt).toBe(1_000_000);
  });

  it('computes the rolling rate and the ETA from two samples', async () => {
    const { result } = await mount();
    emitAt(1_000_000, 10); // 100 000 B
    emitAt(1_002_000, 30); // 300 000 B two seconds later → 100 000 B/s
    expect(result.current.bytesPerSecondRecent).toBe(100_000);
    expect(result.current.etaSeconds).toBe(7); // 700 000 B left
    expect(result.current.etaRendered).toBe('≈ 10 s');
  });

  it('drops samples older than the window', async () => {
    const { result } = await mount({ windowMs: 3_000 });
    emitAt(1_000_000, 0);
    emitAt(1_002_000, 10);
    emitAt(1_010_000, 20); // the first two are now > 3 s old
    // Only one sample left → no rate.
    expect(result.current.bytesPerSecondRecent).toBe(0);
    expect(result.current.etaSeconds).toBeNull();
  });

  it('keeps a sample that is exactly windowMs old', async () => {
    const { result } = await mount({ windowMs: 2_000 });
    emitAt(1_000_000, 10);
    emitAt(1_002_000, 30);
    expect(result.current.bytesPerSecondRecent).toBe(100_000);
  });

  it('flips to waiting after staleMs without progress, and zeroes the rate', async () => {
    const { result } = await mount();
    emitAt(1_000_000, 10);
    emitAt(1_001_000, 20);
    act(() => {
      vi.setSystemTime(1_001_000 + 5_000);
      vi.advanceTimersByTime(500);
    });
    expect(result.current.label).toBe('waiting');
    expect(result.current.bytesPerSecondRecent).toBe(0);
  });

  it('stays downloading just under staleMs', async () => {
    const { result } = await mount();
    emitAt(1_000_000, 10);
    act(() => {
      vi.setSystemTime(1_000_000 + 4_499); // +500 advance → 4 999 ms
      vi.advanceTimersByTime(500);
    });
    expect(result.current.label).toBe('downloading');
  });

  it('a new event after waiting flips back to downloading', async () => {
    const { result } = await mount();
    emitAt(1_000_000, 10);
    act(() => {
      vi.setSystemTime(1_010_000);
      vi.advanceTimersByTime(500);
    });
    expect(result.current.label).toBe('waiting');
    emitAt(1_010_500, 11);
    expect(result.current.label).toBe('downloading');
  });

  it('the store percent wins over the derived one', async () => {
    useStatusStore.setState((s) => ({ status: { ...s.status, progress_percent: 42 } }));
    const { result } = await mount();
    emitAt(1_000_000, 10);
    expect(result.current.lastPct).toBe(42);
  });

  it('unlistens on unmount (FR-010)', async () => {
    const { unmount } = await mount();
    unmount();
    expect(bridge.unlisten).toHaveBeenCalledTimes(1);
  });
});
