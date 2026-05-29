// Spec 027 — functional + destructive coverage for the on-demand
// download sub-states of the model-tier rows.

import { fireEvent, render } from '@testing-library/react';
import { describe, expect, it, vi, beforeEach } from 'vitest';

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async () => () => {}) }));

import { ModelTierSection } from '@/components/SettingsPanelModelTier';
import { SETTINGS_PANEL_STRINGS as S } from '@/lib/settings-panel-strings';
import { useSettingsStore } from '@/lib/settings-store';
import { useTierDownloadStore } from '@/lib/tier-download-store';
import type { ModelTier } from '@/lib/settings-types';
import type { TierDownloadEvent, TierDownloadFailure } from '@/lib/tauri-bridge';

const startSpy = vi.fn();
const cancelSpy = vi.fn();
const retrySpy = vi.fn();

function setPulled(pulled: { snabb: boolean; smart: boolean; stor: boolean }) {
  useSettingsStore.setState({
    snapshot: { schema_version: 1, model_tier: 'Smart' } as never,
    pullState: { snabb_pulled: pulled.snabb, smart_pulled: pulled.smart, stor_pulled: pulled.stor },
  });
}

function setDownload(current: TierDownloadEvent | null, refusal: { tier: ModelTier; reason: 'not_ready' | 'busy' | 'already_pulled' } | null = null) {
  useTierDownloadStore.setState({
    current,
    refusal,
    start: (t: ModelTier) => { startSpy(t); return Promise.resolve(); },
    cancel: (t: ModelTier) => { cancelSpy(t); return Promise.resolve(); },
    retry: (t: ModelTier) => { retrySpy(t); return Promise.resolve(); },
  });
}

function dl(partial: Partial<TierDownloadEvent>): TierDownloadEvent {
  return { tier: 'Stor', phase: 'downloading', percent: 0, completed: 0, total: 0, failure: null, ...partial };
}

beforeEach(() => {
  startSpy.mockReset();
  cancelSpy.mockReset();
  retrySpy.mockReset();
  setPulled({ snabb: false, smart: true, stor: false }); // Smart radio, Snabb+Stor download
  setDownload(null);
});

describe('Spec 027 — download_button sub-states', () => {
  it('idle: unpulled tier shows the Ladda ned button + size badge', () => {
    const { container } = render(<ModelTierSection />);
    const btn = container.querySelector('[data-tier-download-button="Stor"]') as HTMLButtonElement;
    expect(btn).not.toBeNull();
    expect(btn.textContent).toContain(S.tier_ladda_ned_button);
    expect(container.querySelector('[data-tier="Stor"]')?.textContent).toContain('8.1 GB');
  });

  it('clicking Ladda ned calls start(tier)', () => {
    const { container } = render(<ModelTierSection />);
    fireEvent.click(container.querySelector('[data-tier-download-button="Stor"]')!);
    expect(startSpy).toHaveBeenCalledWith('Stor');
  });

  it('downloading: shows a progressbar + "62 % · 5,0 / 8,1 GB" + Avbryt', () => {
    setDownload(dl({ tier: 'Stor', phase: 'downloading', percent: 62, completed: 5_000_000_000, total: 8_100_000_000 }));
    const { container } = render(<ModelTierSection />);
    const bar = container.querySelector('[data-tier-download-progress="Stor"] [role="progressbar"]');
    expect(bar?.getAttribute('aria-valuenow')).toBe('62');
    expect(container.querySelector('[data-tier="Stor"]')?.textContent).toContain('62 % · 5,0 GB / 8,1 GB');
    expect(container.querySelector('[data-tier-cancel="Stor"]')).not.toBeNull();
  });

  it('downloading with unknown total: indeterminate label, no valuenow', () => {
    setDownload(dl({ tier: 'Stor', phase: 'downloading', percent: 0, total: 0 }));
    const { container } = render(<ModelTierSection />);
    expect(container.querySelector('[data-tier="Stor"]')?.textContent).toContain(S.tier_downloading_label);
    const bar = container.querySelector('[role="progressbar"]');
    expect(bar?.getAttribute('aria-valuenow')).toBeNull();
  });

  it('clicking Avbryt calls cancel(tier)', () => {
    setDownload(dl({ tier: 'Stor', phase: 'downloading', percent: 10, total: 100, completed: 10 }));
    const { container } = render(<ModelTierSection />);
    fireEvent.click(container.querySelector('[data-tier-cancel="Stor"]')!);
    expect(cancelSpy).toHaveBeenCalledWith('Stor');
  });

  it('error: shows the mapped Swedish failure + Försök igen, which calls retry', () => {
    const failures: [TierDownloadFailure, string][] = [
      ['network', S.tier_download_err_network],
      ['disk_full', S.tier_download_err_disk_full],
      ['not_found', S.tier_download_err_not_found],
    ];
    for (const [failure, msg] of failures) {
      setDownload(dl({ tier: 'Stor', phase: 'error', failure }));
      const { container, unmount } = render(<ModelTierSection />);
      expect(container.querySelector('[data-tier="Stor"]')?.textContent).toContain(msg);
      const retryBtn = container.querySelector('[data-tier-retry="Stor"]') as HTMLButtonElement;
      expect(retryBtn).not.toBeNull();
      fireEvent.click(retryBtn);
      expect(retrySpy).toHaveBeenCalledWith('Stor');
      retrySpy.mockReset();
      unmount();
    }
  });

  it('FR-009: while one tier downloads, the OTHER unpulled tier’s Ladda ned is disabled', () => {
    setDownload(dl({ tier: 'Stor', phase: 'downloading', percent: 30, total: 100, completed: 30 }));
    const { container } = render(<ModelTierSection />);
    const snabbBtn = container.querySelector('[data-tier-download-button="Snabb"]') as HTMLButtonElement;
    expect(snabbBtn.disabled).toBe(true);
  });

  it('FR-010: a not_ready start-refusal renders the "inte redo" message on the row', () => {
    setDownload(null, { tier: 'Stor', reason: 'not_ready' });
    const { container } = render(<ModelTierSection />);
    expect(container.querySelector('[data-tier="Stor"]')?.textContent).toContain(S.tier_download_err_not_ready);
  });

  it('pulled tier renders a selectable radio, never a download button', () => {
    const { container } = render(<ModelTierSection />);
    const smart = container.querySelector('[data-tier="Smart"]');
    expect(smart?.getAttribute('data-tier-mode')).toBe('radio_selectable');
    expect(container.querySelector('[data-tier-download-button="Smart"]')).toBeNull();
  });
});
