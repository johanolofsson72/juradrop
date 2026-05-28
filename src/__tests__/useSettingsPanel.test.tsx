// Spec 010 / T029 — panel-visibility state machine coverage.
//
// 4 states × 6 transitions. Validates the coalescing invariant
// (rapid Cmd+, presses do not stack the panel) and the disabled-gate
// behaviour (gear click is a no-op while wizard/restart-confirm up).

import { act, renderHook } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { useSettingsPanel } from '@/lib/use-settings-panel';
import { useStatusStore } from '@/lib/status-store';
import { useUpdateStore } from '@/lib/update-store';

beforeEach(() => {
  vi.useFakeTimers();
  // Wizard/restart-confirm BOTH down by default.
  useStatusStore.setState({
    status: {
      visible: 'klar',
      sidecar: 'ready',
      model: 'ready',
      progress_percent: null,
      consent: 'fortsatt',
    },
  });
  useUpdateStore.setState({ status: { state: 'unknown' } });
});
afterEach(() => {
  vi.useRealTimers();
});

describe('useSettingsPanel — state machine', () => {
  it('starts closed', () => {
    const { result } = renderHook(() => useSettingsPanel());
    expect(result.current.visibility).toBe('closed');
    expect(result.current.gearIconEnabled).toBe(true);
  });

  it('closed → opening → open transitions through animation', () => {
    const { result } = renderHook(() => useSettingsPanel());
    act(() => result.current.openPanel());
    expect(result.current.visibility).toBe('opening');
    act(() => {
      vi.advanceTimersByTime(250);
    });
    expect(result.current.visibility).toBe('open');
  });

  it('open → closing → closed transitions through animation', () => {
    const { result } = renderHook(() => useSettingsPanel());
    act(() => result.current.openPanel());
    act(() => {
      vi.advanceTimersByTime(250);
    });
    expect(result.current.visibility).toBe('open');
    act(() => result.current.closePanel());
    expect(result.current.visibility).toBe('closing');
    act(() => {
      vi.advanceTimersByTime(250);
    });
    expect(result.current.visibility).toBe('closed');
  });

  it('togglePanel from closed → opening; from open → closing', () => {
    const { result } = renderHook(() => useSettingsPanel());
    act(() => result.current.togglePanel());
    expect(result.current.visibility).toBe('opening');
    act(() => {
      vi.advanceTimersByTime(250);
    });
    expect(result.current.visibility).toBe('open');
    act(() => result.current.togglePanel());
    expect(result.current.visibility).toBe('closing');
  });

  it('coalesces repeated open intents — at most one panel instance', () => {
    const { result } = renderHook(() => useSettingsPanel());
    act(() => {
      for (let i = 0; i < 20; i++) result.current.openPanel();
    });
    // Still in opening, not in some doubled state.
    expect(['opening', 'open']).toContain(result.current.visibility);
    act(() => {
      vi.advanceTimersByTime(500);
    });
    expect(result.current.visibility).toBe('open');
  });

  it('gear disabled while spec 008 wizard is up (begar_samtycke / laddar_ner_modell)', () => {
    useStatusStore.setState({
      status: {
        visible: 'begar_samtycke',
        sidecar: 'ready',
        model: 'not_present',
        progress_percent: null,
        consent: 'not_asked',
      },
    });
    const { result } = renderHook(() => useSettingsPanel());
    expect(result.current.gearIconEnabled).toBe(false);
    act(() => result.current.openPanel());
    expect(result.current.visibility).toBe('closed');
  });

  it('gear disabled while spec 007 restart-confirm is up', () => {
    useUpdateStore.setState({
      status: {
        state: 'ready_to_install',
        version: '0.2.0',
        notes: '',
        bytes_total: null,
        bytes_downloaded: null,
      } as never,
    });
    const { result } = renderHook(() => useSettingsPanel());
    expect(result.current.gearIconEnabled).toBe(false);
    act(() => result.current.openPanel());
    expect(result.current.visibility).toBe('closed');
  });
});
