import { test, expect } from './support/fixtures';
import { withCanned } from './support/canned-state';

// US3 — the consent gate (privacy-load-bearing, FR-019 lineage) and its IPC
// wiring. The modal is gated on visible='begar_samtycke' && consent='not_asked'
// (which also shows the first-run wizard behind it — by design they are
// coupled). The Radix consent dialog renders in a portal on top; we scope to
// it by its title to avoid the wizard's own role="dialog".

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

function consentDialog(page: import('@playwright/test').Page) {
  return page.getByRole('dialog').filter({ hasText: 'Ladda ner AI-modell' });
}

test.describe('US3 — consent gate', () => {
  test('shows the consent modal on begar_samtycke (AS1)', async ({ page }) => {
    await page.goto('/');
    await expect(consentDialog(page)).toBeVisible();
  });

  test('Fortsätt invokes give_consent (AS2)', async ({ page, juradrop }) => {
    await page.goto('/');
    const dialog = consentDialog(page);
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Fortsätt' }).click();
    const invocations = await juradrop.invocations();
    expect(invocations.some((i) => i.command === 'give_consent' && i.result === 'resolved')).toBe(
      true,
    );
    expect(invocations.some((i) => i.command === 'cancel_consent')).toBe(false);
  });

  test('Avbryt invokes cancel_consent (AS3)', async ({ page, juradrop }) => {
    await page.goto('/');
    const dialog = consentDialog(page);
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Avbryt' }).click();
    const invocations = await juradrop.invocations();
    expect(invocations.some((i) => i.command === 'cancel_consent' && i.result === 'resolved')).toBe(
      true,
    );
    expect(invocations.some((i) => i.command === 'give_consent')).toBe(false);
  });
});
