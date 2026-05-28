// Spec 013 / FR-022 + FR-023 — help/settings mutual exclusion + modal-gating.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. Opening help closes the settings panel (FR-023).
//  2. Opening settings closes the help panel (FR-023 reverse).
//  3. At most one slide-in panel is in open/opening at a time.
//  4. The chrome help icon is disabled while the wizard is up (FR-022).

import { act, fireEvent, render, screen, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async () => () => {}) }));
vi.mock('@tauri-apps/plugin-shell', () => ({ open: vi.fn(async () => {}) }));

import { App } from '../App';
import { useStatusStore } from '@/lib/status-store';

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

function vis(selector: string): string | null {
  const el = document.querySelector(selector);
  return el?.getAttribute(selector.includes('settings') ? 'data-settings-visibility' : 'data-help-visibility') ?? null;
}

afterEach(() => cleanup());

describe('help/settings mutual exclusion (FR-023)', () => {
  it('opening help closes the settings panel', () => {
    setKlar();
    render(<App />);
    // Open settings via the gear.
    fireEvent.click(screen.getByLabelText('Inställningar'));
    expect(document.querySelector('[data-settings-panel]')).not.toBeNull();
    // Now open help — settings must move out of open/opening.
    fireEvent.click(screen.getByLabelText('Hjälp'));
    expect(document.querySelector('[data-help-panel]')).not.toBeNull();
    const settingsVis = vis('[data-settings-panel]');
    expect(settingsVis === null || settingsVis === 'closing' || settingsVis === 'closed').toBe(
      true,
    );
  });

  it('opening settings closes the help panel', () => {
    setKlar();
    render(<App />);
    fireEvent.click(screen.getByLabelText('Hjälp'));
    expect(document.querySelector('[data-help-panel]')).not.toBeNull();
    fireEvent.click(screen.getByLabelText('Inställningar'));
    expect(document.querySelector('[data-settings-panel]')).not.toBeNull();
    const helpVis = vis('[data-help-panel]');
    expect(helpVis === null || helpVis === 'closing' || helpVis === 'closed').toBe(true);
  });

  it('never has both panels in open/opening simultaneously', () => {
    setKlar();
    render(<App />);
    fireEvent.click(screen.getByLabelText('Inställningar'));
    fireEvent.click(screen.getByLabelText('Hjälp'));
    const sv = vis('[data-settings-panel]');
    const hv = vis('[data-help-panel]');
    const bothOpen =
      (sv === 'open' || sv === 'opening') && (hv === 'open' || hv === 'opening');
    expect(bothOpen).toBe(false);
  });
});

describe('help icon modal-gating (FR-022)', () => {
  it('disables the chrome help icon while the first-run wizard is up', () => {
    useStatusStore.setState((s) => ({
      status: { ...s.status, visible: 'begar_samtycke' },
    }));
    render(<App />);
    const help = document.querySelector('[data-help-icon]') as HTMLButtonElement | null;
    expect(help).not.toBeNull();
    expect(help!.getAttribute('aria-disabled')).toBe('true');
    expect(help!.disabled).toBe(true);
    // Clicking while disabled must not open the panel.
    act(() => {
      fireEvent.click(help!);
    });
    expect(document.querySelector('[data-help-panel]')).toBeNull();
  });
});
