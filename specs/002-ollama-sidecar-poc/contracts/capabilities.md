# Contract: `src-tauri/capabilities/default.json` update

Spec 001 set `permissions: []`. Spec 002 adds exactly the permissions required to spawn the bundled Ollama sidecar and let the WebView receive status events. Nothing else.

## Required content (replaces the spec-001 version)

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Ollama sidecar PoC — adds shell:sidecar:ollama and event:default. No filesystem, no http, no shell beyond the bundled binary. Per FR-016 / R-008.",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:app:default",
    "core:event:default",
    {
      "identifier": "shell:allow-spawn",
      "allow": [
        { "name": "binaries/ollama", "sidecar": true, "args": true }
      ]
    },
    "shell:allow-kill",
    "shell:allow-stdin-write"
  ]
}
```

## Permission rationale (per entry)

| Permission | Why we need it |
|------------|----------------|
| `core:default` | Required by Tauri 2.x for the WebView to invoke any `#[tauri::command]`. Without it the four custom commands are unreachable. Granular alternative: list each command identifier — verbose without security benefit since we wrote them all. |
| `core:app:default` | Allows `app_data_dir()` resolution for consent.json. |
| `core:event:default` | Allows `listen()` from the WebView for `juradrop://status` and `juradrop://progress`. |
| `shell:allow-spawn` (scoped) | Spawn the bundled Ollama sidecar. The `allow` list restricts the scope to exactly the `binaries/ollama` sidecar — arbitrary executables are still denied. |
| `shell:allow-kill` | Terminate the spawned child on app quit (FR-003). Scoped via the same allow-list pattern internally. |
| `shell:allow-stdin-write` | Pipe `OLLAMA_HOST=...` / other env-style config into the child (Tauri's sidecar API uses stdin for some configuration paths). Listed for completeness; remove if unused after implementation. |

## What is deliberately NOT in this allowlist

- **No `fs:*` permissions** — JuraDrop never reads or writes Ollama's model files; Ollama manages them. Consent JSON is written via Tauri's `app` API (not the `fs` plugin).
- **No `http:*` permissions** — All HTTP is done from Rust core (reqwest), not from the WebView.
- **No `dialog:*` permissions** — No file-picker / system dialog at this spec; native dialog API arrives in spec 003 for drop-zone file selection.
- **No `process:exit`** — graceful shutdown is handled by the close-window handler in `lib.rs` from spec 001.

## Contract assertions

| Assertion | Verification |
|-----------|--------------|
| `permissions` does NOT contain any `fs:*` entry | Static JSON inspection (Vitest test on the file content) |
| `permissions` does NOT contain any `http:*` entry | Static JSON inspection |
| `shell:allow-spawn` scope is exactly `binaries/ollama` | Static JSON inspection — exact-match assertion |
| `windows` is exactly `["main"]` (no other window labels) | Static JSON inspection |
| No `"identifier": "default"` clash with future capability files | Future spec 003 adds new files (`drop-zone.json` etc.), not extra entries here |
