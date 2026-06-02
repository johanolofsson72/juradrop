# Contract — Mock Tauri IPC bridge

The exact surface the injected bridge MUST expose. Two interfaces: the **SDK-facing** `window.__TAURI_INTERNALS__` (consumed by `@tauri-apps/api`) and the **test-facing** `window.__JURADROP_TEST__`.

## SDK-facing: `window.__TAURI_INTERNALS__`

```ts
interface TauriInternals {
  // core.js — invoke(cmd, args, options) routes here. Returns a Promise.
  invoke(cmd: string, payload?: Record<string, unknown>, options?: unknown): Promise<unknown>;

  // core.js — listen() calls this to register a handler, gets a stable id back.
  transformCallback(cb: (arg: unknown) => void, once?: boolean): number;

  // core.js Channel.drop — must exist and be a no-op-safe deregister.
  unregisterCallback(id: number): void;
}
```

### `invoke` behavior (normative)

1. `plugin:event|listen` → require `payload.handler` is a live callback id; create a `Listener { event: payload.event, callbackId: payload.handler, eventId: nextEventId++, live: true }`; resolve with `eventId`. *(Not logged — plumbing.)*
2. `plugin:event|unlisten` → set matching `Listener.live = false`; resolve `undefined`. Idempotent.
3. A command present in the dispatch table → resolve with its canned value; push `{ command, payload, result:'resolved' }` to the log.
4. Any other command → push `{ command, payload, result:'rejected' }`; **reject** with `new Error('unmocked command: ' + cmd)` (FR-009). Never resolve `undefined`.

### `transformCallback` behavior

- Assign `id = nextCallbackId++`; store `callbacks.set(id, cb)`; return `id`. Honor `once` by marking the listener that later binds this id (or the callback itself) so it fires at most once.

## Test-facing: `window.__JURADROP_TEST__`

```ts
interface JuradropTest {
  emit(event: string, payload: unknown): number;     // delivers {event,id,payload} to live listeners; returns count
  invocations(): ReadonlyArray<{ command: string; payload: unknown; result: 'resolved' | 'rejected' }>;
  setCanned(partial: Partial<CannedState>): void;     // runtime override
  listenerCount(event: string): number;               // live listeners for `event`
}
```

### `emit` behavior (normative)

- For each `Listener` where `live && event === <arg>`: call `callbacks.get(callbackId)?.({ event, id: eventId, payload })`.
- If the listener's callback was registered with `once`, set `live = false` after the call.
- Return the number of deliveries. `0` ⇒ no live listener (test may assert this for the no-listener edge case). Never throws on zero listeners or dead callbacks (FR-010).

## Injection contract (FR-003)

- Registered through Playwright `page.addInitScript` so it runs **before any page script on every navigation**. After injection, `'__TAURI_INTERNALS__' in window === true`.
- The init script is a **self-contained, serializable function** (no imports inside the browser context); canned overrides are passed as a serializable argument to `addInitScript`.

## Privacy contract (Principle I / FR-013)

- The bridge performs **zero** `fetch`/`XHR`/`WebSocket` calls. All responses are canned literals. No payload is ever transmitted off-page. The invocation log stores ids/paths/tiers only — never document content (consistent with the app's own enum-only diagnostics discipline).

## Acceptance mapping

| Contract clause | FR | Smoke test |
|---|---|---|
| `invoke` dispatch + log | FR-004, FR-006, FR-007 | all |
| `plugin:event\|listen/unlisten` | FR-005 | events.spec, panels.spec |
| unmocked → reject loudly | FR-009 | contract.spec |
| `emit` → live listeners, `{event,id,payload}` | FR-008 | events.spec |
| emit no-listener no-op | FR-010 | events.spec |
| addInitScript before bundle | FR-003 | boot.spec |
| no network | FR-013 | boot.spec (assert 0 non-localhost requests) |
| `transformCallback`/`listen` shape pin | FR-017 | contract.spec |
