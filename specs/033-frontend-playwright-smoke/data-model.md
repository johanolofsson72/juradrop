# Data model — Frontend Playwright smoke tests

This feature has no persistent data. The "model" is the in-memory state of the injected mock bridge (one instance per page) and the canned backend shapes. Mirrors `spec.allium`.

## Mock bridge internal state

```text
MockBridge (one per page, lives until navigation/close)
├── nextCallbackId: number              # monotonic, starts at 1
├── nextEventId: number                 # monotonic, starts at 1
├── callbacks: Map<number, Function>    # transformCallback id → handler fn
├── listeners: Listener[]               # event subscriptions
├── canned: CannedState                 # current canned backend data (per-test mutable)
├── commandTable: Map<string, (payload) => unknown>   # command name → canned-response factory
└── log: InvocationRecord[]             # every invoke() recorded
```

### Listener

| Field | Type | Notes |
|---|---|---|
| `event` | `string` | e.g. `juradrop://status`, `juradrop://zone/sammanfatta` |
| `callbackId` | `number` | key into `callbacks` |
| `eventId` | `number` | returned to `listen()`, used by `plugin:event|unlisten` |
| `live` | `boolean` | `false` after unlisten or once-fire |

### InvocationRecord

| Field | Type | Notes |
|---|---|---|
| `command` | `string` | the invoked command name |
| `payload` | `unknown` | the args object (never document content — only ids/paths/tiers) |
| `result` | `'resolved' \| 'rejected'` | rejected ⇒ unmocked command (FR-009) |

## CannedState (per-test overridable)

| Key | Default | Shape source |
|---|---|---|
| `status` | `{ visible:'klar', sidecar:'ready', model:'ready', progress_percent:null, consent:'fortsatt' }` | `AppStatus` (`tauri-bridge.ts`) |
| `settings` | `{ schema_version:1, model_tier:'Smart' }` | `SettingsSnapshot` (`settings-types.ts`) |
| `tierPull` | `{ snabb_pulled:false, smart_pulled:true, stor_pulled:false }` | `TierPullState` |
| `tierDownload` | `null` | `TierDownloadEvent \| null` |
| `diagnostics` | `{ enabled:false, log_path:null }` | `DiagnosticsStatus` |
| `appVersion` | `'0.1.0'` | `string` |
| `pickerResult` | `null` | `string \| null` (path or cancel) |

## Command dispatch table (canned responses)

| Command | Returns | Recorded? |
|---|---|---|
| `get_status` | `canned.status` | yes |
| `get_settings` | `canned.settings` | yes |
| `get_tier_pull_state` | `canned.tierPull` | yes |
| `get_tier_download_state` | `canned.tierDownload` | yes |
| `get_diagnostics_status` | `canned.diagnostics` | yes |
| `get_app_version` | `canned.appVersion` | yes |
| `give_consent` / `cancel_consent` | `undefined` (void) | yes |
| `dispatch_to_zone` | `undefined` (void) | yes (assert zoneId + paths) |
| `set_model_tier` / `cancel_summary` / `cancel_model_pull` / `check_for_updates_now` … | `undefined` (void) | yes |
| `plugin:dialog\|open` | `canned.pickerResult` | yes |
| `plugin:event\|listen` | new `eventId` (registers listener) | no (plumbing) |
| `plugin:event\|unlisten` | `undefined` (removes listener) | no (plumbing) |
| *(any other)* | **rejects** `Error("unmocked command: <cmd>")` | yes (result=rejected) |

## Test control surface (`window.__JURADROP_TEST__`)

| Member | Signature | Purpose |
|---|---|---|
| `emit` | `(event: string, payload: unknown) => number` | deliver to live listeners; returns delivery count (0 ⇒ no listener, FR-010) |
| `invocations` | `() => InvocationRecord[]` | snapshot of the log for assertions |
| `setCanned` | `(partial: Partial<CannedState>) => void` | per-test override (rarely needed at runtime; most overrides happen pre-injection) |
| `listenerCount` | `(event: string) => number` | assert a subscription is live before emitting |

## State transitions (listener lifecycle)

```text
(none) --transformCallback--> registered(live)
registered(live) --plugin:event|listen--> subscribed(live)
subscribed(live) --emit (once=true)--> dead
subscribed(live) --plugin:event|unlisten / unregisterCallback--> dead
dead --emit--> (no-op, no throw)         # FR-010
```

Terminal: `dead`. Invariants (from `spec.allium`): `NeverTouchesNetwork` (network_calls=0), `GateReadsTrue` (injected_before_bundle), `DeadCallbacksNeverFire`.
