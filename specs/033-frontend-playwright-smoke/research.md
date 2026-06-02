# Research — Frontend Playwright smoke tests

All "NEEDS CLARIFICATION" resolved here. Sources are read from the actual codebase / `node_modules`, not assumed.

## R-001 — The `@tauri-apps/api` v2.11 IPC contract the bridge must reproduce

**Decision:** Implement `window.__TAURI_INTERNALS__` with exactly three methods the SDK calls, plus a test control surface.

From `node_modules/@tauri-apps/api/core.js`:
- `transformCallback(cb, once)` → `window.__TAURI_INTERNALS__.transformCallback(cb, once)` — returns an id; the SDK stores nothing itself.
- `invoke(cmd, payload, options)` → `window.__TAURI_INTERNALS__.invoke(cmd, payload, options)` — returns a Promise.
- A `Channel` path uses `window.__TAURI_INTERNALS__.unregisterCallback(id)` on drop.

From `node_modules/@tauri-apps/api/event.js`:
- `listen(event, handler, options)` calls `invoke('plugin:event|listen', { event, target, handler: transformCallback(handler) })` and resolves to an `eventId` (number); the returned unlisten fn calls `invoke('plugin:event|unlisten', { event, eventId })`.
- `target` defaults to `{ kind: 'Any' }` — the bridge can ignore `target` for smoke purposes.
- The transformed `handler` is invoked by the backend with an event object of shape `{ event: string, id: number, payload: T }`; `listen`'s wrapper reads `event.payload`.

**Rationale:** Matching these three method names + the `{event,id,payload}` delivery shape is necessary and sufficient for `invoke`/`listen`/`unlisten` to work against the unmodified frontend.

**Alternatives considered:** `@tauri-apps/api/mocks` (`mockIPC`/`mockWindows`). Rejected as primary: it covers `invoke` but its event story is awkward for *pushing* backend events into live listeners on a real page, and it couples us to its internal callback plumbing. A hand-rolled bridge is small, explicit, and gives us the `emit` + invocation-log control surface the spec needs. (We still pin the contract with FR-017 so a future SDK bump can't silently break our hand-roll.)

## R-002 — Injection timing (FR-003: before the bundle's gate is read)

**Decision:** Inject via Playwright `page.addInitScript` (wrapped in a test fixture). `addInitScript` runs **before any page script on every navigation**, so `'__TAURI_INTERNALS__' in window` reads `true` by the time `main.tsx` evaluates and `App`'s effects run.

**Rationale:** The frontend reads the gate inside React effects (post-first-render) AND `main.tsx` mounts synchronously; `addInitScript` guarantees the global exists before any of it. A `page.evaluate` after load would be too late and is explicitly an edge case to avoid.

**Alternatives considered:** `<script>` injected into `index.html` (pollutes the production entry — rejected, violates FR-012); `route` interception to rewrite HTML (fragile). `addInitScript` is the canonical Playwright mechanism.

## R-003 — Vite `webServer` config

**Decision:** `playwright.config.ts` gets `webServer: { command: 'npm run dev', url: 'http://localhost:1420', reuseExistingServer: !process.env.CI, timeout: 120_000 }` and `use.baseURL = 'http://localhost:1420'`.

**Rationale:** `vite.config.ts` pins `server.port = 1420, strictPort: true` (Tauri convention). `reuseExistingServer: !CI` reuses a dev server locally but starts a fresh, isolated one in CI (edge case: stale/missing server fails loudly via the `url` health-check rather than hanging).

**Alternatives considered:** `vite preview` over a production build (slower, and the dev server is the documented target); a fixed `port` override (unnecessary — 1420 is already strict).

## R-004 — Event delivery / `emit` helper

**Decision:** The bridge keeps `callbacks: Map<id, fn>` and `listeners: Array<{event, callbackId, eventId, live}>`. `emit(event, payload)` finds every live listener whose `event` matches and calls `callbacks.get(callbackId)({ event, id: eventId, payload })`. A once-listener flips `live=false` after delivery. The helper is exposed as `window.__JURADROP_TEST__.emit`.

**Rationale:** This mirrors exactly what Tauri's backend does when it emits, so `subscribeZone`/`subscribeStatus`/etc. receive the payload through their normal `(event) => cb(event.payload)` wrapper. Emitting before a listener registers is a no-op (empty match set) — surfaced via an optional `expectListener` assert in tests (FR-010). Tests `await expect(locator).toBeVisible()` for the subscribing UI before emitting, proving the subscription is live.

**Alternatives considered:** Driving events by mutating a Zustand store directly via `page.evaluate` — rejected, it bypasses the very `listen` plumbing US6 exists to verify.

## R-005 — Canned backend state needed to render without crashing

**Decision:** Default canned state (per-test overridable):
- `get_status` → `{ visible: 'klar', sidecar: 'ready', model: 'ready', progress_percent: null, consent: 'fortsatt' }` → `deriveWizardPhase` returns `'hidden'` → grid renders (verified against `use-wizard-state.ts`).
- `get_settings` → `{ schema_version: 1, model_tier: 'Smart' }` (from `settings-types.ts`).
- `get_tier_pull_state` → `{ snabb_pulled: false, smart_pulled: true, stor_pulled: false }`.
- `get_tier_download_state` → `null`.
- `get_diagnostics_status` → `{ enabled: false, log_path: null }`.
- `get_app_version` → `'0.1.0'`.
- `give_consent` / `cancel_consent` / `dispatch_to_zone` / `set_model_tier` / `cancel_summary` → resolve `void`, recorded in the log.
- `plugin:dialog|open` → returns the per-test path string, or `null` for the cancel case.
- `plugin:event|listen` → registers + returns an eventId; `plugin:event|unlisten` → removes.

**Rationale:** These are the only commands the boot path + the six smoke groups invoke (traced through `App.tsx`, `DropZone.tsx`, `tauri-bridge.ts`, `settings-store.ts`, `tier-download-store.ts`, `update-store.ts`). The consent test overrides `get_status.visible='begar_samtycke', consent='not_asked'`.

## R-006 — Assertion strategy / production-code impact (Q1 clarification)

**Decision:** Assert on existing accessible DOM + existing `data-*`. **No production change.** Confirmed by reading `DropZone.tsx`:
- Nine zones: `[data-zone-id="<slug>"]` each with an `<h2>` carrying `ZONE_IDENTITIES[slug].title`.
- Zone state: `[data-zone-id="<slug>"][data-state="processing|success|error|idle|dragover"]`.
- Picker button: `[data-zone-pick="<slug>"]`, `aria-label="Välj fil för <title>"`, visible text `Välj fil`.
- Chrome: `[data-settings-gear]` (aria-label from strings), `[data-help-icon]`.
- Consent modal: Radix `Dialog` with `DialogTitle` "Ladda ner AI-modell" and buttons `Fortsätt` / `Avbryt` (role+name).

**Rationale:** SC-005 (zero runtime behavior change) holds by construction; FR-016's inert-hook escape hatch is unused.

## R-007 — Chromium vs WKWebView fidelity boundary

**Decision:** Accept Chromium for smoke; document the limit. Real WKWebView + OS drag-drop coverage is **spec 037** (XCUITest, blocked-on-hardware).

**Rationale:** Spec 019's blocker stands (no macOS WKWebView WebDriver). This harness covers the React tree, IPC wiring, and rendered Swedish surface — everything that is engine-independent. OS-level drag-drop is not simulatable here; US5's picker path is the dispatch-coverage substitute (consistent with spec 016/019).
