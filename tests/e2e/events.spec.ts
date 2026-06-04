import { test, expect } from './support/fixtures';

// US6 — the live event channels: backend-pushed events delivered through the
// mocked bridge's emit() must reach a React state update. This exercises the
// most Tauri-internal-coupled plumbing (listen → transformCallback → backend
// emit → {event,id,payload}). We wait for the subscription to be live
// (listenerCount > 0) before emitting, since an event with no listener drops.

const ZONE = 'juradrop://zone/sammanfatta';

function snapshot(state: string, hint: string | null = null) {
  return { state, disabled: false, failure: null, job_id: 'job-1', progress_hint: hint };
}

test.describe('US6 — live event channels', () => {
  test('emitted zone snapshot drives the zone into processing (AS1)', async ({ page, juradrop }) => {
    await page.goto('/');
    await expect(page.locator('[data-zone-id="sammanfatta"]')).toBeVisible();
    await expect.poll(() => juradrop.listenerCount(ZONE)).toBeGreaterThan(0);

    await juradrop.emit(ZONE, snapshot('processing', 'Sammanfattar…'));
    await expect(
      page.locator('[data-zone-id="sammanfatta"][data-state="processing"]'),
    ).toBeVisible();
  });

  test('emitted snapshots drive success then error in turn (AS2)', async ({ page, juradrop }) => {
    await page.goto('/');
    await expect(page.locator('[data-zone-id="sammanfatta"]')).toBeVisible();
    await expect.poll(() => juradrop.listenerCount(ZONE)).toBeGreaterThan(0);

    await juradrop.emit(ZONE, snapshot('success'));
    await expect(page.locator('[data-zone-id="sammanfatta"][data-state="success"]')).toBeVisible();

    await juradrop.emit(ZONE, { ...snapshot('error'), failure: 'parse_error' });
    await expect(page.locator('[data-zone-id="sammanfatta"][data-state="error"]')).toBeVisible();
  });

  test('emitted status transition re-renders without reload (AS3)', async ({ page, juradrop }) => {
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    await expect.poll(() => juradrop.listenerCount('juradrop://status')).toBeGreaterThan(0);

    await juradrop.emit('juradrop://status', {
      visible: 'begar_samtycke',
      sidecar: 'starting',
      model: 'not_present',
      progress_percent: null,
      consent: 'not_asked',
    });

    await expect(
      page.getByRole('dialog').filter({ hasText: 'Ladda ner AI-modell' }),
    ).toBeVisible();
  });

  test('emit returns delivery count; no-listener emit is a no-op (FR-010)', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    await expect(page.locator('[data-zone-id="sammanfatta"]')).toBeVisible();
    await expect.poll(() => juradrop.listenerCount(ZONE)).toBeGreaterThan(0);

    const delivered = await juradrop.emit(ZONE, snapshot('processing'));
    expect(delivered).toBeGreaterThanOrEqual(1);

    const none = await juradrop.emit('juradrop://nonexistent-channel', {});
    expect(none).toBe(0);
  });

  // Spec 038 T015/T017(9) — multi-chunk per-part progress rides the existing
  // progress_hint surface: successive processing snapshots must re-render the
  // advancing Swedish hint inside the zone (the zone's accessible content),
  // then the combine hint, then the normal success flow.
  test('chunked-run progress hints render and advance in the zone (spec 038)', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    const zone = page.locator('[data-zone-id="sammanfatta"]');
    await expect(zone).toBeVisible();
    await expect.poll(() => juradrop.listenerCount(ZONE)).toBeGreaterThan(0);

    await juradrop.emit(ZONE, snapshot('processing', 'Bearbetar del 1 av 5…'));
    await expect(zone).toContainText('Bearbetar del 1 av 5…');

    await juradrop.emit(ZONE, snapshot('processing', 'Bearbetar del 2 av 5…'));
    await expect(zone).toContainText('Bearbetar del 2 av 5…');
    await expect(zone).not.toContainText('Bearbetar del 1 av 5…');

    await juradrop.emit(ZONE, snapshot('processing', 'Sammanställer…'));
    await expect(zone).toContainText('Sammanställer…');

    await juradrop.emit(ZONE, snapshot('success', 'Klar — öppnar fil…'));
    await expect(
      page.locator('[data-zone-id="sammanfatta"][data-state="success"]'),
    ).toBeVisible();
  });
});
