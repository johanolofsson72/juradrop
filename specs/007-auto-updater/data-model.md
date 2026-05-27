# Data Model — Spec 007

Date: 2026-05-27

## Enums

### UpdateState (new — `src-tauri/src/updater/state.rs`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateState {
    Unknown,
    Checking,
    UpToDate,
    Available,
    Downloading,
    ReadyToInstall,
    Restarting,
    Failed,
}
```

**Transitions** (from spec.allium):
- `Unknown → Checking` (auto on launch, or manual via `check_for_updates_now`)
- `UpToDate → Checking` (manual or 4h tick)
- `Failed → Checking` (manual or 4h tick — recovery path)
- `Checking → UpToDate | Available | Failed`
- `Available → Downloading | Failed`
- `Downloading → ReadyToInstall | Failed`
- `ReadyToInstall → Restarting | Failed`
- `Restarting` is terminal (process is being replaced)

### UpdateFailure (new — `src-tauri/src/updater/errors.rs`)

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize, thiserror::Error)]
#[serde(rename_all = "snake_case")]
pub enum UpdateFailure {
    #[error("Kan inte nå GitHub — kontrollera nätverksanslutningen")]
    NoNetwork,

    #[error("Uppdateringsservern svarade med ogiltigt innehåll")]
    ManifestMalformed,

    #[error("Säkerhetskontrollen misslyckades — uppdateringen installeras inte")]
    SignatureInvalid,

    #[error("Nedladdningen avbröts — försök igen")]
    DownloadInterrupted,

    #[error("Kunde inte installera uppdateringen")]
    InstallFailed,

    #[error("Den nya versionen kräver en nyare macOS — uppdatera macOS först")]
    UnsupportedPlatform,
}
```

Length check (Swedish chars × 1.0, ASCII × 1.0 — manual count):
- `NoNetwork` — 50 chars
- `ManifestMalformed` — 49 chars
- `SignatureInvalid` — 65 chars
- `DownloadInterrupted` — 35 chars
- `InstallFailed` — 33 chars
- `UnsupportedPlatform` — 60 chars

All under 80 chars ✓ (SwedishCopy invariant).

## Entities

### Updater (new — `src-tauri/src/updater/state.rs`)

```rust
pub struct Updater {
    pub state: UpdateState,
    pub current_version: String,             // built at compile time via env!("CARGO_PKG_VERSION")
    pub latest_known_version: Option<String>,
    pub release_notes: Option<String>,       // raw text from the manifest
    pub download_url: Option<String>,
    pub progress_pct: u8,                    // 0–100, meaningful only while Downloading
    pub last_emitted_pct: u8,                // for FR-007 debounce (one event per integer percent)
    pub pending_restart_consent: bool,       // FR-009 deferral gate
    pub indicator_dismissed: bool,           // FR-018
    pub last_checked_at: Option<chrono::DateTime<chrono::Local>>,
    pub last_failure: Option<UpdateFailure>,
    pub last_failure_at: Option<chrono::DateTime<chrono::Local>>,
    pub downloaded_bytes: Option<Vec<u8>>,   // held in memory between Downloading and Restarting
    pub cancel_token: tokio_util::sync::CancellationToken,  // for the 4h task
}

impl Updater {
    pub fn new() -> Self {
        Self {
            state: UpdateState::Unknown,
            current_version: env!("CARGO_PKG_VERSION").to_string(),
            latest_known_version: None,
            release_notes: None,
            download_url: None,
            progress_pct: 0,
            last_emitted_pct: 0,
            pending_restart_consent: false,
            indicator_dismissed: false,
            last_checked_at: None,
            last_failure: None,
            last_failure_at: None,
            downloaded_bytes: None,
            cancel_token: tokio_util::sync::CancellationToken::new(),
        }
    }
}
```

**Invariants**:
- `pending_restart_consent == true` ⇒ `state == ReadyToInstall`. Cleared on every transition out of `ReadyToInstall`.
- `downloaded_bytes.is_some()` ⇒ `state ∈ {ReadyToInstall, Restarting}`. Cleared on transition back to `Failed | Available`.
- `progress_pct ∈ [0, 100]`. Only meaningful while `state == Downloading`.
- `last_emitted_pct ≤ progress_pct` (monotonically tracks emissions).
- `last_failure.is_some()` ⇒ `state == Failed` OR last transition was out of `Failed`.

## Values

### UpdateStatus (new — `src-tauri/src/updater/status.rs`)

The mirrored value emitted on `juradrop://update-status`. Tagged-union shape so the TS consumer can pattern-match exhaustively.

```rust
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum UpdateStatus {
    Unknown,
    Checking,
    UpToDate {
        version: String,
        checked_at: String,   // ISO 8601 local-time
    },
    Available {
        version: String,
        notes: String,
        download_url: String,
    },
    Downloading {
        version: String,
        progress_pct: u8,
    },
    ReadyToInstall {
        version: String,
        deferred: bool,       // FR-009 — true while pending_restart_consent is true
    },
    Restarting {
        version: String,
    },
    Failed {
        failure: UpdateFailure,
        message: String,      // the Swedish copy from UpdateFailure
        checked_at: String,
    },
}

impl UpdateStatus {
    pub fn from_updater(u: &Updater) -> Self {
        match u.state {
            UpdateState::Unknown => Self::Unknown,
            UpdateState::Checking => Self::Checking,
            UpdateState::UpToDate => Self::UpToDate {
                version: u.current_version.clone(),
                checked_at: u.last_checked_at.as_ref().unwrap().to_rfc3339(),
            },
            UpdateState::Available => Self::Available {
                version: u.latest_known_version.clone().unwrap(),
                notes: u.release_notes.clone().unwrap_or_default(),
                download_url: u.download_url.clone().unwrap(),
            },
            UpdateState::Downloading => Self::Downloading {
                version: u.latest_known_version.clone().unwrap(),
                progress_pct: u.progress_pct,
            },
            UpdateState::ReadyToInstall => Self::ReadyToInstall {
                version: u.latest_known_version.clone().unwrap(),
                deferred: u.pending_restart_consent,
            },
            UpdateState::Restarting => Self::Restarting {
                version: u.latest_known_version.clone().unwrap(),
            },
            UpdateState::Failed => Self::Failed {
                failure: u.last_failure.unwrap(),
                message: u.last_failure.unwrap().to_string(),
                checked_at: u.last_failure_at.as_ref().unwrap().to_rfc3339(),
            },
        }
    }
}
```

## TypeScript mirror types (`src/lib/tauri-bridge.ts`)

```typescript
export type UpdateStateTag =
  | 'unknown'
  | 'checking'
  | 'up_to_date'
  | 'available'
  | 'downloading'
  | 'ready_to_install'
  | 'restarting'
  | 'failed';

export type UpdateFailureVariant =
  | 'no_network'
  | 'manifest_malformed'
  | 'signature_invalid'
  | 'download_interrupted'
  | 'install_failed'
  | 'unsupported_platform';

export type UpdateStatus =
  | { state: 'unknown' }
  | { state: 'checking' }
  | { state: 'up_to_date'; version: string; checked_at: string }
  | { state: 'available'; version: string; notes: string; download_url: string }
  | { state: 'downloading'; version: string; progress_pct: number }
  | { state: 'ready_to_install'; version: string; deferred: boolean }
  | { state: 'restarting'; version: string }
  | { state: 'failed'; failure: UpdateFailureVariant; message: string; checked_at: string };
```

## Module shape

```text
src-tauri/src/updater/
├── mod.rs                          # pub use: Updater, UpdateState, UpdateStatus, UpdateFailure, commands
├── state.rs                        # UpdateState enum + Updater struct
├── status.rs                       # UpdateStatus mirrored value + From<&Updater> impl
├── errors.rs                       # UpdateFailure enum + Swedish copy + plugin error mapping
├── commands.rs                     # 4 Tauri commands (check, install, cancel_deferred, dismiss)
├── tick.rs                         # 4-hour background task + the launch-time delay
└── deferral.rs                     # any_zone_processing() predicate + deferred-restart fire-now logic
```

## Cross-language drift detection

`src-tauri/tests/fixtures/update-failure-strings.json` — single source of truth for the six Swedish error strings. Rust side asserts every variant's `to_string()` matches the fixture; TS side asserts the `SWEDISH_UPDATE_ERROR` lookup table matches. Same pattern as spec 003's `zone-error-strings.json` (T048 cross-language drift assertion).

```json
{
  "_comment": "Spec 007 — single source of truth for the six UpdateFailure Swedish strings. Rust + TS both assert against this.",
  "no_network": "Kan inte nå GitHub — kontrollera nätverksanslutningen",
  "manifest_malformed": "Uppdateringsservern svarade med ogiltigt innehåll",
  "signature_invalid": "Säkerhetskontrollen misslyckades — uppdateringen installeras inte",
  "download_interrupted": "Nedladdningen avbröts — försök igen",
  "install_failed": "Kunde inte installera uppdateringen",
  "unsupported_platform": "Den nya versionen kräver en nyare macOS — uppdatera macOS först"
}
```

## Tauri event channel name

`juradrop://update-status` (FR-003). Unique — no collision with `juradrop://zone/<slug>` or `juradrop://file-dropped` (spec 004) or `juradrop://sidecar/status` (spec 002). SC-007 codifies this.
