# Plan — 050 reliability-fixes

## Technical approach (per FR)

| FR | File(s) | Change |
|---|---|---|
| 001 | `src-tauri/src/updater/commands.rs` | `run_plugin_install` returns `Result<(), ()>`. On `Ok` → `app.restart()`. `run_deferred_install` records `InstallFailed` only on `Err`. |
| 002 | `src-tauri/src/sidecar/commands.rs` `give_consent` | Clear `error_override` after the consent is persisted, before the disk check. |
| 003 | same, `cancel_consent` | Extract a pure `cancel_consent_allowed(choice, model)` guard (unit-testable). Clear the override on accept. |
| 004 | same, `spawn_pull_task` | Drop the `tokio::time::timeout` wrapper and the `MODEL_PULL_TIMEOUT_SECONDS` constant. The stall detector stays in `client.rs`. |
| 005 | `src-tauri/src/zones/docx_write.rs`, `sammanfatta.rs` | Add `build_summary_doc_for_model(..., model_label)`. The old signature delegates with the default model (tests only). Production passes `model_id`. |
| 006 | `src/lib/wizard-strings.ts`, `ConsentModal.tsx`, `use-progress-estimate.ts` | New `DEFAULT_MODEL_DOWNLOAD` constant in `src/lib/model-download.ts` (label + bytes). A Rust test pins the tier badge "~3.3 GB" to it. |
| 007 | `src-tauri/src/lib.rs` | Move the cleanup into `fn shutdown(app)`, called from `RunEvent::Exit`. `CloseRequested` → `app.exit(0)`. |
| 008 | `sidecar/commands.rs` `after_sidecar_ready` | Retry `list_tags` up to 3× (backoff 1 s, 2 s). On exhaustion set `FelOvantat` + emit. |
| 009 | `WelcomeWizard.tsx`, `ConsentModal.tsx`, `FirstRunProgress.tsx`, `App.tsx`, `wizard-strings.ts` | `.catch` → local error state rendered in a `role="alert"` paragraph; drop failure → `useStatusStore.setStatusMessage`. |
| 010 | `App.tsx`, `DropZone.tsx`, `use-progress-estimate.ts` | Add a `disposed` flag: if cleanup already ran when `listen` resolves, unlisten immediately. Subscribe before `getStatus`. |
| 011 | `src-tauri/capabilities/default.json` | Remove `shell:allow-spawn` and `shell:allow-kill`. A Rust test asserts it. |
| 012 | `scripts/fetch-ollama.sh` | Pin v0.34.4 and its SHA-256. |

## Test plan

- Rust unit tests: `cancel_consent_allowed` truth table (PBT over all 4×3 combos), docx header names the given model, capability file denies spawn/kill, `DEFAULT_MODEL` badge text.
- Vitest: consent rejection → alert text (3 components), drop rejection → status message, late-resolving listen is unlistened (App, DropZone, progress hook), `getStatus` called after `subscribeStatus`, progress estimate uses 3.3 GB.
- Destructive (vitest, per interactive function): retry/cancel buttons double-click, rejection, rejection-then-success, unmount mid-flight.
- TLA+: the consent/pull recovery machine (`/tla`).
