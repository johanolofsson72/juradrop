import { test, expect } from './support/fixtures';

// US1 — boot the real frontend in Chromium against the mocked backend.
// The bridge is injected before the bundle (fixtures.ts), so the app seeds
// from canned get_status (default: klar) and renders the grid.

test.describe('US1 — boot to grid', () => {
  test('boots past the wizard to the 3×3 zone grid at klar (AS1)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    // Wizard owns the viewport while visible; at klar it must be gone.
    await expect(page.locator('#wizard-title')).toHaveCount(0);
  });

  test('no uncaught errors and no error-boundary fallback after boot (AS2)', async ({ page }) => {
    const pageErrors: string[] = [];
    page.on('pageerror', (err) => pageErrors.push(err.message));

    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();

    // The ErrorBoundary fallback offers a restart button with Swedish copy;
    // the grid being visible already implies it did not trip, but assert the
    // page produced zero uncaught exceptions explicitly.
    expect(pageErrors, `uncaught errors: ${pageErrors.join(' | ')}`).toEqual([]);
  });

  test('makes no non-localhost network request — Principle I / FR-013 (AS3)', async ({ page }) => {
    const offHost: string[] = [];
    page.on('request', (req) => {
      const host = new URL(req.url()).hostname;
      const local = host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '';
      if (!local) offHost.push(req.url());
    });

    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    // Let any deferred boot requests settle.
    await page.waitForTimeout(250);

    expect(offHost, `unexpected off-host requests: ${offHost.join(' | ')}`).toEqual([]);
  });
});
