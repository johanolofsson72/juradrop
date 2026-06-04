// Spec 042 — PrivacyBadge e2e: visibility across states (T006) + the
// destructive sweep scaled to a static feature (T012).
//
// ===== FUNCTIONAL COVERAGE INVENTORY (e2e scope) =====
// 1. Badge visible at ready state with the accessible claim text
// 2. Badge text unchanged through processing/error/success (standing fact)
// 3. Badge + bottom grid row fit the default viewport without scroll
// 4. Badge still in DOM with the help panel open
// =====================================================
//
// ===== DESTRUCTIVE SWEEP (static feature — interactive attack surface
// is nil BY DESIGN; scaled per the spec-033 precedent, rationale in
// tasks.md T012) =====
// D1: zero focusable descendants — keyboard traversal skips the badge
// D2: clicking the badge triggers no IPC invocation
// D3: panel open/close cycle leaves the badge intact
// D4: small viewport keeps the badge rendered (no responsive hide)
// =====================================================

import { test, expect } from './support/fixtures';
import { withCanned } from './support/canned-state';

const BADGE = '[data-privacy-badge]';
const CLAIM = 'Dina dokument bearbetas på din dator och lämnar den aldrig.';

const snap = (state: string, failure: string | null = null) => ({
  state,
  disabled: false,
  failure,
  job_id: state === 'idle' ? null : 'job-privacy-1',
  progress_hint: null,
});

test.describe('privacy badge — functional', () => {
  test('visible at ready state with the accessible claim (F1)', async ({ page }) => {
    await page.goto('/');
    const badge = page.locator(BADGE);
    await expect(badge).toBeVisible();
    await expect(badge).toHaveText(CLAIM);
  });

  test('a standing fact: unchanged through every zone state (F2)', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    for (const s of [
      snap('processing'),
      snap('error', 'model_error'),
      snap('success'),
      snap('idle'),
    ]) {
      await juradrop.emit('juradrop://zone/sammanfatta', s);
      await expect(page.locator(BADGE)).toHaveText(CLAIM);
      await expect(page.locator(BADGE)).toBeVisible();
    }
  });

  test('badge and bottom grid row fit the default viewport without scroll (F3)', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1160, height: 1000 });
    await page.goto('/');
    const badgeBox = await page.locator(BADGE).boundingBox();
    expect(badgeBox).not.toBeNull();
    expect(badgeBox!.y + badgeBox!.height).toBeLessThanOrEqual(1000);
    // The last zone sits above the badge (badge is the colophon).
    const lastZone = page.locator('[data-zone-id="forklara"]');
    const zoneBox = await lastZone.boundingBox();
    expect(zoneBox!.y + zoneBox!.height).toBeLessThanOrEqual(badgeBox!.y);
  });

  test('still in the DOM with the help panel open (F4)', async ({ page }) => {
    await page.goto('/');
    await page.locator('[data-help-icon]').click();
    await expect(page.locator('[data-help-panel]')).toBeVisible();
    await expect(page.locator(BADGE)).toHaveCount(1);
    // And the help panel carries the privacy entry (FR-006 surface check).
    await expect(page.locator('[data-privacy-help]')).toBeVisible();
  });
});

test.describe('privacy badge — destructive (static-feature sweep)', () => {
  test.use({ canned: withCanned({ pickerResult: '/Users/x/avtal.docx' }) });

  test('D1: zero focusable descendants', async ({ page }) => {
    await page.goto('/');
    expect(
      await page.locator(`${BADGE} a, ${BADGE} button, ${BADGE} [tabindex]`).count(),
    ).toBe(0);
  });

  test('D2: clicking the badge triggers no invocation', async ({ page, juradrop }) => {
    await page.goto('/');
    const before = (await juradrop.invocations()).length;
    await page.locator(BADGE).click();
    await page.waitForTimeout(150);
    expect((await juradrop.invocations()).length).toBe(before);
  });

  test('D3: panel open/close cycle leaves the badge intact', async ({ page }) => {
    await page.goto('/');
    await page.locator('[data-help-icon]').click();
    await page.keyboard.press('Escape');
    await expect(page.locator(BADGE)).toHaveText(CLAIM);
  });

  test('D4: small viewport keeps the badge rendered', async ({ page }) => {
    await page.setViewportSize({ width: 600, height: 700 });
    await page.goto('/');
    await expect(page.locator(BADGE)).toHaveCount(1);
  });
});
