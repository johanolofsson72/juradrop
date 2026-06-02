import { test, expect } from './support/fixtures';

// FR-017 — pin the @tauri-apps/api v2.11 IPC contract the mock bridge depends
// on, so a future SDK bump that breaks it fails loudly here rather than
// silently de-fanging the whole smoke suite.
//
// Strategy (no bundling the SDK into the test):
//   (a) After boot the REAL app, via the REAL @tauri-apps/api, must have
//       registered listeners on known channels. That only happens if listen()
//       called transformCallback(handler) then invoke('plugin:event|listen',
//       { handler: <id> }) exactly as our bridge expects. listenerCount > 0
//       proves the transformCallback→invoke routing end to end.
//   (b) An emitted event must reach a React state change — proving the SDK's
//       listen wrapper unwraps the { event, id, payload } shape we deliver.
//   (c) An unknown command must reject with a clear "unmocked command:"
//       message (FR-009) — never silently resolve undefined.

const ZONE = 'juradrop://zone/sammanfatta';

test.describe('FR-017 — @tauri-apps/api contract pin', () => {
  test('the app established listeners via the real SDK routing (a)', async ({ page, juradrop }) => {
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();

    await expect.poll(() => juradrop.listenerCount('juradrop://status')).toBeGreaterThan(0);
    await expect.poll(() => juradrop.listenerCount(ZONE)).toBeGreaterThan(0);
  });

  test('emitted {event,id,payload} is unwrapped by the SDK into a state change (b)', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    await expect(page.locator('[data-zone-id="sammanfatta"]')).toBeVisible();
    await expect.poll(() => juradrop.listenerCount(ZONE)).toBeGreaterThan(0);

    const delivered = await juradrop.emit(ZONE, {
      state: 'processing',
      disabled: false,
      failure: null,
      job_id: 'job-1',
      progress_hint: 'Sammanfattar…',
    });
    expect(delivered).toBeGreaterThanOrEqual(1);
    await expect(
      page.locator('[data-zone-id="sammanfatta"][data-state="processing"]'),
    ).toBeVisible();
  });

  test('an unmocked command rejects loudly (c) — FR-009', async ({ page }) => {
    await page.goto('/');
    const message = await page.evaluate(async () => {
      try {
        await window.__TAURI_INTERNALS__!.invoke('definitely_not_a_real_command_xyz', {});
        return null;
      } catch (e) {
        return (e as Error).message;
      }
    });
    expect(message).toContain('unmocked command:');
  });
});
