// Spec 013 / FR-017 + SC-010 — the spec-010 settings gear still renders
// and is clickable with the 9-zone grid mounted, and the chrome help
// icon sits alongside it. Guards against the help-system additions
// breaking the existing chrome layout.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. The 9-zone grid renders 9 drop zones (SC-001).
//  2. data-settings-gear is present + enabled + clickable (SC-010).
//  3. data-help-icon is present (FR-019) and enabled in the klar state.
//  4. Each zone card carries a per-zone help (?) button (FR-018).

import { fireEvent, render, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async () => () => {}) }));
vi.mock('@tauri-apps/plugin-shell', () => ({ open: vi.fn(async () => {}) }));

import { App } from '../App';
import { useStatusStore } from '@/lib/status-store';
import { ZONE_ORDER } from '@/components/DropZone.identity';

function setKlar() {
  useStatusStore.setState((s) => ({
    status: {
      ...s.status,
      visible: 'klar',
      sidecar: 'ready',
      model: 'ready',
      consent: 'fortsatt',
      progress_percent: null,
    },
  }));
}

afterEach(() => cleanup());

describe('help system layout (FR-017 / SC-010 / SC-001)', () => {
  it('renders all 9 drop zones', () => {
    setKlar();
    render(<App />);
    expect(document.querySelectorAll('[data-zone-id]')).toHaveLength(ZONE_ORDER.length);
  });

  it('keeps the settings gear present, enabled and clickable', () => {
    setKlar();
    render(<App />);
    const gear = document.querySelector('[data-settings-gear]') as HTMLButtonElement | null;
    expect(gear).not.toBeNull();
    expect(gear!.disabled).toBe(false);
    fireEvent.click(gear!);
    expect(document.querySelector('[data-settings-panel]')).not.toBeNull();
  });

  it('renders the chrome help icon enabled in the klar state', () => {
    setKlar();
    render(<App />);
    const help = document.querySelector('[data-help-icon]') as HTMLButtonElement | null;
    expect(help).not.toBeNull();
    expect(help!.disabled).toBe(false);
  });

  it('gives every zone card its own help (?) button', () => {
    setKlar();
    render(<App />);
    expect(document.querySelectorAll('[data-zone-help-icon]')).toHaveLength(
      ZONE_ORDER.length,
    );
  });
});
