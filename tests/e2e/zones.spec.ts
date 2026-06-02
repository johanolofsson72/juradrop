import { test, expect } from './support/fixtures';
import { withCanned } from './support/canned-state';

// US2 — the core rendered surface: nine labelled zones + chrome, plus the
// first-run wizard welcome screen. Labels are the shipped Swedish titles
// from src/components/DropZone.identity.ts (asserted here as the source of
// truth a regression would break — SC-006).

// Canonical zone order + titles, mirrored from DropZone.identity.ts.
const ZONES: Array<{ slug: string; title: string }> = [
  { slug: 'sammanfatta', title: 'Sammanfatta' },
  { slug: 'tillengelska', title: 'Till engelska' },
  { slug: 'tillsvenska', title: 'Till svenska' },
  { slug: 'punktlista', title: 'Punktlista' },
  { slug: 'anonymisera', title: 'Anonymisera' },
  { slug: 'forenkla', title: 'Förenkla' },
  { slug: 'kontakter', title: 'Plocka ut kontaktuppgifter' },
  { slug: 'generera', title: 'Generera juridisk text' },
  { slug: 'kallor', title: 'Källförteckning' },
];

test.describe('US2 — core rendered surface', () => {
  test('renders exactly nine drop zones with their data-zone-id (AS1)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    await expect(page.locator('[data-zone-id]')).toHaveCount(9);
    for (const { slug } of ZONES) {
      await expect(page.locator(`[data-zone-id="${slug}"]`)).toBeVisible();
    }
  });

  test('each zone shows its correct Swedish title (AS1)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toBeVisible();
    for (const { slug, title } of ZONES) {
      await expect(page.locator(`[data-zone-id="${slug}"] h2`)).toHaveText(title);
    }
  });

  test('both chrome icons are visible at the ready state (AS2)', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('[data-settings-gear]')).toBeVisible();
    await expect(page.locator('[data-help-icon]')).toBeVisible();
  });
});

test.describe('US2 — first-run wizard welcome (AS3)', () => {
  test.use({
    canned: withCanned({
      status: {
        visible: 'begar_samtycke',
        sidecar: 'starting',
        model: 'not_present',
        progress_percent: null,
        consent: 'not_asked',
      },
    }),
  });

  test('fresh install shows the wizard welcome screen; the grid is absent', async ({ page }) => {
    await page.goto('/');
    const wizardTitle = page.locator('#wizard-title');
    await expect(wizardTitle).toBeVisible();
    await expect(wizardTitle).not.toBeEmpty();
    // The grid cedes the viewport to the wizard while it is up.
    await expect(page.locator('section[aria-label="Drop-zoner"]')).toHaveCount(0);
  });
});
