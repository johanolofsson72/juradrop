import { render, cleanup } from '@testing-library/react';
import { describe, expect, it, afterEach } from 'vitest';
import { DropZone } from '@/components/DropZone';
import { ZONE_ORDER } from '@/components/DropZone.identity';
import { useStatusStore } from '@/lib/status-store';
import type { AppStatus } from '@/lib/tauri-bridge';

// Spec 026 SC-002 (/tla GAP-1) — the single readiness truth.
//
// The zone-disabled gate derives SOLELY from the global status
// (status.visible === 'klar'), so the header and every zone can NEVER
// disagree. This locks in the fix for the bug where a per-zone `disabled`
// flag (a separate, racy signal) stayed stuck at its seed `true` while the
// header said "AI är redo" — leaving every zone inert behind a ready header.

type Visible = AppStatus['visible'];

function setVisible(visible: Visible) {
  useStatusStore.setState((s) => ({ status: { ...s.status, visible } }));
}

const NON_KLAR: readonly Visible[] = [
  'startar',
  'laddar_ner_modell',
  'begar_samtycke',
  'fel_kunde_inte_starta',
  'fel_porten_upptagen',
  'fel_ovantat',
];

describe('Spec 026 SC-002 — zones interactive iff the global status is Klar', () => {
  afterEach(() => {
    cleanup();
    setVisible('startar');
  });

  it('every zone’s "Välj fil" is enabled when the header is Klar', () => {
    setVisible('klar');
    for (const zoneId of ZONE_ORDER) {
      const { container, unmount } = render(<DropZone zoneId={zoneId} />);
      const btn = container.querySelector(
        `[data-zone-pick="${zoneId}"]`,
      ) as HTMLButtonElement | null;
      expect(btn, `pick button for ${zoneId}`).not.toBeNull();
      expect(btn!.disabled, `${zoneId} must be enabled when Klar`).toBe(false);
      unmount();
    }
  });

  it('every zone is disabled in EVERY non-Klar status — header and zones agree', () => {
    for (const visible of NON_KLAR) {
      setVisible(visible);
      for (const zoneId of ZONE_ORDER) {
        const { container, unmount } = render(<DropZone zoneId={zoneId} />);
        const btn = container.querySelector(
          `[data-zone-pick="${zoneId}"]`,
        ) as HTMLButtonElement | null;
        expect(btn!.disabled, `${zoneId} must be disabled when ${visible}`).toBe(true);
        unmount();
      }
    }
  });
});
