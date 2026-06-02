# Research: Strict Content-Security-Policy (spec 030)

## R-1: How Tauri 2 applies CSP

**Decision**: Set `app.security.csp` (production) and `app.security.devCsp` (development) in `src-tauri/tauri.conf.json`.

**Rationale** (from the Tauri v2 `SecurityConfig` source, via context7):
- `csp` is injected into all HTML in the **built** application.
- `devCsp` is injected in **development**. **If `devCsp` is omitted, `csp` is used for both** — there is NO automatic dev-server relaxation.
- At compile time Tauri parses frontend assets and **injects `nonce` + `sha256-` hash sources** into `script-src`/`style-src` so the app's own scripts/styles load under a strict policy without us hand-listing them. This is why `script-src 'self'` works for the bundled React app even though Vite emits hashed module scripts — Tauri adds the hashes. `dangerousDisableAssetCspModification` (left at default = enabled) is what powers this; we keep it ON.

**Consequence**: A strict `default-src 'self'` is safe for the production bundle because Tauri augments script/style sources at build time. Dev needs the extra dev-server origin + HMR websocket, hence `devCsp`.

**Alternatives considered**:
- Single `csp` only → rejected: breaks Vite HMR in `tauri dev` (no `ws://localhost:1420` in connect-src).
- `dangerousDisableAssetCspModification: true` + hand-listing hashes → rejected: brittle, defeats the framework's own hashing, and the prefix says "dangerous".

## R-2: The IPC / asset origin tokens

**Decision**: `connect-src` includes `'self' ipc: http://ipc.localhost`.

**Rationale**: Tauri 2 `invoke()` rides the IPC custom protocol; the documented tokens to keep IPC working under a custom CSP are `ipc:` and `http://ipc.localhost`. The app's own assets are served from the `tauri://localhost` origin, which `'self'` covers.

## R-3: Does the frontend fetch Ollama directly?

**Decision**: Include the localhost Ollama origins in `connect-src` anyway, but note they are not strictly required today.

**Rationale**: grep of `src/**` shows the renderer makes **no** `fetch()`/XHR to `127.0.0.1:11434` — all Ollama traffic goes through the Rust command layer via `invoke()` (IPC). So functionally `connect-src` does not need the Ollama origins. We include `http://127.0.0.1:11434` + `http://localhost:11434` to (a) match the spec's declared allowed-egress set and `.allium` invariant, and (b) future-proof a direct-fetch path. They are localhost-only, so `LocalhostOnlyEgress` still holds. This is the maximally-honest "allowed = localhost only" set.

## R-4: style-src and data: URIs

**Decision**: `style-src 'self' 'unsafe-inline'`; `img-src 'self' data:`; `font-src 'self' data:`.

**Rationale**: Tailwind + shadcn/ui inject runtime inline styles; without `'unsafe-inline'` on `style-src` the UI loses styling. `script-src` gets NO `'unsafe-inline'`/`'unsafe-eval'` — that is the load-bearing XSS-egress guard (FR-012). `data:` is needed for inline SVG icons (lucide-react) and any inlined fonts; allowed for img/font only, never script.

## R-5: Are updater + shell.open affected by the webview CSP?

**Decision**: No — verify, don't assume.

**Rationale**: The auto-updater runs in the Rust core (reqwest), and `shell.open` is an OS-level open handled by the shell plugin in the core — neither is a webview `fetch()`, so neither is governed by the renderer CSP. Verification = the existing updater/shell tests + full suite stay green, plus a manual `tauri dev` smoke.

## R-6: The chosen policy strings

Production (`csp`):
```
default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' ipc: http://ipc.localhost http://127.0.0.1:11434 http://localhost:11434; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'
```

Development (`devCsp`) — production policy with the Vite dev origin + HMR websocket added to `default-src`/`connect-src` (and `script-src`/`style-src` for the dev server's module + inline injection):
```
default-src 'self' http://localhost:1420; script-src 'self' 'unsafe-inline' http://localhost:1420; style-src 'self' 'unsafe-inline' http://localhost:1420; img-src 'self' data: http://localhost:1420; font-src 'self' data: http://localhost:1420; connect-src 'self' ipc: http://ipc.localhost http://127.0.0.1:11434 http://localhost:11434 http://localhost:1420 ws://localhost:1420; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'
```

**Note**: `devCsp` relaxes `script-src` with `'unsafe-inline'` + the dev origin because Vite serves un-hashed module scripts and an inline HMR client in dev. This relaxation exists ONLY in dev builds and never ships (verified by FR-015's test asserting the production `csp` has no `'unsafe-inline'` in `script-src`). `frame-ancestors`/`object-src`/`base-uri`/`form-action` stay locked even in dev.

## R-7: Verification approach (cannot drive WKWebView in CI here)

**Decision**: Pin the policy with a config-parsing unit test (Rust) + a structural assertion test, and rely on a manual `tauri dev` smoke for the live WKWebView egress check. Document the manual step in quickstart.md.

**Rationale**: The real CSP enforcement happens in WKWebView, which is not drivable in this environment (spec 019 is blocked for exactly this reason). So automated coverage = parse `tauri.conf.json`, assert the production `csp` satisfies every FR (localhost-only connect-src, no unsafe script, no report endpoint, defense-in-depth directives present, `csp != null`). The egress-probe (SC-001) is executed manually in `tauri dev` per quickstart, since a jsdom/Playwright run does not exercise the WKWebView policy.
