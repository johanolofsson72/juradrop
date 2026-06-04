import { test, expect } from './support/fixtures';
import { withCanned } from './support/canned-state';

// US5 — the click-to-browse picker path (spec 016, the accessible alternative
// to OS drag-drop, and the only dispatch path drivable without simulating a
// native drag). "Välj fil" → pickFileForZone → plugin:dialog|open → on a
// string result, dispatch_to_zone(zoneId, [path]); on null (cancel), nothing.

test.describe('US5 — picker dispatches the chosen file', () => {
  test.use({ canned: withCanned({ pickerResult: '/Users/x/avtal.docx' }) });

  test('Välj fil → dispatch_to_zone with zoneId + path (AS1)', async ({ page, juradrop }) => {
    await page.goto('/');
    const pick = page.locator('[data-zone-pick="sammanfatta"]');
    await expect(pick).toBeVisible();
    await pick.click();

    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);

    const dispatch = (await juradrop.invocations()).find((i) => i.command === 'dispatch_to_zone');
    // Spec 041 — the dormant instruction field rides along as null.
    expect(dispatch?.payload).toEqual({
      zoneId: 'sammanfatta',
      paths: ['/Users/x/avtal.docx'],
      instruction: null,
    });
  });
});

test.describe('US5 — cancelled picker dispatches nothing', () => {
  test.use({ canned: withCanned({ pickerResult: null }) });

  test('Välj fil with a cancelled picker records no dispatch (AS2)', async ({ page, juradrop }) => {
    await page.goto('/');
    const pick = page.locator('[data-zone-pick="kontakter"]');
    await expect(pick).toBeVisible();
    await pick.click();

    // The picker WAS invoked; the dispatch was not.
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'plugin:dialog|open'),
      )
      .toBe(true);
    await page.waitForTimeout(200);
    const invocations = await juradrop.invocations();
    expect(invocations.some((i) => i.command === 'dispatch_to_zone')).toBe(false);
  });
});
