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

import { ensureSettingsSubscription, useSettingsStore } from '@/lib/settings-store';

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

  // ── H1 mutation-kill: the if-false branches + setters + subscription ──

  it('refresh() keeps snapshot null when get_settings fails but still sets pullState', async () => {
    invokeMock.mockImplementation(async (name: string) => {
      if (name === 'get_settings') throw new Error('boom');
      if (name === 'get_tier_pull_state')
        return { snabb_pulled: true, smart_pulled: false, stor_pulled: false };
      throw new Error(`unexpected invoke: ${name}`);
    });

    await useSettingsStore.getState().refresh();

    expect(useSettingsStore.getState().snapshot).toBeNull();
    expect(useSettingsStore.getState().pullState).toEqual({
      snabb_pulled: true,
      smart_pulled: false,
      stor_pulled: false,
    });
  });

  it('refresh() keeps pullState null when get_tier_pull_state fails but still sets snapshot', async () => {
    invokeMock.mockImplementation(async (name: string) => {
      if (name === 'get_settings') return { schema_version: 1, model_tier: 'Stor' };
      if (name === 'get_tier_pull_state') throw new Error('boom');
      throw new Error(`unexpected invoke: ${name}`);
    });

    await useSettingsStore.getState().refresh();

    expect(useSettingsStore.getState().snapshot).toEqual({ schema_version: 1, model_tier: 'Stor' });
    expect(useSettingsStore.getState().pullState).toBeNull();
  });

  it('selectTier() with no previous snapshot invokes Rust without an optimistic set', async () => {
    // previous === null → the `if (previous)` optimistic-set branch is skipped.
    invokeMock.mockResolvedValue(undefined);

    await useSettingsStore.getState().selectTier('Snabb');

    expect(invokeMock).toHaveBeenCalledWith('set_model_tier', { tier: 'Snabb' });
    expect(useSettingsStore.getState().snapshot).toBeNull();
  });

  it('selectTier() with no previous rethrows on error and leaves snapshot null', async () => {
    invokeMock.mockRejectedValue(new Error('TierNotPulled'));

    await expect(useSettingsStore.getState().selectTier('Stor')).rejects.toThrow('TierNotPulled');
    expect(useSettingsStore.getState().snapshot).toBeNull();
  });

  it('setSnapshot() and setPullState() write directly to the store', () => {
    useSettingsStore.getState().setSnapshot({ schema_version: 1, model_tier: 'Smart' });
    expect(useSettingsStore.getState().snapshot).toEqual({ schema_version: 1, model_tier: 'Smart' });

    useSettingsStore
      .getState()
      .setPullState({ snabb_pulled: false, smart_pulled: false, stor_pulled: true });
    expect(useSettingsStore.getState().pullState).toEqual({
      snabb_pulled: false,
      smart_pulled: false,
      stor_pulled: true,
    });
  });

  it('ensureSettingsSubscription() fetches once and is idempotent on repeat calls', async () => {
    invokeMock.mockResolvedValue({ schema_version: 1, model_tier: 'Smart' });

    ensureSettingsSubscription();
    await Promise.resolve();
    await Promise.resolve();
    const firstCallCount = invokeMock.mock.calls.filter((c) => c[0] === 'get_settings').length;
    expect(firstCallCount).toBeGreaterThanOrEqual(1);

    invokeMock.mockClear();
    ensureSettingsSubscription(); // already subscribed → no second fetch
    await Promise.resolve();
    expect(invokeMock.mock.calls.filter((c) => c[0] === 'get_settings')).toHaveLength(0);
  });
});
