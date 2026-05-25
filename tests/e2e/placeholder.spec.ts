import { test, expect } from '@playwright/test';

// Spec 001-tauri-bootstrap Playwright stub.
// FR-002 + research.md R-006: this test exists so `npm run test:e2e` exits 0
// on a fresh checkout. Real browser-driving tests against the built .app
// arrive in spec 003 once interactive surface exists.
test('placeholder e2e — vitest replacement until spec 003', async () => {
  expect(1 + 1).toBe(2);
});
