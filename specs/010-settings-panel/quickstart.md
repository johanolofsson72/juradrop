# Quickstart — Spec 010 Settings Panel

**Five user flows the implementation MUST satisfy.** Each flow has explicit assertions that the test suite verifies.

## Flow 1 — Open panel, switch tier, drop file, observe new tier in effect

**Pre-conditions**:
- App launched on a Mac where `gemma3:4b` (Smart) is already pulled (post-first-run state).
- No update-restart modal up, no first-run wizard up.

**Steps**:
1. Click the gear icon in the top-right chrome bar of the main window.
2. Observe the panel slide in from the right edge within the design-system motion budget.
3. Verify the **Modell** section shows three rows:
   - **Snabb** — `Ladda ned` button + `Inte nedladdad — ~1.3 GB` badge (assuming Snabb is not pulled).
   - **Smart** — selected radio + helper sentence + size badge.
   - **Stor** — `Ladda ned` button + `Inte nedladdad — ~8.1 GB` badge (assuming Stor is not pulled).
4. The Snabb row is grey/unavailable for direct selection — you cannot click a radio there.
5. Press **Esc** to close the panel.
6. Observe the panel slide out.
7. Drop a `.docx` fixture file onto the **Sammanfatta** zone.
8. The zone processes normally; the resulting sidecar file is generated using `gemma3:4b` (Smart).

**Assertions** (Playwright + vitest):
- Panel transitions: `closed → opening → open` within animation budget.
- `get_settings()` returns `{schema_version: 1, model_tier: "Smart"}`.
- `get_tier_pull_state()` returns `{snabb_pulled: false, smart_pulled: true, stor_pulled: false}` (or whatever the mock specifies).
- The dispatched zone run uses `model_id = "gemma3:4b"` (asserted via the test seam in `sidecar/commands.rs`).
- `model_tier` did not change — still `Smart` after the drop.

## Flow 2 — Pull a new tier via Ladda ned, observe auto-selection

**Pre-conditions**: Same as Flow 1, but the test mocks the spec 008 wizard to succeed with the requested model after 2 s.

**Steps**:
1. Open the panel (gear click or Cmd+,).
2. Click **Ladda ned** on the **Stor** row.
3. The spec 008 first-run-wizard UI takes over the screen showing the download progress.
4. After 2 s (mocked), the wizard reports success.
5. The wizard dismisses; the panel reappears.
6. Observe that the **Stor** row is now a selected radio (auto-selected after pull).
7. `Smart` row is no longer selected.
8. Close the panel.
9. Drop a `.docx` fixture file onto **Sammanfatta**.
10. The dispatched zone run uses `model_id = "gemma3:12b"`.

**Assertions**:
- `trigger_tier_download("Stor")` was invoked.
- `settings://tier_pulled` event fired with payload `{tier: "Stor"}`.
- `set_model_tier("Stor")` was invoked by the store's auto-select handler.
- `settings.json` on disk now contains `"model_tier": "Stor"`.
- `model_tier` mutation happened AFTER the wizard's success event, not at click time.
- The dispatch's `model_id` is `gemma3:12b`.

## Flow 3 — Appearance row reflects OS change without user action

**Pre-conditions**: App launched in macOS dark mode.

**Steps**:
1. Open the panel.
2. Observe the **Utseende** section displays read-only text: **Mörkt läge (följer systemet)**.
3. Confirm NO interactive controls in this section — no toggle, no radio, no dropdown.
4. Without closing the panel, switch macOS to light mode.
5. Observe the **Utseende** row text update to **Ljust läge (följer systemet)** within 500 ms.
6. The panel chrome (background, borders) also updates to light-mode tokens.
7. Close the panel and re-open — the row still shows the current OS value.

**Assertions** (vitest with fake timers):
- The MediaQueryList `change` event handler fires within 1 frame of the synthetic OS change event.
- The new text appears in the DOM within 500 ms of the event.
- The appearance section's DOM has zero descendants matching `input`, `button`, `select`, or `[role="switch"]`.

## Flow 4 — About section opens GitHub Releases in default browser

**Pre-conditions**: Panel can be opened normally.

**Steps**:
1. Open the panel.
2. Scroll to (or focus) the **Om JuraDrop** section.
3. Verify the row displays:
   - App name: **JuraDrop**
   - Version: the current build's version string (matching `Cargo.toml` + `tauri.conf.json` + `package.json` per spec 006's release-prep script).
   - License: **Öppen källkod, MIT-licens**
   - Button: **Visa utgåvor på GitHub**
4. Click **Visa utgåvor på GitHub**.
5. Observe the OS default browser open at `https://github.com/johanolofsson72/juradrop/releases`.
6. The JuraDrop window stays open and focused (no embedded webview, no in-app navigation).

**Assertions**:
- `shell.open` was called exactly once with the pinned URL.
- No webview was opened by JuraDrop.
- JuraDrop's main window did NOT navigate (its location stays whatever the dev server / production build uses).
- The version string in the panel matches the build's version (test reads the same source the panel reads).

## Flow 5 — Disabled gate: gear icon does nothing while first-run wizard is up

**Pre-conditions**: Fresh install with no Ollama model pulled; spec 008 first-run wizard is up after app launch.

**Steps**:
1. Without dismissing the wizard, click the gear icon location.
2. Observe nothing happens — the panel does NOT open.
3. Press Cmd+,.
4. Observe nothing happens — the panel does NOT open.
5. The first-run wizard continues unaffected.
6. Wait for the wizard to complete (or simulate completion in the test).
7. Click the gear icon again.
8. The panel now opens normally.

**Assertions**:
- During wizard-visible state: `useSettingsPanel.visibility` stays `closed` through the gear click AND through the Cmd+, press.
- After wizard dismisses: `gearIconEnabled` flips to `true`; subsequent gear click DOES open the panel.
- The gear icon's DOM has `aria-disabled="true"` during the disabled period.
- A keyboard test confirms Cmd+, is preventDefault'd during the disabled period (so no other shortcut fires either).
