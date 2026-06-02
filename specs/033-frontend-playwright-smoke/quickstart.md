# Quickstart — Frontend Playwright smoke tests

## Run the suite

```bash
npm run test:e2e            # boots Vite (port 1420), runs Chromium smoke suite headless
npm run test:e2e -- boot    # run one spec file by name
npx playwright test --ui    # interactive debug (local only)
```

First run on a fresh machine needs the Chromium binary:

```bash
npx playwright install chromium
```

CI does this automatically (the spec-031 `ci.yml` step added by FR-015).

## How it works (one paragraph)

Playwright starts the Vite dev server, opens the **production** frontend in Chromium, and — via a test fixture using `page.addInitScript` — installs `window.__TAURI_INTERNALS__` (a hand-rolled Tauri IPC double) **before** the app bundle runs. The frontend's `'__TAURI_INTERNALS__' in window` gate reads `true`, so it seeds from canned `get_status`, subscribes to event channels, and renders normally. Tests drive the real DOM and assert on rendered Swedish text / `data-*` attributes and on the bridge's invocation log. The fixture exposes `__JURADROP_TEST__.emit(...)` to push backend events into live listeners.

## Add a smoke test

```ts
import { test, expect } from './support/fixtures';   // fixture injects the bridge

test('zone goes to processing on emitted snapshot', async ({ page, juradrop }) => {
  await page.goto('/');                               // bridge already injected
  await expect(page.locator('[data-zone-id="sammanfatta"]')).toBeVisible();
  await juradrop.emit('juradrop://zone/sammanfatta', {
    state: 'processing', disabled: false, failure: null, job_id: 'job-1',
    progress_hint: 'Sammanfattar…',
  });
  await expect(page.locator('[data-zone-id="sammanfatta"][data-state="processing"]')).toBeVisible();
});
```

Override canned state per test (e.g. consent flow):

```ts
test.use({ canned: { status: { visible: 'begar_samtycke', consent: 'not_asked', sidecar: 'starting', model: 'not_present', progress_percent: null } } });
```

## Selectors cheat-sheet (existing production attributes — no prod change)

| Surface | Selector |
|---|---|
| A zone | `[data-zone-id="<slug>"]` |
| Zone visual state | `[data-zone-id="<slug>"][data-state="processing\|success\|error\|idle\|dragover"]` |
| Välj fil button | `[data-zone-pick="<slug>"]` (text `Välj fil`) |
| Settings gear | `[data-settings-gear]` |
| Help icon | `[data-help-icon]` |
| Consent modal | role `dialog`, title `Ladda ner AI-modell`, buttons `Fortsätt` / `Avbryt` |
| Zone title | `[data-zone-id="<slug>"] h2` |

## Regression-detection sanity check (SC-006)

The suite has real teeth. To confirm, temporarily break the frontend and watch a test go red:

- Delete a `ZONE_ORDER` entry → `zones.spec` fails (≠ 9 zones).
- Change a zone title in `DropZone.identity.ts` → `zones.spec` label assertion fails.
- Unwire the consent `Fortsätt` `onClick` → `consent.spec` fails (no `give_consent` recorded).

Revert after confirming.

## Boundaries

- This is **Chromium**, not WKWebView. Native-window + OS drag-drop coverage is **spec 037** (XCUITest, blocked-on-hardware). Do not add OS-drag simulation here — use the picker path (US5).
- The bridge mirrors `@tauri-apps/api` v2.11. If you bump that package, run `contract.spec` first — FR-017 pins the contract so a breaking change fails loudly.
