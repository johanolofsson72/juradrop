// Spec 025 / T007 — diagnostics opt-in section coverage.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. Renders OFF by default (toggle unchecked) with the Swedish explanation.
//  2. Toggling on calls set_diagnostics_enabled(true).
//  3. The log path is shown once known.
//  4. No "send"/upload affordance exists (privacy: local-only).

import { fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const invokeMock = vi.fn();
vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

// Pretend we're inside Tauri so the section loads status on mount.
beforeEach(() => {
  (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
  invokeMock.mockReset();
});
afterEach(() => {
  delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  cleanup();
});

import { DiagnosticsSection } from '@/components/SettingsPanelDiagnostics';
import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';

describe('DiagnosticsSection (spec 025)', () => {
  it('renders OFF by default with the Swedish explanation', async () => {
    invokeMock.mockResolvedValue({ enabled: false, log_path: '/tmp/diagnostics.log' });
    render(<DiagnosticsSection />);
    const toggle = screen.getByRole('checkbox') as HTMLInputElement;
    expect(toggle.checked).toBe(false);
    expect(
      screen.getByText(SETTINGS_PANEL_STRINGS.diagnostics_explanation),
    ).toBeInTheDocument();
    // The path appears after the mount fetch resolves.
    await waitFor(() => expect(screen.getByText('/tmp/diagnostics.log')).toBeInTheDocument());
  });

  it('enabling calls set_diagnostics_enabled(true)', async () => {
    invokeMock.mockResolvedValue({ enabled: false, log_path: null });
    render(<DiagnosticsSection />);
    await waitFor(() => expect(invokeMock).toHaveBeenCalledWith('get_diagnostics_status'));
    invokeMock.mockResolvedValue({ enabled: true, log_path: '/tmp/diagnostics.log' });
    fireEvent.click(screen.getByRole('checkbox'));
    await waitFor(() =>
      expect(invokeMock).toHaveBeenCalledWith('set_diagnostics_enabled', { enabled: true }),
    );
  });

  it('has no upload/send affordance (local-only)', () => {
    invokeMock.mockResolvedValue({ enabled: false, log_path: null });
    const { container } = render(<DiagnosticsSection />);
    expect(container.textContent?.toLowerCase()).not.toContain('skicka in');
    expect(container.querySelectorAll('button')).toHaveLength(0);
  });
});
