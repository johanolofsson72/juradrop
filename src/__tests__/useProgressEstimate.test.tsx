// Spec 008 / T009 + GAP-B — ETA formatter + rolling-window estimator.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';

import { formatBytesSwedish, formatEta, useProgressEstimate } from '@/lib/use-progress-estimate';
import { WIZARD_STRINGS } from '@/lib/wizard-strings';
import { useStatusStore } from '@/lib/status-store';

describe('formatEta — FR-004 clarification', () => {
  it('null → em-dash placeholder', () => {
    expect(formatEta(null)).toBe(WIZARD_STRINGS.progress_eta_unknown);
  });

  it('negative → em-dash placeholder', () => {
    expect(formatEta(-5)).toBe(WIZARD_STRINGS.progress_eta_unknown);
  });

  it('1 second → "≈ 5 s" (rounds up to 5)', () => {
    expect(formatEta(1)).toBe('≈ 5 s');
  });

  it('59 seconds → "≈ 60 s" (still seconds bucket)', () => {
    expect(formatEta(59)).toBe('≈ 60 s');
  });

  it('60 seconds → "≈ 1 min" (boundary flips to minutes)', () => {
    expect(formatEta(60)).toBe('≈ 1 min');
  });

  it('120 seconds → "≈ 2 min"', () => {
    expect(formatEta(120)).toBe('≈ 2 min');
  });

  it('181 seconds → "≈ 4 min" (ceiling)', () => {
    expect(formatEta(181)).toBe('≈ 4 min');
  });

  it('Infinity → em-dash placeholder', () => {
    expect(formatEta(Number.POSITIVE_INFINITY)).toBe(WIZARD_STRINGS.progress_eta_unknown);
  });
});

describe('formatBytesSwedish — thin-space thousands', () => {
  // U+202F NARROW NO-BREAK SPACE — the Swedish thousands separator.
  const NBSP = ' ';

  it('formats MB with thin-space (U+202F) thousands separator', () => {
    expect(formatBytesSwedish(0, 2 * 1024 * 1024 * 1024)).toContain('av');
    expect(formatBytesSwedish(0, 2 * 1024 * 1024 * 1024)).toContain(`2${NBSP}048`);
  });

  it('rounds to whole MB', () => {
    const s = formatBytesSwedish(512 * 1024 * 1024 + 12345, 2 * 1024 * 1024 * 1024);
    expect(s).toMatch(/^\d+ MB av/);
  });
});

// GAP-B / TLA+ finding — rolling-window estimator coverage.
describe('useProgressEstimate — rolling-window estimator', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    useStatusStore.setState((s) => ({
      status: { ...s.status, progress_percent: 0 },
    }));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns "—" ETA when no progress events have arrived', () => {
    const { result } = renderHook(() => useProgressEstimate());
    expect(result.current.etaRendered).toBe(WIZARD_STRINGS.progress_eta_unknown);
    expect(result.current.label).toBe('downloading');
  });

  it('does not flip label to "waiting" when sample buffer is empty', () => {
    const { result, rerender } = renderHook(() => useProgressEstimate({ staleMs: 5000 }));
    expect(result.current.label).toBe('downloading');

    // Advance past the stale threshold + one polling interval.
    act(() => {
      vi.advanceTimersByTime(5500);
    });
    rerender();
    // No samples ever arrived; the poll short-circuits when buffer empty.
    expect(result.current.label).toBe('downloading');
  });

  it('mirrors progress_percent from the status store as lastPct', () => {
    useStatusStore.setState((s) => ({
      status: { ...s.status, progress_percent: 73 },
    }));
    const { result } = renderHook(() => useProgressEstimate());
    expect(result.current.lastPct).toBe(73);
  });
});
