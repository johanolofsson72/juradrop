# Data Model: First drop zone — Sammanfatta

**Phase 1 output**. Mirrors `spec.allium` into concrete Rust + TypeScript shapes. Every entity in the Allium spec has a corresponding type here; every invariant has a comment pointing back to the Allium clause it satisfies.

## Rust (src-tauri/src/zones/)

### `enum ZoneState` (per `DropZone.visible_state`)

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ZoneState {
    Idle,
    Dragover,
    Processing,
    Success,
    Error,
}
```

Transitions match the Allium `transitions visible_state` block. No runtime-validated transition graph — invalid transitions can't happen from the current callers (mirroring the spec 002 F9 decision).

### `enum JobOutcome` (per `DropJob.outcome`)

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JobOutcome {
    InFlight,
    Success,
    Failure,
    Cancelled,
}
```

### `enum ZoneFailure` (per `SummaryFailure`)

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum ZoneFailure {
    #[error("endast .docx i denna version")]        InvalidFormat,
    #[error("ett dokument i taget")]                 MultipleFiles,
    #[error("vänta tills föregående dokument är klart")] ZoneBusy,
    #[error("AI är inte redo ännu")]                 ZoneDisabled,
    #[error("kunde inte läsa dokumentet")]           ParseError,
    #[error("dokumentet är lösenordsskyddat")]       PasswordProtected,
    #[error("dokumentet innehåller ingen text")]    EmptyText,
    #[error("AI-motorn svarade inte — försök igen")] ModelError,
    #[error("kunde inte spara sammanfattningen")]   SaveError,
}
```

The Swedish strings live on the `Display` impl via `#[error(...)]` so the Rust side has a single source of truth. The TS layer mirrors them — see below.

Invariant carriers (per Allium `value SwedishCopy`):
- Each variant's string is ≤ 80 chars (covered by `LengthBounded` — unit-tested).
- No string starts with `Error:` (covered by `NoEnglishPrefix` — unit-tested).
- All non-empty (compile-time obvious).

### `struct DropJob` (per `entity DropJob`)

```rust
pub struct DropJob {
    pub id: uuid::Uuid,                          // monotonic identifier per zone session
    pub source_path: PathBuf,
    pub started_at: chrono::DateTime<chrono::Local>,
    pub outcome: JobOutcome,                     // mutated as the job progresses
    pub truncated: bool,                         // FR-019 — was the input truncated?
    pub cancel_token: tokio_util::sync::CancellationToken,
    pub finished_at: Option<chrono::DateTime<chrono::Local>>, // set in terminal states
}
```

Invariants:
- `SuccessHasSummary` — checked by `WriteSummaryDoc*` rules — when `outcome = Success`, the matching `SummaryDoc` exists at the expected path on disk.
- `FailureHasReason` — when `outcome = Failure`, the caller carries a `ZoneFailure`.
- `CancelledLeavesNoSidecar` — when `outcome = Cancelled`, no sidecar file at the canonical or timestamped path.

### `struct SummaryDoc` (per `entity SummaryDoc`)

```rust
pub struct SummaryDoc {
    pub path: PathBuf,
    pub source_path: PathBuf,
    pub header_filename_paragraph: String,       // "Sammanfattning av '<name>'"
    pub header_meta_paragraph: String,           // "Genererad <local-now> av JuraDrop ..."
    pub truncation_notice: Option<String>,       // present iff source was truncated
    pub body_paragraphs: Vec<String>,            // ≥ 1
}
```

Invariants:
- `HeaderAlwaysPresent` — both header strings non-empty.
- `BodyNonEmpty` — `body_paragraphs.len() >= 1`.
- `AtomicWrite` — write helper enforces `.tmp` + `fsync` + `rename`.

### `struct ZoneSnapshot` (the payload emitted to the WebView)

```rust
#[derive(Debug, Clone, serde::Serialize)]
pub struct ZoneSnapshot {
    pub state: ZoneState,
    pub disabled: bool,
    pub failure: Option<ZoneFailure>,            // surfaces the current error string
    pub job_id: Option<uuid::Uuid>,              // identifies the in-flight or terminal job
    pub progress_hint: Option<String>,           // "Sammanfattar…", "Klar — öppnar fil…", etc.
}
```

Emitted on `juradrop://sammanfatta` per `contracts/tauri-events.md`.

### Helper types

```rust
pub struct SourceDocument {
    pub path: PathBuf,
    pub byte_len: u64,
    pub sha256_before: [u8; 32],  // test-only invariant guard (R-009)
}

pub struct ExtractedText {
    pub raw: Redacted<String>,    // FR-004 — never logged
    pub char_count: usize,
    pub was_truncated: bool,
}
```

## TypeScript (src/components/, src/lib/)

### Mirror enums

```typescript
export type ZoneState = 'idle' | 'dragover' | 'processing' | 'success' | 'error';

export type JobOutcome = 'in_flight' | 'success' | 'failure' | 'cancelled';

export type ZoneFailure =
  | 'invalid_format'
  | 'multiple_files'
  | 'zone_busy'
  | 'zone_disabled'
  | 'parse_error'
  | 'password_protected'
  | 'empty_text'
  | 'model_error'
  | 'save_error';
```

`serde(rename_all = "snake_case")` on the Rust enums produces exactly these wire values.

### `zoneErrorMessage` (Swedish copy mapping)

`src/components/SammanfattaZone.errors.ts`:

```typescript
export const SWEDISH_ZONE_ERROR: Record<ZoneFailure, string> = {
  invalid_format:     'Endast .docx i denna version',
  multiple_files:     'Ett dokument i taget',
  zone_busy:          'Vänta tills föregående dokument är klart',
  zone_disabled:      'AI är inte redo ännu',
  parse_error:        'Kunde inte läsa dokumentet',
  password_protected: 'Dokumentet är lösenordsskyddat',
  empty_text:         'Dokumentet innehåller ingen text',
  model_error:        'AI-motorn svarade inte — försök igen',
  save_error:         'Kunde inte spara sammanfattningen',
};
```

Tests assert exact-string equivalence with the Rust `Display` impls so the two sources never drift (see `__tests__/SammanfattaZone.errors.test.tsx`).

### `ZoneSnapshot` mirror

```typescript
export interface ZoneSnapshot {
  state: ZoneState;
  disabled: boolean;
  failure: ZoneFailure | null;
  job_id: string | null;          // UUID
  progress_hint: string | null;
}
```

### Zustand store extension

`src/lib/status-store.ts` gains a `zone: ZoneSnapshot` slice that the React component subscribes to:

```typescript
interface StatusStoreState {
  status: AppStatus;              // existing from spec 002
  zone: ZoneSnapshot;             // new
  setZone(snapshot: ZoneSnapshot): void;
}
```

The store auto-subscribes to `juradrop://sammanfatta` events on first use, mirroring the spec 002 pattern.

## Cross-layer invariants

| Invariant (Allium) | Rust enforcement | TS enforcement |
|---|---|---|
| `DisabledMatchesGlobalStatus` | `Zone::recompute_disabled()` reads `AppState.sidecar_status` and updates `ZoneSnapshot.disabled`. | UI disables drop handlers + greys the zone when `zone.disabled === true`. |
| `SingleFlightWhileProcessing` | `Zone` holds at most one `DropJob` in `Arc<RwLock<Option<DropJob>>>`. New Drop while `Some(_)` returns `ZoneBusy`. | UI shows the `Avbryt` button (only path to clear) while `state === 'processing'`. |
| `ProcessingHasJob` / `IdleHasNoJob` | Type-enforced via the `Option<DropJob>` field. | UI maps `state → job_id` presence in unit tests. |
| `SourceFileImmutable` | The extractor opens the source `O_RDONLY`. `sha256_before` captured at test time and asserted equal post-drop. | N/A — no JS file IO. |
| `OnlyLoopbackOutboundDuringDrop` | Reuses `OllamaClient::with_base_url` from spec 002 (default `127.0.0.1:11434`). Capabilities file does not gain any new permission. | N/A. |
| `SidecarPathsAreUnique` | Naming logic checks `Path::exists()` before claiming the canonical name; otherwise appends timestamp suffix. | N/A. |
| `PromptStaysRedacted` | `ExtractedText.raw: Redacted<String>` flows into `OllamaClient::generate(model, Redacted<String>)`. Never unwrapped for logging. | N/A — content never enters the WebView. |
| `CancelledLeavesNoSidecar` | The write helper only fires after `JobOutcome::Success`. `JobOutcome::Cancelled` short-circuits before the write. | N/A. |
| `AllErrorMessagesSwedish` | `ZoneFailure` `#[error(...)]` strings reviewed by tests + humanizer skill. | `SWEDISH_ZONE_ERROR` map vitest-asserted byte-equal to Rust strings. |
