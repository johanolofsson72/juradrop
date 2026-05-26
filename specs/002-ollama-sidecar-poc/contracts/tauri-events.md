# Contract: Tauri events

Rust→WebView events for live updates. The WebView subscribes via `@tauri-apps/api/event` `listen()` in the zustand store's bootstrap.

| Event name | Payload | When emitted |
|------------|---------|--------------|
| `juradrop://status` | `AppStatus` | On every transition of any of the three underlying states (SidecarStatus, ModelStatus, ConsentChoice). |
| `juradrop://progress` | `{ percent: u8 }` | While `ModelStatus = Downloading` — emitted at most every 500 ms or when `percent` changes by ≥ 1. Throttled to avoid flooding the IPC channel. |

## Subscription contract

The WebView MUST:
1. Subscribe to both events on app mount.
2. Call `get_status` once on mount to seed the store before any event fires.
3. Treat events as authoritative when received; never compute derived UI state from a stale snapshot.
4. Tear down subscriptions on unmount (cleanup function from `useEffect`).

## Throttling

The `juradrop://progress` event is throttled in Rust by tracking the last-emitted percent and last-emitted timestamp. Emission rule:

```rust
should_emit = (current_percent != last_percent) || (now - last_emit > 500ms);
```

This keeps the WebView responsive without re-rendering the welcome card 60 times per second during a fast LAN pull.

## Backpressure

If the WebView is slow (e.g., DevTools-throttled), Tauri's IPC channel buffers events. Stale `progress` events are harmless (only `percent` matters). Stale `status` events are harmless because each one carries the full snapshot, so the last-arrived wins.
