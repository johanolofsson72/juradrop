# Contract — Panel events and IPC surface

The React panel talks to Rust via three channels: Tauri `#[command]` invocations (see `settings-commands.md`), Tauri `emit`/`listen` events for asynchronous notifications, and ambient OS events (media-query change for appearance) handled entirely client-side.

## Tauri events

### `settings://tier_pulled`

**Direction**: Rust → React.

**Emitter**: The spec 008 wizard's success callback, gated on the wizard invocation's `source == panel_triggered`.

**Payload**:

```json
{
  "tier": "Snabb"
}
```

(`tier` is one of `"Snabb"`, `"Smart"`, `"Stor"`.)

**Listener**: `src/store/useSettingsStore.ts`'s subscription, registered in the store's `init()` call (mounted at App.tsx level). On receipt:
1. Re-fetch `get_tier_pull_state()` (the local cache may be stale).
2. Auto-select the target tier by calling `set_model_tier(tier)`.
3. The panel UI re-renders: the previously-grey-`Ladda ned` row becomes a selected radio row.

**Idempotency**: If the user has manually selected a different tier between clicking `Ladda ned` and the pull completing, the auto-select still fires. The user can change again — no race window where the panel is "stuck" on the pulled tier.

### `settings://tier_pull_failed`

**Direction**: Rust → React.

**Emitter**: Spec 008 wizard's failure callback, gated on `source == panel_triggered`.

**Payload**:

```json
{
  "tier": "Stor",
  "reason": "<existing wizard failure reason enum>"
}
```

**Listener**: Same store subscription. On receipt:
1. Re-fetch `get_tier_pull_state()` (probably unchanged, but defensive).
2. Do NOT mutate `model_tier` — previously-selected tier stays active.
3. The panel UI re-renders: the `Ladda ned` button reappears (no longer in pulling state); the wizard's error UI (existing spec 008 Swedish error copy) is what the user sees prominently.

### `settings://tier_pull_cancelled`

Same shape and semantics as `settings://tier_pull_failed`, but emitted on user-initiated cancel inside the wizard. No state mutation; UI returns to pre-click state.

## Commands invoked from React (recap; see `settings-commands.md` for full signatures)

| Command                  | When                              | Direction      |
|--------------------------|-----------------------------------|----------------|
| `get_settings`           | Panel mount; after any pull event | React → Rust   |
| `set_model_tier`         | User clicks a `radio_selectable` tier row | React → Rust |
| `get_tier_pull_state`    | Panel mount; after `tier_pulled`  | React → Rust   |
| `trigger_tier_download`  | User clicks `Ladda ned` button    | React → Rust   |

## Client-side OS events

### `(prefers-color-scheme: dark)` MediaQueryList change

**Direction**: OS → WKWebView → React (via `useSyncExternalStore`).

**Listener**: `src/hooks/useSystemAppearance.ts`. Returns `'light' | 'dark'`. Subscribes via `mediaQueryList.addEventListener('change', notify)`.

**Latency budget**: ≤ 500 ms (SC-004). The MediaQueryList event fires synchronously; the React re-render schedules within the next frame. Total wall-clock: well under 100 ms in practice; the 500 ms budget is for fake-timer assertions in vitest.

**No Rust round-trip**: this is a pure browser API. No Tauri command needed. Avoids one IPC per appearance change.

### `keydown` global listener (Cmd+,)

**Direction**: OS → WKWebView → React (via window-level `addEventListener`).

**Listener**: `src/hooks/useCmdComma.ts`. Mounted once at App.tsx level. Listens for `event.metaKey && event.key === ','`. On match:
1. `event.preventDefault()`.
2. If `gearIconEnabled` is true (predicate from `useSettingsPanel`): dispatch `togglePanel()`. Otherwise: no-op.

**Cleanup**: standard React `useEffect` return — `removeEventListener` on unmount.

## Disabled-gate predicate

The `gearIconEnabled` predicate is derived in `useSettingsPanel`:

```ts
const gearIconEnabled =
    !firstRunWizardVisible &&
    !updateRestartConfirmVisible;
```

Both `firstRunWizardVisible` (from spec 008's `useWizardStore`) and `updateRestartConfirmVisible` (from spec 007's `useUpdateStore`) are read directly via their existing Zustand selectors. No new state, no duplicated source of truth.

When either becomes true:
- `GearIcon.tsx` renders with `aria-disabled="true"`, reduced opacity, no `onClick` handler.
- `useCmdComma` skips the toggle dispatch.
- A test in `SettingsPanel.test.tsx` asserts that simulating a gear click during a mocked wizard-visible state does NOT change `PanelVisibility`.

## Event-flow sequence diagrams

### Happy path: user switches from Smart to (pulled) Snabb

```text
User           GearIcon        useSettingsPanel    SettingsPanel    Rust
 │ click gear   │                  │                   │             │
 │─────────────▶│ openPanel()      │                   │             │
 │              │─────────────────▶│ visibility=opening│             │
 │              │                  │──────────────────▶│ render      │
 │ animation completes             │ visibility=open   │             │
 │                                 │──────────────────▶│ re-render   │
 │              click "Snabb"      │                   │             │
 │ ────────────────────────────────────────────────────▶ set_model_tier(Snabb)
 │                                                     │             │── disk write
 │                                                     │             │── return Ok
 │              click outside      │                   │             │
 │ ────────────────────────────────▶ closePanel()      │             │
 │                                 │ visibility=closing│             │
 │ animation completes             │ visibility=closed │             │
 │              drop file on zone                     │             │
 │ ────────────────────────────────────────────────────────────────────▶ dispatch_to_zone
 │                                                     │             │── reads snapshot.model_tier = Snabb
 │                                                     │             │── calls Ollama with model_id="llama3.2:1b"
```

### Ladda-ned path: user pulls Stor

```text
User           TierRow          Rust                              SpecWizard
 │ click Ladda  │                │                                 │
 │─────────────▶│ trigger_tier_download(Stor)                      │
 │              │───────────────▶│ start_model_pull("gemma3:12b",  │
 │              │                │   source: PanelTriggered{Stor}) │
 │              │                │────────────────────────────────▶│ shows progress UI
 │              │                │                                 │... download ...
 │              │                │                                 │ ✓ complete
 │              │                │◀────────────────────────────────│ emit settings://tier_pulled {tier: "Stor"}
 │              │ listen          │                                 │
 │              │◀───────────────│ event                            │
 │              │ set_model_tier(Stor)                              │
 │              │───────────────▶│ disk write                       │
 │              │ re-render with Stor selected                     │
```

### Disabled-gate path: user clicks gear during first-run wizard

```text
User           GearIcon                useSettingsPanel
 │ click gear   │                          │
 │─────────────▶│ gearIconEnabled === false│
 │              │ (no openPanel call)      │
 │              │ visibility stays closed  │
```
