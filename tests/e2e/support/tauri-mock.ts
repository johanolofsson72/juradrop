// Spec 033 — the mock Tauri IPC bridge.
//
// `installTauriMock` is injected via Playwright `page.addInitScript` and runs
// in the BROWSER context BEFORE the app bundle evaluates (FR-003). It MUST be
// fully self-contained — no references to module-scope values — because
// Playwright serializes it with `Function.prototype.toString`. The only input
// is the `canned` argument (a JSON-serializable CannedState).
//
// It reproduces the @tauri-apps/api v2.11 contract (read from
// node_modules/@tauri-apps/api/{core,event}.js):
//   - window.__TAURI_INTERNALS__.invoke(cmd, payload, options): Promise
//   - window.__TAURI_INTERNALS__.transformCallback(cb, once): number
//   - window.__TAURI_INTERNALS__.unregisterCallback(id): void
// plus a test-facing control surface window.__JURADROP_TEST__.
//
// See specs/033-frontend-playwright-smoke/contracts/mock-bridge-contract.md.

import type { CannedState } from './canned-state';

export interface InvocationRecord {
  command: string;
  payload: unknown;
  result: 'resolved' | 'rejected';
}

export interface JuradropTest {
  emit(event: string, payload: unknown): number;
  invocations(): InvocationRecord[];
  setCanned(partial: Partial<CannedState>): void;
  listenerCount(event: string): number;
}

declare global {
  interface Window {
    __TAURI_INTERNALS__?: {
      invoke(cmd: string, payload?: unknown, options?: unknown): Promise<unknown>;
      transformCallback(cb: (arg: unknown) => void, once?: boolean): number;
      unregisterCallback(id: number): void;
      metadata?: unknown;
    };
    __JURADROP_TEST__?: JuradropTest;
  }
}

export function installTauriMock(canned: CannedState): void {
  // ---- internal state (per page) ----
  const callbacks = new Map<number, { fn: (arg: unknown) => void; once: boolean }>();
  const listeners: Array<{
    event: string;
    callbackId: number;
    eventId: number;
    live: boolean;
  }> = [];
  const log: Array<{ command: string; payload: unknown; result: 'resolved' | 'rejected' }> = [];
  let nextCallbackId = 1;
  let nextEventId = 1;
  // Mutable working copy so __JURADROP_TEST__.setCanned can override at runtime.
  const state: CannedState = JSON.parse(JSON.stringify(canned));

  // ---- command dispatch table ----
  // Returns a value for read commands; `undefined` (void) for action commands.
  // Throwing here is NOT how unmocked commands are handled — they are simply
  // absent from this table and rejected by invoke() below (FR-009).
  const UNMOCKED = Symbol('unmocked');
  function dispatch(cmd: string, payload: unknown): unknown {
    switch (cmd) {
      // --- read commands ---
      case 'get_status':
        return state.status;
      case 'get_settings':
        return state.settings;
      case 'get_tier_pull_state':
        return state.tierPull;
      case 'get_tier_download_state':
        return state.tierDownload;
      case 'get_diagnostics_status':
        return state.diagnostics;
      case 'set_diagnostics_enabled': {
        const enabled = !!(payload as { enabled?: boolean } | undefined)?.enabled;
        state.diagnostics = { ...state.diagnostics, enabled };
        return state.diagnostics;
      }
      case 'get_app_version':
        return state.appVersion;
      // --- the native picker ---
      case 'plugin:dialog|open':
        // plugin-dialog's open() invokes with { options }. We ignore the
        // filter/options and return the canned path (or null = cancelled).
        return state.pickerResult;
      // --- void action commands (recorded, resolve undefined) ---
      case 'give_consent':
      case 'cancel_consent':
      case 'run_roundtrip_dev':
      case 'cancel_model_pull':
      case 'cancel_summary':
      case 'dispatch_to_zone':
      case 'set_model_tier':
      case 'start_tier_download':
      case 'cancel_tier_download':
      case 'check_for_updates_now':
      case 'install_update_now':
      case 'confirm_restart_install':
      case 'cancel_deferred_restart':
      case 'dismiss_update_indicator':
        return undefined;
      default:
        // Sentinel: command not in the table.
        return UNMOCKED;
    }
  }

  // ---- the SDK-facing bridge ----
  window.__TAURI_INTERNALS__ = {
    transformCallback(cb: (arg: unknown) => void, once?: boolean): number {
      const id = nextCallbackId++;
      callbacks.set(id, { fn: cb, once: !!once });
      return id;
    },
    unregisterCallback(id: number): void {
      callbacks.delete(id);
      for (const l of listeners) {
        if (l.callbackId === id) l.live = false;
      }
    },
    invoke(cmd: string, payload?: unknown, _options?: unknown): Promise<unknown> {
      // Event-plugin plumbing — not logged as a "command".
      if (cmd === 'plugin:event|listen') {
        const p = (payload ?? {}) as { event?: string; handler?: number };
        const eventId = nextEventId++;
        listeners.push({
          event: String(p.event),
          callbackId: Number(p.handler),
          eventId,
          live: true,
        });
        return Promise.resolve(eventId);
      }
      if (cmd === 'plugin:event|unlisten') {
        const p = (payload ?? {}) as { eventId?: number };
        for (const l of listeners) {
          if (l.eventId === p.eventId) l.live = false;
        }
        return Promise.resolve(undefined);
      }

      const result = dispatch(cmd, payload);
      if (result === UNMOCKED) {
        log.push({ command: cmd, payload, result: 'rejected' });
        return Promise.reject(new Error('unmocked command: ' + cmd));
      }
      log.push({ command: cmd, payload, result: 'resolved' });
      return Promise.resolve(result);
    },
    metadata: {
      currentWindow: { label: 'main' },
      currentWebview: { windowLabel: 'main', label: 'main' },
    },
  };

  // ---- the test-facing control surface ----
  window.__JURADROP_TEST__ = {
    emit(event: string, payload: unknown): number {
      let delivered = 0;
      for (const l of listeners) {
        if (!l.live || l.event !== event) continue;
        const entry = callbacks.get(l.callbackId);
        if (!entry) continue;
        delivered++;
        // The shape @tauri-apps/api's listen() handler expects.
        entry.fn({ event, id: l.eventId, payload });
        if (entry.once) {
          l.live = false;
          callbacks.delete(l.callbackId);
        }
      }
      return delivered;
    },
    invocations(): InvocationRecord[] {
      return log.map((r) => ({ ...r }));
    },
    setCanned(partial: Partial<CannedState>): void {
      Object.assign(state, partial);
    },
    listenerCount(event: string): number {
      return listeners.filter((l) => l.live && l.event === event).length;
    },
  };
}
