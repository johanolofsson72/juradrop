// Spec 033 — Playwright test fixtures.
//
// Extends the base test with:
//   - `canned`  : a per-test-overridable CannedState option (test.use({ canned }))
//   - `page`    : overridden to inject the mock Tauri bridge via addInitScript
//                 BEFORE navigation (FR-003), so '__TAURI_INTERNALS__' in window
//                 is true by the time the app bundle evaluates.
//   - `juradrop`: a node-side handle that drives the in-page test surface
//                 (emit / invocations / listenerCount / setCanned) through
//                 page.evaluate (node→browser; NOT exposeFunction).

import { test as base, expect } from '@playwright/test';

import { defaultCanned, type CannedState } from './canned-state';
import { installTauriMock, type InvocationRecord } from './tauri-mock';

export interface JuradropHandle {
  /** Deliver a backend event to live listeners; resolves to the delivery count. */
  emit(event: string, payload: unknown): Promise<number>;
  /** Snapshot the recorded invoke() calls (event-plugin plumbing excluded). */
  invocations(): Promise<InvocationRecord[]>;
  /** Count live listeners registered for an event channel. */
  listenerCount(event: string): Promise<number>;
  /** Override canned backend state at runtime. */
  setCanned(partial: Partial<CannedState>): Promise<void>;
}

interface Fixtures {
  canned: CannedState;
  juradrop: JuradropHandle;
}

export const test = base.extend<Fixtures>({
  canned: [defaultCanned(), { option: true }],

  page: async ({ page, canned }, use) => {
    // Runs before any page script, on every navigation (FR-003).
    await page.addInitScript(installTauriMock, canned);
    await use(page);
  },

  juradrop: async ({ page }, use) => {
    const handle: JuradropHandle = {
      emit: (event, payload) =>
        page.evaluate(
          ([e, p]) => window.__JURADROP_TEST__!.emit(e as string, p),
          [event, payload] as const,
        ),
      invocations: () =>
        page.evaluate(() => window.__JURADROP_TEST__!.invocations()),
      listenerCount: (event) =>
        page.evaluate((e) => window.__JURADROP_TEST__!.listenerCount(e), event),
      setCanned: (partial) =>
        page.evaluate((p) => window.__JURADROP_TEST__!.setCanned(p), partial),
    };
    await use(handle);
  },
});

export { expect };
