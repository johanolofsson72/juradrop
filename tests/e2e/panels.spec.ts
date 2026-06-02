import { test, expect } from './support/fixtures';

// US4 — the settings + help slide-in panels and their mutual exclusion
// (spec 010 / 013). Panel roots carry stable markers:
//   settings → [data-settings-panel] (mounted while visibility !== 'closed')
//   help     → [data-help-panel]
// Both panels render fixed inset-0 z-50, so while one is open its scrim
// covers the z-40 chrome icons — the other icon is not click-reachable. The
// reachable mutual-exclusion path is keyboard: Cmd+, opens settings and
// closes help (useCmdComma → toggleSettingsPanel → helpPanel.closePanel()).

test.describe('US4 — panels', () => {
  test('gear icon opens the settings panel (AS1)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('[data-settings-gear]')).toBeVisible();
    await page.locator('[data-settings-gear]').click();
    await expect(page.locator('[data-settings-panel]')).toBeVisible();
  });

  test('Cmd+, toggles the settings panel open then closed (AS2)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();

    await page.keyboard.press('Meta+Comma');
    await expect(page.locator('[data-settings-panel]')).toBeVisible();

    await page.keyboard.press('Meta+Comma');
    // closing → closed → unmounts; toHaveCount(0) auto-retries through the anim.
    await expect(page.locator('[data-settings-panel]')).toHaveCount(0);
  });

  test('opening one panel closes the other — mutual exclusion (AS3)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('[data-help-icon]')).toBeVisible();

    // Open help first (nothing covering the icon yet).
    await page.locator('[data-help-icon]').click();
    await expect(page.locator('[data-help-panel]')).toBeVisible();

    // Cmd+, while help is open → settings opens, help closes (at most one open).
    await page.keyboard.press('Meta+Comma');
    await expect(page.locator('[data-settings-panel]')).toBeVisible();
    await expect(page.locator('[data-help-panel]')).toHaveCount(0);
  });
});
