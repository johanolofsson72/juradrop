// Spec 010 / T020 / T030 / T045 — functional coverage for the
// settings panel surface. Renders each section with mocked store
// state and asserts the contract from spec.md (radio mode vs
// download_button mode, appearance projection, About content + the
// shell.open boundary, gear-icon disabled-gate, FR-012a invariant).

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

const invokeMock = vi.fn();
const shellOpenMock = vi.fn(async (_url: string) => {});

vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));
vi.mock('@tauri-apps/api/event', () => ({
  listen: vi.fn(async () => () => {}),
}));
vi.mock('@tauri-apps/plugin-shell', () => ({
  open: (url: string) => shellOpenMock(url),
}));

import { AboutSection } from '@/components/SettingsPanelAbout';
import { AppearanceSection } from '@/components/SettingsPanelAppearance';
import { GearIcon } from '@/components/GearIcon';
import { ModelTierSection } from '@/components/SettingsPanelModelTier';
import { SettingsPanel } from '@/components/SettingsPanel';
import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import { useSettingsStore } from '@/lib/settings-store';

beforeEach(() => {
  invokeMock.mockReset();
  shellOpenMock.mockReset();
  useSettingsStore.setState({ snapshot: null, pullState: null });
});
afterEach(() => {
  invokeMock.mockReset();
  shellOpenMock.mockReset();
});

function setSettings(args: {
  tier?: 'Snabb' | 'Smart' | 'Stor';
  pulled?: { snabb: boolean; smart: boolean; stor: boolean };
}) {
  useSettingsStore.setState({
    snapshot: { schema_version: 1, model_tier: args.tier ?? 'Smart' },
    pullState: args.pulled
      ? {
          snabb_pulled: args.pulled.snabb,
          smart_pulled: args.pulled.smart,
          stor_pulled: args.pulled.stor,
        }
      : null,
  });
}

describe('ModelTierSection', () => {
  it('renders three rows in canonical order with helpers + size badges', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: false, smart: true, stor: false } });
    render(<ModelTierSection />);
    expect(screen.getByText(SETTINGS_PANEL_STRINGS.tier_snabb_helper)).toBeInTheDocument();
    expect(screen.getByText(SETTINGS_PANEL_STRINGS.tier_smart_helper)).toBeInTheDocument();
    expect(screen.getByText(SETTINGS_PANEL_STRINGS.tier_stor_helper)).toBeInTheDocument();
    // Two Ladda ned buttons (Snabb + Stor unpulled), zero for Smart.
    expect(screen.getAllByText(SETTINGS_PANEL_STRINGS.tier_ladda_ned_button)).toHaveLength(2);
  });

  it('selectable radio shows for pulled tier; download_button for unpulled (FR-012)', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: false, smart: true, stor: false } });
    const { container } = render(<ModelTierSection />);
    const smart = container.querySelector('[data-tier="Smart"]');
    const snabb = container.querySelector('[data-tier="Snabb"]');
    const stor = container.querySelector('[data-tier="Stor"]');
    expect(smart?.getAttribute('data-tier-mode')).toBe('radio_selectable');
    expect(snabb?.getAttribute('data-tier-mode')).toBe('download_button');
    expect(stor?.getAttribute('data-tier-mode')).toBe('download_button');
  });

  it('clicking a radio fires set_model_tier with the typed enum', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: true, smart: true, stor: false } });
    invokeMock.mockResolvedValue(undefined);
    render(<ModelTierSection />);
    const snabbRow = document.querySelector('[data-tier="Snabb"] input[type="radio"]');
    fireEvent.click(snabbRow as Element);
    expect(invokeMock).toHaveBeenCalledWith('set_model_tier', { tier: 'Snabb' });
  });

  it('clicking Ladda ned fires trigger_tier_download — not set_model_tier (FR-012)', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: false, smart: true, stor: false } });
    invokeMock.mockResolvedValue(undefined);
    render(<ModelTierSection />);
    const button = document.querySelector('[data-tier="Stor"] button');
    fireEvent.click(button as Element);
    expect(invokeMock).toHaveBeenCalledWith('trigger_tier_download', { tier: 'Stor' });
    expect(invokeMock).not.toHaveBeenCalledWith('set_model_tier', expect.anything());
  });

  it('FR-012a — Smart pulled means at least one tier is radio_selectable', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: false, smart: true, stor: false } });
    const { container } = render(<ModelTierSection />);
    const selectable = container.querySelectorAll('[data-tier-mode="radio_selectable"]');
    expect(selectable.length).toBeGreaterThanOrEqual(1);
  });
});

describe('AppearanceSection (FR-013, FR-014)', () => {
  it('renders the Swedish appearance row (light by default in jsdom)', () => {
    const { container } = render(<AppearanceSection />);
    const row = container.querySelector('[data-settings-appearance]');
    expect(row?.textContent).toBe(SETTINGS_PANEL_STRINGS.appearance_light);
  });

  it('FR-014 — has zero interactive descendants', () => {
    const { container } = render(<AppearanceSection />);
    const section = container.querySelector('section');
    const interactives = section?.querySelectorAll(
      'input, button, select, [role="switch"], [role="checkbox"], [role="radio"]',
    );
    expect(interactives?.length ?? 0).toBe(0);
  });
});

describe('AboutSection (FR-016, FR-017)', () => {
  it('renders app name + license + GitHub button', () => {
    render(<AboutSection />);
    expect(screen.getByText(SETTINGS_PANEL_STRINGS.about_app_name)).toBeInTheDocument();
    expect(screen.getByText(SETTINGS_PANEL_STRINGS.about_license)).toBeInTheDocument();
    expect(screen.getByText(SETTINGS_PANEL_STRINGS.about_github_button)).toBeInTheDocument();
  });

  it('clicking the GitHub button goes through shell.open with the pinned URL — no in-app navigation', () => {
    render(<AboutSection />);
    fireEvent.click(screen.getByText(SETTINGS_PANEL_STRINGS.about_github_button));
    expect(shellOpenMock).toHaveBeenCalledTimes(1);
    expect(shellOpenMock).toHaveBeenCalledWith(
      'https://github.com/johanolofsson72/juradrop/releases',
    );
  });
});

describe('GearIcon (FR-005a)', () => {
  it('calls onClick when enabled', () => {
    const onClick = vi.fn();
    render(<GearIcon enabled={true} onClick={onClick} />);
    fireEvent.click(screen.getByRole('button', { name: SETTINGS_PANEL_STRINGS.gear_label }));
    expect(onClick).toHaveBeenCalledOnce();
  });

  it('does NOT call onClick when disabled (FR-005a — wizard or restart modal up)', () => {
    const onClick = vi.fn();
    render(<GearIcon enabled={false} onClick={onClick} />);
    fireEvent.click(screen.getByRole('button', { name: SETTINGS_PANEL_STRINGS.gear_label }));
    expect(onClick).not.toHaveBeenCalled();
  });

  it('exposes aria-disabled when disabled', () => {
    render(<GearIcon enabled={false} onClick={() => {}} />);
    const btn = screen.getByRole('button', { name: SETTINGS_PANEL_STRINGS.gear_label });
    expect(btn).toHaveAttribute('aria-disabled', 'true');
  });
});

describe('SettingsPanel — Esc dismisses', () => {
  it('renders nothing when visibility=closed', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: false, smart: true, stor: false } });
    const { container } = render(
      <SettingsPanel visibility="closed" onClose={() => {}} />,
    );
    expect(container.querySelector('[data-settings-panel]')).toBeNull();
  });

  it('Esc fires onClose when open', () => {
    setSettings({ tier: 'Smart', pulled: { snabb: false, smart: true, stor: false } });
    const onClose = vi.fn();
    render(<SettingsPanel visibility="open" onClose={onClose} />);
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledOnce();
  });
});
