// Spec 008 / GAP-A — fake-timer test for the FR-019 minimum-visible hold.
//
// The hook must hold the previous phase for at least minMs after a
// phase change. Verifies the hold across the three relevant scenarios:
//   1. Phase changes immediately after mount → hold for full minMs.
//   2. Phase changes after a long visible time → apply immediately.
//   3. Repeated phase changes within minMs → only the LAST change wins.

import { renderHook, act } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { useMinVisibleHold, type WizardPhase } from '@/lib/use-wizard-state';

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('useMinVisibleHold — FR-019 minimum-visible-time invariant', () => {
  it('holds the previous phase for 300 ms after an instant transition', () => {
    let actual: WizardPhase = 'welcome';
    const { result, rerender } = renderHook(() =>
      useMinVisibleHold(actual, 300),
    );
    expect(result.current).toBe('welcome');

    // Flip the actual phase 10 ms after mount.
    act(() => {
      vi.advanceTimersByTime(10);
    });
    actual = 'hidden';
    rerender();
    expect(result.current).toBe('welcome'); // hold still active

    // Advance 200 ms — total 210 ms elapsed. Still holding.
    act(() => {
      vi.advanceTimersByTime(200);
    });
    expect(result.current).toBe('welcome');

    // Advance another 100 ms — total 310 ms. Hold released.
    act(() => {
      vi.advanceTimersByTime(100);
    });
    expect(result.current).toBe('hidden');
  });

  it('applies a transition immediately after the visible window has elapsed', () => {
    let actual: WizardPhase = 'welcome';
    const { result, rerender } = renderHook(() =>
      useMinVisibleHold(actual, 300),
    );
    // Wait 1 second before any transition.
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    expect(result.current).toBe('welcome');

    // Now flip — should apply immediately because elapsed >> minMs.
    actual = 'hidden';
    rerender();
    // The effect schedules a setTimeout(0) when elapsed >= minMs;
    // flush the macrotask.
    act(() => {
      vi.advanceTimersByTime(0);
    });
    expect(result.current).toBe('hidden');
  });

  it('cancels a pending hold when the actual phase reverts before minMs', () => {
    let actual: WizardPhase = 'welcome';
    const { result, rerender } = renderHook(() =>
      useMinVisibleHold(actual, 300),
    );
    expect(result.current).toBe('welcome');

    // Flip to hidden after 10 ms.
    act(() => {
      vi.advanceTimersByTime(10);
    });
    actual = 'hidden';
    rerender();
    expect(result.current).toBe('welcome'); // hold active

    // Revert to welcome 50 ms later — held stays welcome (no change).
    act(() => {
      vi.advanceTimersByTime(50);
    });
    actual = 'welcome';
    rerender();
    expect(result.current).toBe('welcome');

    // Advance well past 300 ms; held should remain welcome.
    act(() => {
      vi.advanceTimersByTime(500);
    });
    expect(result.current).toBe('welcome');
  });
});
