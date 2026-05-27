# Tauri events contract — Spec 007

One new event channel. Tagged-union payload (see `UpdateStatus` in `data-model.md`).

## `juradrop://update-status`

Emitted on every transition of `Updater.state` AND on every integer-percent progress tick during `Downloading`.

**Payload shape**: serialised `UpdateStatus` (tagged union with `state` discriminator).

**Example payloads**:

```json
{ "state": "unknown" }
```

```json
{ "state": "checking" }
```

```json
{
  "state": "up_to_date",
  "version": "0.1.0",
  "checked_at": "2026-05-27T15:30:42+02:00"
}
```

```json
{
  "state": "available",
  "version": "0.2.0",
  "notes": "## What's new\n\n- Added Punktlista zone\n- Fixed PDF extraction crash on encrypted files",
  "download_url": "https://github.com/johanolofsson72/juradrop/releases/download/v0.2.0/JuraDrop_0.2.0_universal.dmg"
}
```

```json
{
  "state": "downloading",
  "version": "0.2.0",
  "progress_pct": 73
}
```

```json
{
  "state": "ready_to_install",
  "version": "0.2.0",
  "deferred": false
}
```

```json
{
  "state": "ready_to_install",
  "version": "0.2.0",
  "deferred": true
}
```

```json
{
  "state": "restarting",
  "version": "0.2.0"
}
```

```json
{
  "state": "failed",
  "failure": "no_network",
  "message": "Kan inte nå GitHub — kontrollera nätverksanslutningen",
  "checked_at": "2026-05-27T15:30:42+02:00"
}
```

## Subscription pattern (TypeScript)

```typescript
// src/lib/tauri-bridge.ts
import { listen } from '@tauri-apps/api/event';
import type { UpdateStatus } from './tauri-bridge';

export function subscribeUpdateStatus(callback: (status: UpdateStatus) => void): () => void {
  const unlistenPromise = listen<UpdateStatus>('juradrop://update-status', (event) => {
    callback(event.payload);
  });

  return () => {
    unlistenPromise.then((unlisten) => unlisten());
  };
}
```

The Zustand slice (`src/lib/update-store.ts`) subscribes once at app startup and forwards every payload to the store.

## Emission rate

- State-transition events: 1 per transition. The state machine has at most ~10 transitions during a single update lifecycle, so ~10 emissions.
- Download-progress events: 1 per integer percent change. A 50 MB DMG produces at most 101 emissions (0–100 inclusive). Debouncing in Rust ensures we never emit twice for the same `progress_pct`.

Total per update: ~110 events from `Checking` → `Restarting`. Bounded, predictable, no event-storm risk.
