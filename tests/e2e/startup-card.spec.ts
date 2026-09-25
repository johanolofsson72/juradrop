import { test, expect } from './support/fixtures';

// Spec 051 — the startup card in the real bundle (Vite build + mocked Tauri
// bridge). Covers the storage round-trip across real page reloads, which the
// jsdom suite can only simulate. SC-157/158/160/161/162.

const KEY = 'juradrop-startup';
const card = '[data-startup-card]';

test.describe('Spec 051 — startup card', () => {
  test('SC-157/158: a tip shows, and a reload shows the next one', async ({ page }) => {
    await page.addInitScript((key) => {
      if (!sessionStorage.getItem('seeded')) {
        localStorage.setItem(key, JSON.stringify({ tipsEnabled: true, nextTip: 0, lastSeenVersion: 'current' }));
        sessionStorage.setItem('seeded', '1');
      }
    }, KEY);
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    // 'current' != running version → what's-new if notes exist, else a tip.
    const first = page.locator(card);
    await expect(first).toBeVisible();
    if ((await first.getAttribute('data-startup-card')) === 'whats_new') {
      await page.getByRole('button', { name: 'Okej' }).click();
      await page.reload();
    }
    await expect(page.locator('[data-startup-card="tip"]')).toBeVisible();
    const tipA = await page.locator(`${card} p`).textContent();
    await page.reload();
    await expect(page.locator('[data-startup-card="tip"]')).toBeVisible();
    const tipB = await page.locator(`${card} p`).textContent();
    expect(tipB).not.toBe(tipA);
  });

  test('SC-160: × hides the card', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator(card)).toBeVisible();
    await page.locator(card).getByRole('button', { name: 'Stäng' }).click();
    await expect(page.locator(card)).toHaveCount(0);
  });

  test('SC-161: turning tips off in Settings survives a reload', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator(card)).toBeVisible();
    await page.keyboard.press('Meta+Comma');
    const panelOpened = await page.getByRole('checkbox', { name: /Visa tips vid start/ }).isVisible();
    if (!panelOpened) await page.getByRole('button', { name: /Inställningar/ }).click();
    const box = page.getByRole('checkbox', { name: /Visa tips vid start/ });
    await expect(box).toBeChecked();
    await box.uncheck();
    const stored = await page.evaluate((k) => JSON.parse(localStorage.getItem(k) ?? '{}'), KEY);
    expect(stored.tipsEnabled).toBe(false);
    await page.reload();
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    await expect(page.locator('[data-startup-card="tip"]')).toHaveCount(0);
  });

  for (const colorScheme of ['light', 'dark'] as const) {
    test.describe(`visual — ${colorScheme}`, () => {
      test.use({ colorScheme });
      test(`card renders in ${colorScheme} mode`, async ({ page }) => {
        await page.goto('/');
        await expect(page.locator(card)).toBeVisible();
        await page.screenshot({
          path: `test-results/startup-card-${colorScheme}.png`,
          clip: { x: 0, y: 0, width: 1100, height: 420 },
        });
      });
    });
  }
});
