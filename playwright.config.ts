import { defineConfig, devices } from '@playwright/test';

// Spec 033 — frontend Playwright smoke tests.
//
// These tests drive the REAL production React frontend in Chromium via the
// Vite dev server, with a mocked Tauri IPC bridge injected before the bundle
// loads (tests/e2e/support/). They are the testable substitute spec 019
// pre-planned: not the native WKWebView (no macOS WebDriver exists — that is
// spec 037's XCUITest job), but the assembled React tree + IPC wiring in a
// real browser engine. Replaces the old 1+1===2 placeholder.
//
// webServer boots `npm run dev` (Vite on port 1420, strictPort per
// vite.config.ts). reuseExistingServer locally; a fresh isolated server in CI.
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: 'list',
  timeout: 30_000,
  use: {
    baseURL: 'http://localhost:1420',
    headless: true,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:1420',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
