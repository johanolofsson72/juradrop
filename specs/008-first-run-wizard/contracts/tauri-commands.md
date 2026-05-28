# Tauri commands contract — Spec 008

Spec 008 adds **one new Tauri command** (`cancel_model_pull`). The existing `give_consent` + `cancel_consent` commands from spec 002 are unchanged.

## `cancel_model_pull`

```rust
#[tauri::command]
pub async fn cancel_model_pull(
    state: tauri::State<'_, AppState>,
    app: AppHandle,
) -> Result<(), String>;
```

**Behaviour** (per FR-013 + clarification 5):

- Acquires `state.model_status` write-lock.
- If `*model_status == Ready` → silent no-op + return `Ok(())`. The download already completed; the cancel race was won by completion.
- If `*model_status != Downloading` → silent no-op + return `Ok(())`. Idempotent across already-cancelled, never-started, and failed states.
- Else (`*model_status == Downloading`):
  - Trips `state.pull_cancel.cancel()` — the existing pull task's `tokio::select!` exits.
  - Flips `*model_status = NotPresent`.
  - Sets `*state.error_override = Some(UserVisibleStatus::ModellSaknasAvbruten)`.
  - Drops the write-lock.
  - Emits `juradrop://status` with the fresh snapshot.
  - Returns `Ok(())`.

**Errors**: Returns `Err(message)` only on truly exceptional internal failures (e.g. the AppState managed-state lookup returns None). The user-facing path is always through the status event, never the command's `Result`.

**Consent record**: The command MUST NOT touch the consent record. The user's choice from the welcome screen is preserved; the next launch will see `consent = fortsatt` BUT `model_status = NotPresent` and re-show the welcome wizard per FR-012.

**Idempotency**: Safe to invoke repeatedly. The model_status check inside the lock guarantees only the first call within a Downloading window does work.

## Existing commands (unchanged, documented for completeness)

### `give_consent`

```rust
#[tauri::command]
pub async fn give_consent(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<(), String>;
```

Spec 002 behavior. Spec 008 invokes this from the WelcomeWizard's Fortsätt button — same as the existing ConsentModal does today.

### `cancel_consent`

```rust
#[tauri::command]
pub async fn cancel_consent(
    app: AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<(), String>;
```

Spec 002 behavior. Spec 008 invokes this from the WelcomeWizard's Avbryt button + the Escape key path. Per FR-011 + clarification 4, the wizard does NOT transition out of `welcome` phase after a cancel — it stays visible.

## Cancel-race state trace (codified)

```
INVARIANT (R-003): WizardState.phase = welcome ∧ model_status = ready is unreachable.
```

The lock-acquire-order resolution ensures one of the two outcomes always wins:

```
Race outcome A (cancel acquires lock first):
  1. cancel_model_pull acquires lock; model_status == Downloading
  2. trips pull_cancel; sets status to NotPresent
  3. emits status event
  4. pull task wakes inside tokio::select!; cancel branch wins
  5. pull task exits without touching model_status
  6. wizard transitions: progress → welcome (consent stays fortsatt; visible = modell_saknas_avbruten)

Race outcome B (completion acquires lock first):
  1. spawn_pull_task's completion callback acquires lock; sets model_status = Ready
  2. emits status event
  3. cancel_model_pull acquires lock; model_status == Ready
  4. silent no-op
  5. wizard transitions: progress → hidden (consent stays fortsatt; model = ready)
```

Both outcomes are user-coherent. The wizard never shows a frozen "Hämtar…" badge after a completed download.
