import { test, expect } from './support/fixtures';
import { withCanned } from './support/canned-state';

// README screenshot generator — NOT a test. Renders the real frontend
// against the mocked Tauri bridge and writes the three screenshots that
// README.md embeds from docs/screenshots/. Skipped in normal e2e runs;
// regenerate with:
//
//   README_SCREENSHOTS=1 npx playwright test tests/e2e/readme-screenshots.spec.ts
//
// Viewport matches the real app window (1160×1000, tauri.conf.json) at 2×
// scale so the PNGs are crisp on Retina/GitHub.

const ENABLED = !!process.env.README_SCREENSHOTS;
const OUT = 'docs/screenshots';

test.describe('README screenshots', () => {
  test.skip(!ENABLED, 'screenshot generator — run with README_SCREENSHOTS=1');

  test.use({ viewport: { width: 1160, height: 1000 }, deviceScaleFactor: 2 });

  test.describe('zone grid (dark)', () => {
    test.use({ colorScheme: 'dark' });

    test('captures the 3×4 grid', async ({ page }) => {
      await page.goto('/');
      await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
      await page.waitForTimeout(500); // let entrance animations settle
      await page.screenshot({ path: `${OUT}/zone-grid-dark.png` });
    });
  });

  test.describe('welcome wizard (model download)', () => {
    test.use({
      colorScheme: 'light',
      canned: withCanned({
        status: {
          visible: 'laddar_ner_modell',
          sidecar: 'starting',
          model: 'downloading',
          progress_percent: 47,
          consent: 'fortsatt',
        },
      }),
    });

    test('captures the download progress state', async ({ page, juradrop }) => {
      await page.goto('/');
      await expect(page.locator('#wizard-title')).toBeVisible();
      // The MB counter + ETA derive from juradrop://progress events (not
      // status.progress_percent), and the ETA needs ≥2 samples — emit two
      // so the bar, byte counter, and ETA all agree on 47%.
      await juradrop.emit('juradrop://progress', { percent: 44 });
      await page.waitForTimeout(900);
      await juradrop.emit('juradrop://progress', { percent: 47 });
      await page.waitForTimeout(500);
      await page.screenshot({ path: `${OUT}/welcome-wizard-download.png` });
    });
  });

  test.describe('settings panel', () => {
    // The "Om JuraDrop" card renders appVersion — keep it in sync with
    // package.json so the screenshot doesn't advertise a stale release.
    test.use({ colorScheme: 'light', canned: withCanned({ appVersion: '0.3.0' }) });

    test('captures the open panel', async ({ page }) => {
      await page.goto('/');
      await page.locator('[data-settings-gear]').click();
      await expect(page.locator('[data-settings-panel]')).toBeVisible();
      await page.waitForTimeout(500); // slide-in animation
      await page.screenshot({ path: `${OUT}/settings-panel.png` });
    });
  });
});
