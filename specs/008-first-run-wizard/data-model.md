# Data Model — Spec 008 first-run wizard

This spec adds **zero new persistent state**. The wizard's phase is a pure function of the existing `AppStatus` snapshot from spec 002; the progress estimate is an ephemeral React-side rolling-window value.

## React-side types

### `WizardPhase` (TS enum-as-union)

```typescript
type WizardPhase = 'welcome' | 'progress' | 'error' | 'hidden';
```

- `welcome` — title + body paragraph + privacy + download note + Fortsätt/Avbryt + sidecar helper
- `progress` — percent bar + byte counter + ETA + Cancel
- `error` — terminal failure (model_missing_aborted, disk_full, download_failed) + Försök-igen + Avbryt-tillbaka
- `hidden` — wizard absent from React tree; zone-grid rendered instead

The four-phase enum is the single source of truth in the React layer. No persistence, no Rust mirror.

### `useWizardState` — derivation hook

```typescript
function useWizardState(): WizardPhase;
```

Reads `useStatusStore()` and returns the current phase per the truth table in research.md R-001. Calling it twice in the same render returns the same value.

### `ProgressEstimate` (TS interface)

```typescript
interface ProgressEstimate {
  last_pct: number;             // 0–100
  last_byte_count: number;      // bytes downloaded so far
  total_byte_count: number;     // total bytes; 0 means unknown
  last_progress_at: number;     // epoch ms of last juradrop://progress
  bytes_per_second_recent: number; // rolling 10s mean; 0 when waiting
  label: 'downloading' | 'waiting';
  eta_seconds: number | null;   // null when bps == 0
  eta_rendered: string;         // "≈ 17 s" | "≈ 3 min" | "—"
}
```

The ETA renderer applies the FR-004 clarified rules:
- `bps === 0` → `'—'`
- `eta_seconds < 60` → `'≈ ' + ceil(eta_seconds / 5) * 5 + ' s'`
- `eta_seconds >= 60` → `'≈ ' + ceil(eta_seconds / 60) + ' min'`

### `useProgressEstimate` — rolling-window hook

```typescript
function useProgressEstimate(opts?: { windowMs?: number; staleThresholdMs?: number }): ProgressEstimate;
```

- `windowMs` default `10_000` — rolling window for the mean-bps estimator
- `staleThresholdMs` default `5_000` — FR-007 network-drop trigger

Reads `useStatusStore()`'s `progress_percent` events (which carry no byte count — the hook reads `model.status` + the `progress_percent` value and synthesises a `byte_count` from the percent + an estimated 2 GB total). Maintains a sample buffer in `useRef`.

### `WIZARD_STRINGS` (TS const)

```typescript
const WIZARD_STRINGS = {
  welcome_title: 'Välkommen till JuraDrop',
  welcome_paragraph: 'JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst.',
  welcome_privacy_line: 'Inget dokumentinnehåll lämnar din Mac.',
  welcome_download_note: 'En AI-modell på cirka 2 GB laddas ner första gången du startar appen — efter det fungerar allt utan nät.',
  welcome_cta_primary: 'Fortsätt',
  welcome_cta_secondary: 'Avbryt',
  welcome_sidecar_helper: 'Förbereder AI-motorn…',
  progress_label_downloading: 'Hämtar AI-modell…',
  progress_label_waiting: 'Väntar på nätverk…',
  progress_cancel_button: 'Avbryt nedladdning',
  progress_eta_unknown: '—',
  progress_error_retry: 'Försök igen',
} as const;
```

Mirrored byte-for-byte from `src-tauri/tests/fixtures/wizard-strings.json` by the cross-language drift test (`WizardCopy.errors.test.tsx`).

## Rust-side additions

### New Tauri command: `cancel_model_pull`

Adds a single command to `src-tauri/src/sidecar/commands.rs`. No new module.

```rust
#[tauri::command]
pub async fn cancel_model_pull(
    state: tauri::State<'_, AppState>,
    app: AppHandle,
) -> Result<(), String> {
    // See R-003 for the cancel-race lock-acquire-order resolution.
    // The command:
    //   1. Acquires the model_status write-lock.
    //   2. If model_status == Ready → silent no-op (race won by completion).
    //   3. If model_status != Downloading → silent no-op (idempotent).
    //   4. Else trips the existing pull_cancel CancellationToken,
    //      flips status to NotPresent, sets error_override to
    //      UserVisibleStatus::ModellSaknasAvbruten, emits a fresh
    //      juradrop://status event.
}
```

The command is registered alongside the existing `give_consent` / `cancel_consent` / `dispatch_to_zone` commands in `lib.rs::generate_handler!`.

### New `AppState` field

`AppState` currently owns the model pull task via `spawn_pull_task` but doesn't hold a separate cancellation handle — the pull task's cancellation lives inside the `OllamaClient::pull` future and is dropped when the future is aborted. To make `cancel_model_pull` work, we add:

```rust
pub struct AppState {
    // ... existing fields ...
    /// Spec 008 — cancellation token for the in-flight model pull.
    /// Tripped by the cancel_model_pull command (FR-013). Reset to
    /// a fresh token on every successful pull start.
    pub pull_cancel: Arc<tokio_util::sync::CancellationToken>,
}
```

`spawn_pull_task` is modified to:
1. Replace `state.pull_cancel` with a fresh CancellationToken before starting.
2. Wrap the `OllamaClient::pull` future in a `tokio::select!` against `state.pull_cancel.cancelled()`.
3. On cancellation, exit the pull cleanly without flipping the model status (the command body owns the status flip — keeps the cancellation path single-responsibility).

### No new event channels

The wizard reads exclusively:
- `juradrop://status` (existing) — for `consent.choice`, `model.status`, `sidecar.status`, `visible`
- `juradrop://progress` (existing) — for the percent value during the pull

SC-007 guarantees zero new outbound surface; the new `cancel_model_pull` command emits to `juradrop://status` only (existing channel).

## Fixture: `wizard-strings.json`

```json
{
  "_comment": "Spec 008 — single source of truth for the 12 Swedish wizard strings. Rust side (src-tauri/tests/wizard_strings.rs) and TS side (src/__tests__/WizardCopy.errors.test.tsx) both assert against this file in their drift-detection tests. Update all three together when changing a string.",
  "welcome_title": "Välkommen till JuraDrop",
  "welcome_paragraph": "JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst.",
  "welcome_privacy_line": "Inget dokumentinnehåll lämnar din Mac.",
  "welcome_download_note": "En AI-modell på cirka 2 GB laddas ner första gången du startar appen — efter det fungerar allt utan nät.",
  "welcome_cta_primary": "Fortsätt",
  "welcome_cta_secondary": "Avbryt",
  "welcome_sidecar_helper": "Förbereder AI-motorn…",
  "progress_label_downloading": "Hämtar AI-modell…",
  "progress_label_waiting": "Väntar på nätverk…",
  "progress_cancel_button": "Avbryt nedladdning",
  "progress_eta_unknown": "—",
  "progress_error_retry": "Försök igen"
}
```

Path: `src-tauri/tests/fixtures/wizard-strings.json`. Same cross-language pattern as spec 007's `update-failure-strings.json`.

## Invariants codified

- `welcome_paragraph.length <= 200` AND `welcome_download_note.length <= 200` — both checked in the Rust + TS cross-language tests (refined 2026-05-28 per /speckit.analyze C1).
- All other strings `length <= 80` — same check.
- No string starts with `Error:` — same check.
- All strings non-empty — same check.

These are the FR-014 + SC-006 contracts in machine-readable form.

## FR-016 vacuous satisfaction note

FR-016 ("no log line emitted by spec 008 may contain document content, IP, system username, or model bytes") is vacuously satisfied because the React-side wizard emits **zero** local logs. No `console.log`, no `eprintln!`, no instrumentation. Phase transitions inside React are state changes, not log emissions. If a future refactor introduces wizard logging, FR-016 becomes binding and must be honored via the spec 007 `log_transition` pattern (state names + version string only). Until then, the invariant has no test surface because there's nothing to test.
