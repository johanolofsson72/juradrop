# Feature Specification: Strict Content-Security-Policy

**Feature Branch**: `main` (direct-push per spec-register.md; no feature branch)

**Created**: 2026-06-02

**Status**: Draft

**Input**: User description: "Replace `csp: null` in tauri.conf.json with a strict Content-Security-Policy that forbids all WKWebView network egress except the localhost Ollama endpoint plus the Tauri IPC channel. Turn Principle I (Privacy by Architecture) from a documented promise into a structurally-enforced wall."

## Clarifications

### Session 2026-06-02

- Q: Does the policy need `'unsafe-inline'` for styles, given the local UI toolkit (Tailwind/shadcn) injects inline styles? → A: Yes — `style-src` allows `'self' 'unsafe-inline'`; `script-src` stays `'self'` only (NO `'unsafe-inline'`/`'unsafe-eval'` for scripts — that is the load-bearing XSS-egress guard).
- Q: Should CSP violations be reported to an endpoint (`report-uri`/`report-to`)? → A: No reporting endpoint. Any report destination is outbound traffic and would violate Principle I; violations surface only in the dev console.
- Q: Beyond `connect-src`/`script-src`, which defense-in-depth directives should the policy set? → A: `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, `form-action 'self'` — lock plugin embeds, base-tag hijack, clickjacking, and form exfiltration too.
- Q: How is dev-mode (Vite HMR over websocket) handled without weakening the production policy? → A: Use Tauri 2's separate `devCsp` field. CORRECTION (found during planning via the Tauri docs): Tauri does NOT auto-relax the policy for the dev server — if `devCsp` is unset, the strict `csp` is used in dev too and would break HMR. So the config declares two values: `csp` = the strict production policy (what ships), and `devCsp` = the same policy plus the Vite dev origin (`http://localhost:1420`) and HMR websocket (`ws://localhost:1420`). `devCsp` is compiled into dev builds only and never reaches a release artifact.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Confidential content cannot leak even under compromise (Priority: P1)

A Swedish law student drops a privileged case document onto a zone. Even if a third-party frontend dependency were compromised, or a crafted document tricked the renderer into attempting an outbound request, the browser engine itself refuses any network connection except to the local Ollama instance. The document content has no path off the Mac.

**Why this priority**: This is the entire reason the feature exists. Principle I is the app's non-negotiable promise; today it is enforced only by code review and good intentions because the webview runs with no Content-Security-Policy at all (`csp: null`). This story makes the privacy boundary a structural property of the runtime, not a convention.

**Independent Test**: With the strict policy active, attempt an outbound `fetch()` / image load / script load to a non-localhost origin from the renderer (via a test harness or injected snippet) and confirm the browser engine blocks it and emits a CSP violation, while a request to the local Ollama endpoint and to the app's own bundled assets succeeds.

**Acceptance Scenarios**:

1. **Given** the app is running under the strict policy, **When** the renderer attempts to connect to any origin other than the app's own bundled assets, the Tauri IPC channel, or the local Ollama endpoint, **Then** the connection is blocked by the browser engine.
2. **Given** the app is running under the strict policy, **When** a zone processes a document, **Then** the local Ollama round-trip completes normally and the sidecar output file is produced exactly as before.
3. **Given** the app is running under the strict policy, **When** the user opens the app, **Then** the React UI renders fully with no blocked stylesheets, scripts, fonts, or images.

---

### User Story 2 - Nothing the user relies on breaks (Priority: P1)

Every existing capability continues to work under the tightened policy: the app loads, all nine zones process documents, the About-section "Open on GitHub" link opens in the system browser, and the auto-updater can still fetch its signed manifest.

**Why this priority**: A privacy clamp that breaks the app is a regression, not a hardening. The policy must be exactly as tight as Principle I requires and no tighter — every legitimate channel must remain open.

**Independent Test**: Run the full existing vitest + cargo + Playwright suites under the new policy with zero regressions, and manually drive one document through one zone in `tauri dev`.

**Acceptance Scenarios**:

1. **Given** the strict policy, **When** the user clicks the GitHub link in About, **Then** the link opens in the system browser (this is an OS-level shell open, not a webview navigation, so it is unaffected — verify it remains so).
2. **Given** the strict policy, **When** an update is available, **Then** the updater fetches and verifies its manifest successfully (the updater runs in the Rust core, not the webview, so it is unaffected — verify it remains so).
3. **Given** the strict policy, **When** any of the existing zones runs, **Then** its output is byte-equivalent to the pre-policy output for the same input.

---

### Edge Cases

- What happens if a future feature legitimately needs a new origin (e.g. a new localhost port)? → The policy is a single declared value; adding an origin is a deliberate, reviewable one-line change, which is the point. A test pins the current policy so any change is intentional.
- What happens to inline styles injected by the UI component library at runtime? → The policy must permit whatever the local UI toolchain emits for styles while still forbidding remote style origins; this is resolved during implementation by inspecting what the built bundle actually requires.
- What happens to `data:` URIs (e.g. inline SVG icons / fonts)? → Permitted for images/fonts as needed by the local bundle; never for scripts.
- What happens in `tauri dev` where the frontend is served from the Vite dev server over a local HTTP origin? → The dev origin must remain loadable in development without weakening the production policy.
- What happens if the policy blocks something silently? → A CSP violation is observable; the verification step must actively probe for blocked-but-needed resources rather than assume success.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The application MUST define an explicit Content-Security-Policy for the main webview instead of leaving it unset.
- **FR-002**: The policy MUST restrict the default fetch directive so that document, script, and connection origins are limited to the application's own bundled assets, the Tauri IPC channel, and the local Ollama endpoint (`127.0.0.1:11434` and its `localhost` alias) — and nothing else.
- **FR-003**: The policy MUST forbid outbound network connections (`connect-src`) to any origin other than the local Ollama endpoint and the app's own assets/IPC.
- **FR-004**: The policy MUST forbid loading scripts from any remote origin (`script-src` limited to the app's own assets).
- **FR-005**: The policy MUST permit exactly the local resources the built frontend genuinely requires to render (styles, fonts, images, including any `data:` URIs the bundle uses) and no remote equivalents.
- **FR-006**: The local Ollama document-processing round-trip MUST continue to function unchanged under the policy.
- **FR-007**: The "Open on GitHub" link MUST continue to open in the system browser under the policy.
- **FR-008**: The auto-updater MUST continue to fetch and verify its signed manifest under the policy.
- **FR-009**: Development mode MUST remain functional under a policy that is no weaker, in production, than the strict policy this spec defines.
- **FR-010**: The policy value MUST be pinned by an automated test so that any future change to it is deliberate and reviewed.
- **FR-011**: The application MUST NOT introduce any new outbound network destination as part of this change (Principle I).
- **FR-012**: `script-src` MUST NOT permit `'unsafe-inline'` or `'unsafe-eval'`; `style-src` MAY permit `'unsafe-inline'` (required by the local UI toolkit) but MUST NOT permit any remote style origin.
- **FR-013**: The policy MUST NOT declare any violation-reporting endpoint (`report-uri`/`report-to`), as a report destination is outbound traffic forbidden by Principle I.
- **FR-014**: The policy MUST set the defense-in-depth directives `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, and `form-action 'self'`.
- **FR-015**: The production policy (`csp`) MUST be strict as defined above. Development-mode relaxations (the Vite dev origin and HMR websocket) MUST live in a separate dev-only policy (`devCsp`) that is compiled into dev builds only and never reaches a release artifact. The two MUST differ only by the added dev origin + websocket; `devCsp` MUST NOT relax `script-src`/`object-src`/`base-uri`/`frame-ancestors`/`form-action` beyond what dev tooling strictly requires.

### Key Entities

- **Content-Security-Policy**: The single declared directive set governing what origins the webview may load resources from and connect to. Attributes: the allowed origins per directive (default/script/connect/style/img/font). Relationship: it is the structural enforcement of Constitution Principle I and the runtime counterpart to the localhost-only invariant already asserted in the Ollama client and the spec-027 `.allium`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of outbound connection attempts from the renderer to non-allowed origins are blocked by the browser engine (verified by an explicit egress-probe test).
- **SC-002**: 0 existing tests regress under the new policy (full vitest + cargo + Playwright suites stay green).
- **SC-003**: A document dropped on a zone produces output byte-equivalent to the pre-policy output for the same input (no functional change observed by the user).
- **SC-004**: The app's UI renders with 0 CSP-blocked resources that it legitimately needs (no missing styles, fonts, scripts, or icons).
- **SC-005**: The number of permitted non-localhost network origins in the policy is exactly 0.

## Assumptions

- The frontend is fully local: it bundles all its own assets and makes no remote resource requests. (Evidence: the only external URL string in `src/` is a GitHub link in settings copy, which is opened via the OS shell, not fetched in the webview.)
- The auto-updater and Ollama HTTP calls execute in the Rust core / Tauri command layer, not as webview `fetch()` calls, so they are governed by the OS network stack and capabilities rather than the webview CSP — this spec verifies that assumption rather than relying on it blindly.
- The local UI toolkit may require permissive inline styles; the exact `style-src` allowance is determined by inspecting the built bundle during implementation, kept as tight as the bundle permits.
- This is a hardening change with no new entities or state transitions of its own; it tightens an existing runtime configuration. The "state machine" is trivial (a single static policy value), so TLA+ is expected to hit its triviality gate — but the security-invariant nature warrants the full track for the Allium localhost-only invariant and the egress-probe test.
- Direct-push to `main`, no feature branch (per `spec-register.md`).
