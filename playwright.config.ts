import { defineConfig } from '@playwright/test';

// Playwright stub config for spec 001-tauri-bootstrap.
// FR-002 requires `npm run test:e2e` to exist and exit 0. Real browser-driving
// tests against the built .app arrive in spec 003 once there's an interactive
// surface to exercise. Per research.md R-006.
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  reporter: 'list',
  use: {
    headless: true,
  },
});
