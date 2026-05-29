import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createDragHoverTracker, type DragHoverDeps } from '@/lib/drag-hover';
import type { ZoneId, ZoneSnapshot } from '@/lib/tauri-bridge';

// Spec 026 — functional coverage for the OS drag-hover highlight routing.
// Every behaviour the live App.tsx wiring relies on is exercised here:
// idle→dragover, gate on disabled/non-idle, zone-to-zone handoff, clear.

const snap = (over: Partial<ZoneSnapshot> = {}): ZoneSnapshot => ({
  state: 'idle',
  disabled: false,
  failure: null,
  job_id: null,
  progress_hint: null,
  ...over,
});

function harness(initial: Partial<Record<ZoneId, ZoneSnapshot>>) {
  const zones: Partial<Record<ZoneId, ZoneSnapshot>> = { ...initial };
  let pointZone: ZoneId | null = null;
  const setZone = vi.fn((id: ZoneId, next: ZoneSnapshot) => {
    zones[id] = next;
  });
  const deps: DragHoverDeps = {
    zoneAtPoint: () => pointZone,
    getZone: (id) => zones[id],
    setZone,
  };
  const tracker = createDragHoverTracker(deps);
  return {
    tracker,
    setZone,
    zones,
    moveTo: (zone: ZoneId | null) => {
      pointZone = zone;
      tracker.over(0, 0);
    },
  };
}

describe('createDragHoverTracker', () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({
      sammanfatta: snap(),
      anonymisera: snap(),
      forenkla: snap({ disabled: true }),
      generera: snap({ state: 'processing', job_id: 'j1' }),
    });
  });

  it('lights up an idle, enabled zone under the cursor', () => {
    h.moveTo('sammanfatta');
    expect(h.zones.sammanfatta?.state).toBe('dragover');
    expect(h.tracker.hovered).toBe('sammanfatta');
  });

  it('does NOT light up a disabled zone', () => {
    h.moveTo('forenkla');
    expect(h.zones.forenkla?.state).toBe('idle');
    expect(h.tracker.hovered).toBeNull();
  });

  it('does NOT hijack a zone that is already processing', () => {
    h.moveTo('generera');
    expect(h.zones.generera?.state).toBe('processing');
    expect(h.tracker.hovered).toBeNull();
  });

  it('hands off cleanly from one zone to another (clears the first)', () => {
    h.moveTo('sammanfatta');
    h.moveTo('anonymisera');
    expect(h.zones.sammanfatta?.state).toBe('idle'); // reverted
    expect(h.zones.anonymisera?.state).toBe('dragover');
    expect(h.tracker.hovered).toBe('anonymisera');
  });

  it('is a no-op while the cursor stays over the same zone (no redundant writes)', () => {
    h.moveTo('sammanfatta');
    h.setZone.mockClear();
    h.moveTo('sammanfatta');
    expect(h.setZone).not.toHaveBeenCalled();
  });

  it('clears the highlight when the cursor moves to empty space', () => {
    h.moveTo('sammanfatta');
    h.moveTo(null);
    expect(h.zones.sammanfatta?.state).toBe('idle');
    expect(h.tracker.hovered).toBeNull();
  });

  it('clear() reverts the active highlight (drop / drag-leave path)', () => {
    h.moveTo('anonymisera');
    h.tracker.clear();
    expect(h.zones.anonymisera?.state).toBe('idle');
    expect(h.tracker.hovered).toBeNull();
  });

  it('clear() is a safe no-op when nothing is highlighted', () => {
    h.setZone.mockClear();
    h.tracker.clear();
    expect(h.setZone).not.toHaveBeenCalled();
  });
});
