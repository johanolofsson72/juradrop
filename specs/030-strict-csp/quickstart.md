# Quickstart: verifying the strict CSP (spec 030)

## Automated (CI-safe)

```bash
cd src-tauri && cargo test csp          # the policy-pinning + invariant tests
npm test                                # full vitest suite stays green (SC-002)
cd src-tauri && cargo test              # full Rust suite stays green
cargo clippy --all-targets -- -D warnings && cargo fmt --check
```

## Manual (the WKWebView egress check — not drivable in CI; see spec 019)

1. `npm run tauri dev` — confirm the app window opens and the React UI renders
   fully (no missing styles/icons → SC-004). If the UI is unstyled, `devCsp`'s
   `style-src` is too tight.
2. Drop a `.docx` on a zone → confirm the sidecar output appears and opens
   (Ollama round-trip works under CSP → SC-003).
3. Click the About-section "Öppna på GitHub" link → opens in the system
   browser (FR-007).
4. Open WKWebView devtools console and run the egress probe (SC-001):
   ```js
   fetch('https://example.com').then(
     () => console.error('LEAK: egress NOT blocked'),
     (e) => console.log('OK: blocked →', e.message)
   );
   ```
   Expect a CSP violation / network error, NOT a successful response.
5. Confirm `invoke()`-based commands still work (any zone running proves IPC is
   intact under the `connect-src ipc:` allowance).

## If something breaks

- UI unstyled → add the missing local source to `style-src` (dev) / inspect what the bundle needs; never add a remote host.
- A zone hangs / IPC fails → `connect-src` is missing `ipc:`/`http://ipc.localhost`.
- HMR not reloading in dev → `devCsp` `connect-src` is missing `ws://localhost:1420`.
- Production build must NEVER carry the dev relaxations — the C-7 pinning test guards this.
