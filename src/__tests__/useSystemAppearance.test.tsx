// Spec 010 / T039 — useSystemAppearance under simulated OS change.
//
// Asserts the hook reflects the current (prefers-color-scheme: dark)
// match value and re-renders within the FR-015 / SC-004 500 ms budget
// when the underlying MediaQueryList emits a change event.

import { act, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { useSystemAppearance } from '@/lib/use-system-appearance';

type Listener = (e: { matches: boolean }) => void;

function installMediaQueryMock(initial: boolean) {
  let matches = initial;
  const listeners = new Set<Listener>();
  const mql = {
    get matches() {
      return matches;
    },
    media: '(prefers-color-scheme: dark)',
    addEventListener(_evt: string, cb: Listener) {
      listeners.add(cb);
    },
    removeEventListener(_evt: string, cb: Listener) {
      listeners.delete(cb);
    },
    addListener(cb: Listener) {
      listeners.add(cb);
    },
    removeListener(cb: Listener) {
      listeners.delete(cb);
    },
    dispatchEvent: () => true,
    onchange: null as null,
  };
  const matchMedia = vi.fn().mockReturnValue(mql);
  Object.defineProperty(window, 'matchMedia', {
    configurable: true,
    writable: true,
    value: matchMedia,
  });
  return {
    fireChange(newValue: boolean) {
      matches = newValue;
      for (const cb of listeners) cb({ matches: newValue });
    },
  };
}

describe('useSystemAppearance', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('initial value reflects (prefers-color-scheme: dark) match state', () => {
    installMediaQueryMock(false);
    const { result } = renderHook(() => useSystemAppearance());
    expect(result.current).toBe('light');
  });

  it('initial value is "dark" when OS reports dark', () => {
    installMediaQueryMock(true);
    const { result } = renderHook(() => useSystemAppearance());
    expect(result.current).toBe('dark');
  });

  it('re-renders within 500 ms of a synthetic change event (SC-004)', () => {
    const handle = installMediaQueryMock(false);
    const { result } = renderHook(() => useSystemAppearance());
    expect(result.current).toBe('light');
    act(() => {
      handle.fireChange(true);
      vi.advanceTimersByTime(500);
    });
    expect(result.current).toBe('dark');
  });
});
