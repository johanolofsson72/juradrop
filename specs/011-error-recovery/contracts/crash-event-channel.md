# Contract — Tauri crash event channel

**Channel name (pinned)**: `juradrop://sidecar-crashed`

## Emitter

`src-tauri/src/sidecar/manager.rs:126` — the drain task's `child.wait()` await fires the emit after a non-stopping exit.

```rust
let _ = app_for_emit.emit("juradrop://sidecar-crashed", payload.code);
```

**Payload type**: `i32` (the child process exit code).

**Emit guarantees**:
- Exactly one emit per `child.wait()` completion.
- Suppressed if `sidecar.status == Stopping` (clean shutdown, not a crash).
- Compiler ownership rules prevent a second emit per crash (single-await consumes the future).

## Listener

`src-tauri/src/lib.rs:79-100` — the SessionStart listener registered in `setup()`.

```rust
app.handle().listen("juradrop://sidecar-crashed", move |_event| { ... });
```

**Listener guarantees**:
- Idempotent for the retry decision: checks `retry_count_value() == 0` before incrementing.
- Single-shot for retry: only the first crash event in app lifetime causes a `sidecar.spawn` call.
- Subsequent crash events log to stderr (debug-only) and set `error_override = FelOvantat`.

## Channel uniqueness

Per `CrashChannelNameUnique` invariant, the channel name does NOT collide with any other Tauri event in the app:

- `juradrop://status` — spec 002
- `juradrop://progress` — spec 002
- `juradrop://file-dropped` — spec 004
- `juradrop://update-status` — spec 007
- `juradrop://zone/<slug>` — spec 003/004
- `juradrop://settings/tier-download-requested` — spec 010
- `juradrop://sidecar-crashed` — spec 002 / this spec

A new spec adding a Tauri channel MUST avoid this list.

## Payload privacy

The `i32` exit code carries no PII, no path, no user-content fragment. It is consumed ONLY by:

1. The listener's `eprintln!` (debug-only, stderr-only, never surfaced to WebView).
2. Future debug-only logging (none currently exists; if added, must follow the same stderr-only convention).

The exit code is NEVER:
- Returned across the Tauri command boundary in any user-facing String.
- Embedded in any Swedish copy fixture entry.
- Written to any file owned by JuraDrop.
- Transmitted via any outbound HTTP call (there are none).

This is enforced by FR-013's grep test (any user-facing string containing `exit \d+` or signal names like `SIGKILL` fails CI) and by `CrashExitCodeNeverInUserFacingStrings` invariant.
