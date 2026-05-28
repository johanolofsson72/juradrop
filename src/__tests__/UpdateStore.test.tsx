// Spec 007 / T023 — vitest coverage for the Zustand UpdateStore.
//
// Drives the store through each state transition and asserts the
// `status` slice reflects the latest payload. The bridge subscription
// (`ensureUpdateStatusSubscription`) is exercised indirectly — the
// store's `setStatus` setter is what the listener calls on every event.

import { describe, expect, it, beforeEach } from 'vitest';

import { useUpdateStore } from '@/lib/update-store';
import type { UpdateStatus } from '@/lib/tauri-bridge';

describe('useUpdateStore — full lifecycle', () => {
  beforeEach(() => {
    useUpdateStore.setState({ status: { state: 'unknown' } });
  });

  it('initial state is unknown', () => {
    expect(useUpdateStore.getState().status.state).toBe('unknown');
  });

  it('transitions Unknown → Checking → Available → Downloading → ReadyToInstall', () => {
    const set = useUpdateStore.getState().setStatus;

    set({ state: 'checking' });
    expect(useUpdateStore.getState().status.state).toBe('checking');

    set({
      state: 'available',
      version: '0.2.0',
      notes: 'Bättre PDF-stöd',
      download_url: 'https://example/dmg',
      dismissed: false,
    });
    let s = useUpdateStore.getState().status;
    expect(s.state).toBe('available');
    if (s.state === 'available') {
      expect(s.version).toBe('0.2.0');
      expect(s.notes).toBe('Bättre PDF-stöd');
    }

    set({ state: 'downloading', version: '0.2.0', progress_pct: 17 });
    s = useUpdateStore.getState().status;
    if (s.state === 'downloading') {
      expect(s.progress_pct).toBe(17);
    }

    set({ state: 'downloading', version: '0.2.0', progress_pct: 73 });
    s = useUpdateStore.getState().status;
    if (s.state === 'downloading') {
      expect(s.progress_pct).toBe(73);
    }

    set({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: false,
      dismissed: false,
    });
    s = useUpdateStore.getState().status;
    if (s.state === 'ready_to_install') {
      expect(s.deferred).toBe(false);
    }
  });

  it('records the deferred ready_to_install variant', () => {
    const set = useUpdateStore.getState().setStatus;
    set({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: true,
      dismissed: false,
    });
    const s = useUpdateStore.getState().status;
    if (s.state === 'ready_to_install') {
      expect(s.deferred).toBe(true);
    } else {
      throw new Error('expected ready_to_install');
    }
  });

  it('records the failed variant with Swedish copy', () => {
    const set = useUpdateStore.getState().setStatus;
    const failed: UpdateStatus = {
      state: 'failed',
      failure: 'no_network',
      message: 'Kan inte nå GitHub — kontrollera nätverksanslutningen',
      checked_at: '2026-05-28T12:00:00Z',
    };
    set(failed);
    const s = useUpdateStore.getState().status;
    expect(s.state).toBe('failed');
    if (s.state === 'failed') {
      expect(s.failure).toBe('no_network');
      expect(s.message).toContain('GitHub');
    }
  });

  it('records up_to_date with version + timestamp', () => {
    const set = useUpdateStore.getState().setStatus;
    set({ state: 'up_to_date', version: '0.1.0', checked_at: '2026-05-28T12:00:00Z' });
    const s = useUpdateStore.getState().status;
    if (s.state === 'up_to_date') {
      expect(s.version).toBe('0.1.0');
      expect(s.checked_at).toContain('2026-05-28');
    }
  });

  it('records restarting with the new version', () => {
    const set = useUpdateStore.getState().setStatus;
    set({ state: 'restarting', version: '0.2.0' });
    const s = useUpdateStore.getState().status;
    if (s.state === 'restarting') {
      expect(s.version).toBe('0.2.0');
    }
  });
});
