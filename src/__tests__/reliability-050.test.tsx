// Spec 050 — reliability fixes (frontend half).
//   FR-009 — no silent IPC failure: consent + drop dispatch surface fixed
//            Swedish copy via role="alert".
//   FR-010 — listeners never leak: late-resolving `listen()` is still
//            unlistened; status is subscribed BEFORE it is read.
// Functional (one per function) + destructive (rejection, double-fire,
// reject-then-succeed, unmount mid-flight) coverage.

import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { StrictMode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const bridge = vi.hoisted(() => ({
  giveConsent: vi.fn<() => Promise<void>>(),
  cancelConsent: vi.fn<() => Promise<void>>(),
  dispatchToZone: vi.fn<() => Promise<void>>(),
  getStatus: vi.fn(),
  calls: [] as string[],
  unlistens: [] as Array<ReturnType<typeof vi.fn>>,
  resolvers: [] as Array<() => void>,
  deferListen: false,
  handlers: {} as Record<string, (payload: unknown) => void>,
}));

vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  const fakeListen = (name: string) => (...args: unknown[]) => {
    bridge.calls.push(name);
    const cb = args.find((a) => typeof a === 'function');
    if (cb) bridge.handlers[name] = cb as (payload: unknown) => void;
    const unlisten = vi.fn();
    bridge.unlistens.push(unlisten);
    if (!bridge.deferListen) return Promise.resolve(unlisten);
    return new Promise<() => void>((resolve) => {
      bridge.resolvers.push(() => resolve(unlisten));
    });
  };
  // Fake EVERY subscribe* export so no real listen() runs without a Tauri host.
  const allSubs = Object.fromEntries(
    Object.keys(actual)
      .filter((k) => k.startsWith('subscribe'))
      .map((k) => [k, fakeListen(k)]),
  );
  return {
    ...actual,
    ...allSubs,
    getUpdateStatus: () => Promise.resolve(null),
    getTierPullState: () => Promise.resolve(null),
    getSettings: () => Promise.resolve(null),
    giveConsent: () => bridge.giveConsent(),
    cancelConsent: () => bridge.cancelConsent(),
    dispatchToZone: () => bridge.dispatchToZone(),
    getStatus: () => {
      bridge.calls.push('getStatus');
      return bridge.getStatus();
    },
    subscribeStatus: fakeListen('subscribeStatus'),
    subscribeProgress: fakeListen('subscribeProgress'),
    subscribeFileDropped: fakeListen('subscribeFileDropped'),
    subscribeFileDragOver: fakeListen('subscribeFileDragOver'),
    subscribeFileDragLeave: fakeListen('subscribeFileDragLeave'),
    subscribeZone: fakeListen('subscribeZone'),
  };
});

import { ActionErrorNotice } from '@/components/ActionErrorNotice';
import { ConsentModal } from '@/components/ConsentModal';
import { FirstRunProgress } from '@/components/FirstRunProgress';
import { WelcomeWizard } from '@/components/WelcomeWizard';
import { disposable } from '@/lib/listen-lifecycle';
import { DEFAULT_MODEL_DOWNLOAD } from '@/lib/model-download';
import { ACTION_ERRORS, useStatusStore } from '@/lib/status-store';
import { WIZARD_STRINGS } from '@/lib/wizard-strings';
import { App, dispatchDrop } from '../App';

const flush = () => act(async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
});

function setStatus(patch: Partial<ReturnType<typeof useStatusStore.getState>['status']>) {
  useStatusStore.setState((s) => ({ status: { ...s.status, ...patch } }));
}

beforeEach(() => {
  bridge.giveConsent.mockReset().mockResolvedValue(undefined);
  bridge.cancelConsent.mockReset().mockResolvedValue(undefined);
  bridge.dispatchToZone.mockReset().mockResolvedValue(undefined);
  bridge.getStatus.mockReset().mockResolvedValue({
    visible: 'klar', sidecar: 'ready', model: 'ready', progress_percent: null, consent: 'fortsatt',
  });
  bridge.calls = [];
  bridge.unlistens = [];
  bridge.resolvers = [];
  bridge.deferListen = false;
  bridge.handlers = {};
  useStatusStore.setState({ actionFailure: null });
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
});

// ─── FR-010 — disposable() ──────────────────────────────────────────────
describe('disposable (FR-010)', () => {
  it('unlistens immediately when stopped after the promise resolved', async () => {
    const unlisten = vi.fn();
    const stop = disposable(Promise.resolve(unlisten));
    await flush();
    stop();
    expect(unlisten).toHaveBeenCalledTimes(1);
  });

  it('unlistens on arrival when stopped BEFORE the promise resolved', async () => {
    const unlisten = vi.fn();
    let resolve!: (fn: () => void) => void;
    const stop = disposable(new Promise((r) => (resolve = r)));
    stop();
    expect(unlisten).not.toHaveBeenCalled();
    resolve(unlisten);
    await flush();
    expect(unlisten).toHaveBeenCalledTimes(1);
  });

  it('never unlistens twice (double stop)', async () => {
    const unlisten = vi.fn();
    const stop = disposable(Promise.resolve(unlisten));
    await flush();
    stop();
    stop();
    expect(unlisten).toHaveBeenCalledTimes(1);
  });

  it('does not unlisten a live subscription', async () => {
    const unlisten = vi.fn();
    disposable(Promise.resolve(unlisten));
    await flush();
    expect(unlisten).not.toHaveBeenCalled();
  });

  it('swallows a rejected subscription (no unhandled rejection)', async () => {
    const stop = disposable(Promise.reject(new Error('listen failed')));
    await flush();
    expect(() => stop()).not.toThrow();
  });
});

// ─── FR-009 — store actions ─────────────────────────────────────────────
describe('status-store consent actions (FR-009)', () => {
  it('giveConsent success leaves no error', async () => {
    await useStatusStore.getState().giveConsent();
    expect(useStatusStore.getState().actionFailure).toBeNull();
  });

  it('giveConsent rejection surfaces the Swedish consent error and resolves', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('disk'));
    await expect(useStatusStore.getState().giveConsent()).resolves.toBeUndefined();
    expect(useStatusStore.getState().actionFailure).toBe(ACTION_ERRORS.consent);
  });

  it('cancelConsent rejection surfaces the Swedish consent error', async () => {
    bridge.cancelConsent.mockRejectedValueOnce('io');
    await useStatusStore.getState().cancelConsent();
    expect(useStatusStore.getState().actionFailure).toBe(ACTION_ERRORS.consent);
  });

  it('a later success clears a previous failure', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('x'));
    await useStatusStore.getState().giveConsent();
    await useStatusStore.getState().giveConsent();
    expect(useStatusStore.getState().actionFailure).toBeNull();
  });

  it('never leaks the raw error text into the UI copy', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('EACCES /Users/x/Library/secret'));
    await useStatusStore.getState().giveConsent();
    expect(useStatusStore.getState().actionFailure).not.toMatch(/EACCES|Users/);
  });
});

describe('dispatchDrop (FR-009)', () => {
  it('success leaves no error', async () => {
    await dispatchDrop('sammanfatta', ['/tmp/a.docx']);
    expect(useStatusStore.getState().actionFailure).toBeNull();
  });

  it('rejection surfaces the Swedish dispatch error', async () => {
    bridge.dispatchToZone.mockRejectedValueOnce(new Error('ipc'));
    await expect(dispatchDrop('sammanfatta', ['/tmp/a.docx'])).resolves.toBeUndefined();
    expect(useStatusStore.getState().actionFailure).toBe(ACTION_ERRORS.dispatch);
  });

  it('a successful drop after a failed one clears the error', async () => {
    bridge.dispatchToZone.mockRejectedValueOnce(new Error('ipc'));
    await dispatchDrop('anonymisera', ['/tmp/a.pdf']);
    await dispatchDrop('anonymisera', ['/tmp/a.pdf']);
    expect(useStatusStore.getState().actionFailure).toBeNull();
  });
});

describe('ActionErrorNotice (FR-009)', () => {
  it('renders nothing without an error', () => {
    const { container } = render(<ActionErrorNotice />);
    expect(container).toBeEmptyDOMElement();
  });

  it('renders the message as an alert', () => {
    useStatusStore.setState({ actionFailure: ACTION_ERRORS.consent });
    render(<ActionErrorNotice />);
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });
});

// ─── FR-009 — the three consent surfaces (functional + destructive) ─────
describe('WelcomeWizard consent failures (FR-009)', () => {
  beforeEach(() => setStatus({ sidecar: 'ready', consent: 'not_asked', visible: 'begar_samtycke' }));

  it('Fortsätt rejection shows the Swedish alert', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('x'));
    render(<WelcomeWizard />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.welcome_cta_primary));
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });

  it('Avbryt rejection shows the Swedish alert', async () => {
    bridge.cancelConsent.mockRejectedValueOnce(new Error('x'));
    render(<WelcomeWizard />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.welcome_cta_secondary));
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });

  it('Escape rejection shows the Swedish alert', async () => {
    bridge.cancelConsent.mockRejectedValueOnce(new Error('x'));
    render(<WelcomeWizard />);
    fireEvent.keyDown(document, { key: 'Escape' });
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });

  it('double-click Fortsätt with both failing shows ONE alert', async () => {
    bridge.giveConsent.mockRejectedValue(new Error('x'));
    render(<WelcomeWizard />);
    const btn = screen.getByText(WIZARD_STRINGS.welcome_cta_primary);
    fireEvent.click(btn);
    fireEvent.click(btn);
    await flush();
    expect(screen.getAllByRole('alert')).toHaveLength(1);
  });

  it('retry after a failure clears the alert', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('x'));
    render(<WelcomeWizard />);
    const btn = screen.getByText(WIZARD_STRINGS.welcome_cta_primary);
    fireEvent.click(btn);
    await flush();
    fireEvent.click(btn);
    await flush();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('shows the real download size in the welcome copy (FR-006)', () => {
    render(<WelcomeWizard />);
    expect(screen.getByText(WIZARD_STRINGS.welcome_download_note)).toHaveTextContent(
      `cirka ${DEFAULT_MODEL_DOWNLOAD.label}`,
    );
  });
});

describe('ConsentModal consent failures (FR-009)', () => {
  beforeEach(() => setStatus({ visible: 'begar_samtycke', consent: 'not_asked' }));

  it('Fortsätt rejection shows the Swedish alert inside the dialog', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('x'));
    render(<ConsentModal />);
    fireEvent.click(screen.getByRole('button', { name: 'Fortsätt' }));
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });

  it('Avbryt rejection shows the Swedish alert inside the dialog', async () => {
    bridge.cancelConsent.mockRejectedValueOnce(new Error('x'));
    render(<ConsentModal />);
    fireEvent.click(screen.getByRole('button', { name: 'Avbryt' }));
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });

  it('names the real download size (FR-006)', () => {
    render(<ConsentModal />);
    expect(screen.getByText(/från ollama\.com/)).toHaveTextContent(
      `~${DEFAULT_MODEL_DOWNLOAD.label}`,
    );
  });
});

describe('FirstRunProgress error panel (FR-003 + FR-009)', () => {
  beforeEach(() => setStatus({ visible: 'fel_modellnedladdning_avbroten', consent: 'fortsatt', model: 'download_failed' }));

  it('Försök igen calls give_consent', async () => {
    render(<FirstRunProgress />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.progress_error_retry));
    await flush();
    expect(bridge.giveConsent).toHaveBeenCalledTimes(1);
  });

  it('Avbryt calls cancel_consent (the Rust guard now honours it)', async () => {
    render(<FirstRunProgress />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.welcome_cta_secondary));
    await flush();
    expect(bridge.cancelConsent).toHaveBeenCalledTimes(1);
  });

  it('Försök igen rejection shows the Swedish alert', async () => {
    bridge.giveConsent.mockRejectedValueOnce(new Error('x'));
    render(<FirstRunProgress />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.progress_error_retry));
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });

  it('Avbryt rejection shows the Swedish alert', async () => {
    bridge.cancelConsent.mockRejectedValueOnce(new Error('x'));
    render(<FirstRunProgress />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.welcome_cta_secondary));
    await flush();
    expect(screen.getByRole('alert')).toHaveTextContent(ACTION_ERRORS.consent);
  });
});

// ─── FR-010 — App listener lifecycle ────────────────────────────────────
describe('App listener lifecycle (FR-010)', () => {
  beforeEach(() => {
    (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
    setStatus({ visible: 'klar', sidecar: 'ready', model: 'ready', consent: 'fortsatt' });
  });

  it('subscribes to status BEFORE reading the seed', async () => {
    render(<App />);
    await flush();
    const sub = bridge.calls.indexOf('subscribeStatus');
    const read = bridge.calls.indexOf('getStatus');
    expect(sub).toBeGreaterThanOrEqual(0);
    expect(read).toBeGreaterThan(sub);
  });

  it('unmount before listen() resolves still unlistens everything', async () => {
    bridge.deferListen = true;
    const { unmount } = render(<App />);
    unmount();
    bridge.resolvers.forEach((r) => r());
    await flush();
    expect(bridge.unlistens.length).toBeGreaterThan(0);
    bridge.unlistens.forEach((u) => expect(u).toHaveBeenCalledTimes(1));
  });

  it('StrictMode double-mount leaves exactly one live drop listener', async () => {
    bridge.deferListen = true;
    render(
      <StrictMode>
        <App />
      </StrictMode>,
    );
    bridge.resolvers.forEach((r) => r());
    await flush();
    const dropIdx = bridge.calls
      .map((c, i) => (c === 'subscribeFileDropped' ? i : -1))
      .filter((i) => i >= 0);
    expect(dropIdx).toHaveLength(2);
    // Map call order → unlisten mock: one disposed, one live.
    const listenCalls = bridge.calls.filter((c) => c !== 'getStatus');
    const dropUnlistens = listenCalls
      .map((c, i) => (c === 'subscribeFileDropped' ? bridge.unlistens[i] : undefined))
      .filter(Boolean);
    const disposedCount = dropUnlistens.filter((u) => u!.mock.calls.length > 0).length;
    expect(disposedCount).toBe(1);
  });

  it('applies the seed when no event arrived first', async () => {
    bridge.getStatus.mockResolvedValueOnce({
      visible: 'startar', sidecar: 'starting', model: 'not_present', progress_percent: null, consent: 'fortsatt',
    });
    render(<App />);
    await flush();
    expect(useStatusStore.getState().status.visible).toBe('startar');
  });

  it('a stale seed never overwrites a newer event', async () => {
    let resolveSeed!: (v: unknown) => void;
    bridge.getStatus.mockReturnValueOnce(new Promise((r) => (resolveSeed = r)));
    render(<App />);
    await flush();
    act(() =>
      bridge.handlers.subscribeStatus!({
        visible: 'klar', sidecar: 'ready', model: 'ready', progress_percent: null, consent: 'fortsatt',
      }),
    );
    resolveSeed({
      visible: 'startar', sidecar: 'starting', model: 'not_present', progress_percent: null, consent: 'fortsatt',
    });
    await flush();
    expect(useStatusStore.getState().status.visible).toBe('klar');
  });
});
