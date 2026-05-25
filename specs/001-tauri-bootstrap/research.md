# Phase 0 — Research: Tauri Bootstrap

Resolution of open questions from `spec.allium` plus the best-practice choices needed to write a complete plan.

## R-001 — Window.appearance binding to macOS appearance changes

**Open question (from `spec.allium`)**: Should the WebView's appearance follow `prefers-color-scheme` (CSS), the Tauri `window.theme()` Rust event subscription, or both?

**Decision**: **Both layers**, with CSS as the source of truth.

1. Tailwind's `darkMode: 'media'` setting makes the dark variant resolve against `@media (prefers-color-scheme: dark)`. This is the default reactive path; WKWebView already follows the macOS appearance setting and emits the matching media query result. No JavaScript subscription required for the CSS path — Tailwind classes just work.
2. In Rust, the Tauri 2.x window builder is left at its default theme handling (no `.theme(...)` override). The OS-level dark/light follows automatically; no custom event subscription needed at this spec.
3. If a future spec needs to read or override the appearance from Rust (e.g. forcing a theme based on a user setting), that is a spec-010 concern and is explicitly deferred.

**Rationale**: The simplest path that satisfies FR-008 + SC-005 with the fewest moving parts. Adding a Rust→JS event channel just to mirror something CSS already does for free is dead code at this spec. Constitution Principle VI ("Native macOS Feel") is satisfied because WKWebView naturally adopts the system appearance.

**Alternatives considered**:
- *Tauri `window.theme()` Rust subscription only* — requires an IPC channel to push the value into React state and a re-render. More code, more places to break, no observable benefit until a spec needs programmatic override.
- *Pure CSS only* — works, but documenting the "Rust path is also clean and ready for spec 010" was worth the explicit note.

## R-002 — Tauri 2.x capability configuration for deny-by-default

**Question**: What is the minimal valid `capabilities/*.json` content that grants the WebView **nothing** while still allowing Tauri itself to start the window?

**Decision**: One file at `src-tauri/capabilities/default.json` with:

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Bootstrap capability set — deny-by-default. No plugins, no core APIs exposed to the WebView.",
  "windows": ["main"],
  "permissions": []
}
```

The empty `permissions` array is the load-bearing piece. Tauri 2.x requires *every* core API call from the WebView (filesystem, dialog, shell, sidecar, etc.) to map to a permission entry in some capability file targeting the calling window. An empty array means: nothing is allowed. The Rust core still runs normally; only the WebView→Rust IPC surface is locked down.

**Rationale**: This is the canonical deny-by-default posture in Tauri 2.x. Every later spec that needs an API adds an entry to either `default.json` or a new capability file scoped to a window — creating the audit trail FR-019 requires.

**Alternatives considered**:
- *Omit the capabilities directory entirely* — Tauri 2.x treats this as "no capabilities", which has the same runtime effect, but provides no place to add future entries and no audit anchor. Worse for ergonomics.
- *Use `core:default` permission set* — grants the standard set of Tauri runtime APIs (window controls, app lifecycle). Convenient, but contradicts FR-019's explicit "no capabilities granted" requirement.

## R-003 — shadcn/ui style + base color

**Question**: Which shadcn/ui style preset (`default` vs `new-york`) and base color match the macOS-native aesthetic described in `design-system/MASTER.md`?

**Decision**: **`new-york` style with `neutral` base color**, configured via `components.json`.

**Rationale**: The "new-york" style is the more refined of shadcn/ui's two presets — tighter spacing, more subtle shadows, less rounded corners. It pairs well with SF Pro and feels native on macOS. The `neutral` base color (warm gray scale) is the default that the Resize Images reference visual uses, and it harmonises with both light and dark macOS appearance without needing per-mode color overrides at this spec.

**Alternatives considered**:
- *`default` style with `zinc` base* — the most common shadcn combination; feels more web-app, less native. Rejected for native-feel reasons.
- *`new-york` with `slate` base* — cooler tone; reserved for spec 003 onward where the design-system review may pick this for the drop zones. Out of scope at bootstrap.

## R-004 — Vite + Tauri dev server port

**Question**: Which port should Vite bind to in dev mode?

**Decision**: **1420** (Tauri 2.x default).

**Rationale**: Matching the Tauri default means `npm create tauri-app@latest`-generated configurations work without surprises. The port is loopback-only and dev-profile-only — covered by the amended FR-016 explicitly excluding 127.0.0.1 from "outbound".

## R-005 — Rust crate type for `cargo test` visibility

**Question**: With Tauri's default `src-tauri/src/main.rs` setup, how do we make `cargo test` find tests in the library code (FR-012, FC-008)?

**Decision**: Use the standard Tauri 2.x scaffolding which already splits `main.rs` (the binary entry) and `lib.rs` (the library form). Tests live in `lib.rs` as a `#[cfg(test)] mod tests { ... }` module. `cargo test` from `src-tauri/` discovers them automatically.

**Rationale**: Matches `npm create tauri-app@latest --rust` output for Tauri 2.x. No custom Cargo configuration needed.

## R-006 — Playwright at this spec

**Question**: FR-002 requires `test:e2e` to "work on a fresh checkout". What is "work" when there's no real interactive surface to test?

**Decision**: Install `@playwright/test`, scaffold `playwright.config.ts`, and ship **one stub test** (`tests/e2e/placeholder.spec.ts`) that does `test('placeholder', async () => { expect(true).toBe(true); });`. The `test:e2e` script in `package.json` runs `playwright test` against that stub.

**Rationale**: The script exists, the framework is installed, and a fresh checkout returns exit code 0. Real browser-driving tests against the built `.app` arrive with spec 003 when there's actual UI to drive. This satisfies FR-002 without paying for Playwright machinery the spec doesn't need yet.

**Alternatives considered**:
- *Skip Playwright entirely until spec 003* — would leave the `test:e2e` script either missing or doing nothing real, contradicting FR-002.
- *Wire Playwright to drive the dev window now* — over-engineering; the dev window has no interactive surface to assert against beyond "it opens", which is more cheaply asserted by the Tauri unit test in `lib.rs`.

## R-007 — Window initial position and behavior on second launch

**Question**: Should the window remember position/size across launches at this spec?

**Decision**: **No** — use Tauri's default centered placement and let macOS choose. Position memory is a settings concern (spec 010).

**Rationale**: Out of scope. The spec only requires the window to open at the configured initial size (FR-015); it says nothing about persistence.
