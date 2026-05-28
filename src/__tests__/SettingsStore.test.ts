// Spec 010 / T028 — coverage for the SettingsStore.
//
// Drives the store through the snapshot + pullState + selectTier
// flows. The Tauri command wrappers are mocked at the @tauri-apps
// boundary so the store can be exercised in jsdom.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const invokeMock = vi.fn();
vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));
vi.mock('@tauri-apps/api/event', () => ({
  listen: vi.fn(async () => () => {}),
}));

import { useSettingsStore } from '@/lib/settings-store';

describe('useSettingsStore', () => {
  beforeEach(() => {
    invokeMock.mockReset();
    useSettingsStore.setState({ snapshot: null, pullState: null });
  });

  afterEach(() => {
    invokeMock.mockReset();
  });

  it('refresh() seeds snapshot + pullState from Tauri commands', async () => {
    invokeMock.mockImplementation(async (name: string) => {
      if (name === 'get_settings')
        return { schema_version: 1, model_tier: 'Smart' };
      if (name === 'get_tier_pull_state')
        return { snabb_pulled: false, smart_pulled: true, stor_pulled: false };
      throw new Error(`unexpected invoke: ${name}`);
    });

    await useSettingsStore.getState().refresh();

    expect(useSettingsStore.getState().snapshot).toEqual({
      schema_version: 1,
      model_tier: 'Smart',
    });
    expect(useSettingsStore.getState().pullState).toEqual({
      snabb_pulled: false,
      smart_pulled: true,
      stor_pulled: false,
    });
  });

  it('selectTier() optimistically updates then awaits Rust', async () => {
    useSettingsStore.setState({
      snapshot: { schema_version: 1, model_tier: 'Smart' },
      pullState: { snabb_pulled: true, smart_pulled: true, stor_pulled: true },
    });
    invokeMock.mockImplementation(async (name: string, args: unknown) => {
      if (name === 'set_model_tier') {
        expect((args as { tier: string }).tier).toBe('Snabb');
        return undefined;
      }
      throw new Error(`unexpected invoke: ${name}`);
    });

    await useSettingsStore.getState().selectTier('Snabb');

    expect(useSettingsStore.getState().snapshot?.model_tier).toBe('Snabb');
    expect(invokeMock).toHaveBeenCalledWith('set_model_tier', { tier: 'Snabb' });
  });

  it('selectTier() reverts on Rust error', async () => {
    useSettingsStore.setState({
      snapshot: { schema_version: 1, model_tier: 'Smart' },
      pullState: { snabb_pulled: true, smart_pulled: true, stor_pulled: true },
    });
    invokeMock.mockImplementation(async () => {
      throw new Error('TierNotPulled');
    });

    await expect(useSettingsStore.getState().selectTier('Stor')).rejects.toThrow();
    // snapshot reverted to the previous value
    expect(useSettingsStore.getState().snapshot?.model_tier).toBe('Smart');
  });
});
