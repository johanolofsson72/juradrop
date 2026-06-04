// Spec 041 — InstructionField e2e: functional coverage (T011), the
// pinned-at-drop guarantee (T016), and the destructive suite (T023).
//
// ===== FUNCTIONAL COVERAGE INVENTORY (e2e scope) =====
// 1. Field renders with Swedish placeholder, idle (no counter/clear)
// 2. Typing shows the live n/500 counter
// 3. Instruction rides the dispatch payload on Välj fil pick
// 4. Clear (×) empties the field → next pick sends null
// 5. Field text survives a failed run (FR-015)
// 6. Pinned at drop: mid-run edits never mutate the sent payload (FR-006)
// =====================================================
//
// ===== DESTRUCTIVE SCENARIOS (6 categories, 8+ scenarios) =====
// D1 (invalid input)  — 600-char paste capped at 500, counter honest
// D2 (invalid input)  — script-tag/emoji/RTL text passes as inert payload
// D3 (wrong order)    — clear DURING processing leaves in-flight run alone
// D4 (wrong order)    — rapid type→clear→type: last value wins
// D5 (skip steps)     — UI cannot produce a >500 payload (Rust cap is the
//                       second wall — commands.rs normalize tests)
// D6 (boundary)       — exactly 500 accepted; whitespace-only → null
// D7 (timing)         — field stays editable while a zone processes
// D8 (accessibility)  — keyboard-only: type, Tab to ×, Enter clears
// ===============================================================

import { test, expect } from './support/fixtures';
import { withCanned } from './support/canned-state';

const FIELD = '[data-instruction-field] input';
const COUNTER = '[data-instruction-counter]';
const CLEAR = '[data-instruction-clear]';

const processingSnap = {
  state: 'processing',
  disabled: false,
  failure: null,
  job_id: 'job-e2e-1',
  progress_hint: 'Bearbetar del 1 av 3…',
};

test.describe('instruction field — functional', () => {
  test.use({ canned: withCanned({ pickerResult: '/Users/x/avtal.docx' }) });

  test('renders idle: placeholder, no counter, no clear (F1)', async ({ page }) => {
    await page.goto('/');
    const field = page.locator(FIELD);
    await expect(field).toBeVisible();
    await expect(field).toHaveAttribute('placeholder', /nästa dokument/);
    await expect(page.locator(COUNTER)).toHaveCount(0);
    await expect(page.locator(CLEAR)).toHaveCount(0);
  });

  test('typing shows a live, accurate counter (F2)', async ({ page }) => {
    await page.goto('/');
    await page.fill(FIELD, 'fokusera på skadeståndsfrågan');
    await expect(page.locator(COUNTER)).toHaveText('29/500');
  });

  test('instruction rides the dispatch payload on pick (F3)', async ({ page, juradrop }) => {
    await page.goto('/');
    await page.fill(FIELD, 'behåll citaten på svenska');
    await page.locator('[data-zone-pick="sammanfatta"]').click();

    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    const dispatch = (await juradrop.invocations()).find(
      (i) => i.command === 'dispatch_to_zone',
    );
    expect(dispatch?.payload).toEqual({
      zoneId: 'sammanfatta',
      paths: ['/Users/x/avtal.docx'],
      instruction: 'behåll citaten på svenska',
    });
  });

  test('clear empties the field → next pick sends null (F4)', async ({ page, juradrop }) => {
    await page.goto('/');
    await page.fill(FIELD, 'tillfällig instruktion');
    await page.locator(CLEAR).click();
    await expect(page.locator(FIELD)).toHaveValue('');

    await page.locator('[data-zone-pick="punktlista"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    const dispatch = (await juradrop.invocations()).find(
      (i) => i.command === 'dispatch_to_zone',
    );
    expect(dispatch?.payload).toMatchObject({ instruction: null });
  });

  test('field text survives a failed run (F5 / FR-015)', async ({ page, juradrop }) => {
    await page.goto('/');
    await page.fill(FIELD, 'fokusera på domskälen');
    await page.locator('[data-zone-pick="sammanfatta"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    // The backend reports the run failed.
    await juradrop.emit('juradrop://zone/sammanfatta', {
      state: 'error',
      disabled: false,
      failure: 'model_error',
      job_id: 'job-e2e-1',
      progress_hint: null,
    });
    await expect(page.locator(FIELD)).toHaveValue('fokusera på domskälen');
  });

  test('pinned at drop: mid-run edits never mutate the sent payload (F6 / FR-006)', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    await page.fill(FIELD, 'första instruktionen');
    await page.locator('[data-zone-pick="sammanfatta"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).filter((i) => i.command === 'dispatch_to_zone').length,
      )
      .toBe(1);

    // Run is in flight; the user edits the field.
    await juradrop.emit('juradrop://zone/sammanfatta', processingSnap);
    await page.fill(FIELD, 'andra instruktionen');

    // The recorded payload is untouched by the edit.
    const first = (await juradrop.invocations()).find((i) => i.command === 'dispatch_to_zone');
    expect(first?.payload).toMatchObject({ instruction: 'första instruktionen' });

    // Run completes; the NEXT pick carries the new text.
    await juradrop.emit('juradrop://zone/sammanfatta', {
      state: 'idle',
      disabled: false,
      failure: null,
      job_id: null,
      progress_hint: null,
    });
    await page.locator('[data-zone-pick="forenkla"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).filter((i) => i.command === 'dispatch_to_zone').length,
      )
      .toBe(2);
    const second = (await juradrop.invocations())
      .filter((i) => i.command === 'dispatch_to_zone')
      .at(-1);
    expect(second?.payload).toMatchObject({
      zoneId: 'forenkla',
      instruction: 'andra instruktionen',
    });
  });
});

test.describe('instruction field — destructive', () => {
  test.use({ canned: withCanned({ pickerResult: '/Users/x/avtal.docx' }) });

  test('D1+D5: 600-char paste caps at 500 — UI cannot exceed the payload cap', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    await page.fill(FIELD, 'x'.repeat(600));
    await expect(page.locator(FIELD)).toHaveValue('x'.repeat(500));
    await expect(page.locator(COUNTER)).toHaveText('500/500');

    await page.locator('[data-zone-pick="sammanfatta"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    const dispatch = (await juradrop.invocations()).find(
      (i) => i.command === 'dispatch_to_zone',
    );
    const sent = (dispatch?.payload as { instruction: string }).instruction;
    expect(sent).toHaveLength(500);
  });

  test('D2: hostile text is inert payload, never DOM (no script execution)', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    const hostile = '<script>window.__pwned=1</script> 🧨 עברית ‏RTL';
    await page.fill(FIELD, hostile);
    await expect(page.locator(FIELD)).toHaveValue(hostile);
    expect(await page.evaluate(() => (window as { __pwned?: number }).__pwned)).toBeUndefined();

    await page.locator('[data-zone-pick="sammanfatta"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    const dispatch = (await juradrop.invocations()).find(
      (i) => i.command === 'dispatch_to_zone',
    );
    expect(dispatch?.payload).toMatchObject({ instruction: hostile });
  });

  test('D3: clearing DURING processing leaves the in-flight run alone', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    await page.fill(FIELD, 'pågående instruktion');
    await page.locator('[data-zone-pick="sammanfatta"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    await juradrop.emit('juradrop://zone/sammanfatta', processingSnap);

    await page.locator(CLEAR).click();
    await expect(page.locator(FIELD)).toHaveValue('');
    // Exactly one dispatch, payload unchanged.
    const dispatches = (await juradrop.invocations()).filter(
      (i) => i.command === 'dispatch_to_zone',
    );
    expect(dispatches).toHaveLength(1);
    expect(dispatches[0]?.payload).toMatchObject({ instruction: 'pågående instruktion' });
  });

  test('D4: rapid type→clear→type — last value wins on pick', async ({ page, juradrop }) => {
    await page.goto('/');
    await page.fill(FIELD, 'version ett');
    await page.locator(CLEAR).click();
    await page.fill(FIELD, 'version två');
    await page.locator('[data-zone-pick="kontakter"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    const dispatch = (await juradrop.invocations()).find(
      (i) => i.command === 'dispatch_to_zone',
    );
    expect(dispatch?.payload).toMatchObject({ instruction: 'version två' });
  });

  test('D6: exactly 500 accepted; whitespace-only dispatches null', async ({
    page,
    juradrop,
  }) => {
    await page.goto('/');
    const exact = 'b'.repeat(500);
    await page.fill(FIELD, exact);
    await expect(page.locator(FIELD)).toHaveValue(exact);
    await expect(page.locator(COUNTER)).toHaveText('500/500');

    await page.fill(FIELD, '   ');
    await page.locator('[data-zone-pick="sammanfatta"]').click();
    await expect
      .poll(async () =>
        (await juradrop.invocations()).some((i) => i.command === 'dispatch_to_zone'),
      )
      .toBe(true);
    const dispatch = (await juradrop.invocations()).find(
      (i) => i.command === 'dispatch_to_zone',
    );
    expect(dispatch?.payload).toMatchObject({ instruction: null });
  });

  test('D7: field stays editable while a zone is processing', async ({ page, juradrop }) => {
    await page.goto('/');
    await juradrop.emit('juradrop://zone/sammanfatta', processingSnap);
    const field = page.locator(FIELD);
    await expect(field).toBeEnabled();
    await page.fill(FIELD, 'skrivs under pågående körning');
    await expect(field).toHaveValue('skrivs under pågående körning');
  });

  test('D8: keyboard-only — type, Tab to ×, Enter clears; accessible name present', async ({
    page,
  }) => {
    await page.goto('/');
    const field = page.locator(FIELD);
    await expect(field).toHaveAccessibleName('Egna instruktioner för nästa dokument');

    await field.focus();
    await page.keyboard.type('tangentbordstest');
    await expect(page.locator(COUNTER)).toHaveText('16/500');

    // Tab moves focus to the clear button (next focusable in the row).
    await page.keyboard.press('Tab');
    await expect(page.locator(CLEAR)).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(field).toHaveValue('');
  });
});
