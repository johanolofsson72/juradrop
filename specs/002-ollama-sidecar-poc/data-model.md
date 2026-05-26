# Phase 1 — Data Model: Ollama Sidecar PoC

Maps `spec.allium` entities to concrete Rust types in `src-tauri/src/sidecar/` and a mirrored TS shape in `src/lib/status-store.ts`.

## Rust types (canonical)

```rust
// src-tauri/src/sidecar/status.rs

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SidecarStatus {
    NotStarted,
    Starting,
    Ready,
    Crashed,
    Stopping,
    Stopped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelStatus {
    NotPresent,
    Downloading,
    Ready,
    DownloadFailed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConsentChoice {
    NotAsked,
    Fortsatt,
    Avbryt,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UserVisibleStatus {
    Startar,
    Klar,
    LaddarNerModell,
    BegarSamtycke,
    FelKundeInteStarta,
    FelPortenUpptagen,
    FelDiskFull,
    FelModellnedladdningAvbroten,
    FelOvantat,
    ModellSaknasAvbruten,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct AppStatus {
    pub visible: UserVisibleStatus,
    pub sidecar: SidecarStatus,
    pub model: ModelStatus,
    pub progress_percent: Option<u8>, // Some(0..=100) when model.status = Downloading
    pub consent: ConsentChoice,
}
```

State transitions enforce the `transitions` graphs from `spec.allium` at runtime via a private `transition()` method that returns `Result<(), TransitionError>`. Invalid transitions are programmer bugs and panic in debug builds, log + return error in release.

## Sidecar manager

```rust
// src-tauri/src/sidecar/manager.rs

pub struct OllamaSidecar {
    status: parking_lot::RwLock<SidecarStatus>,
    pid: parking_lot::RwLock<Option<u32>>,
    port: u16,        // pinned to 11434 by config + invariant
    host: &'static str, // "127.0.0.1"
    retry_count: AtomicU8,
}

impl OllamaSidecar {
    pub async fn spawn(app: &AppHandle) -> Result<Self, SidecarError>;
    pub async fn wait_ready(&self, timeout: Duration) -> Result<(), SidecarError>;
    pub async fn stop(&self, grace: Duration) -> Result<(), SidecarError>;
    pub fn status(&self) -> SidecarStatus;
}

pub enum SidecarError {
    BundledBinaryMissing,    // FR-015 → FelKundeIntStarta
    PortBusy,                // US4 #3 → FelPortenUpptagen
    StartupTimeout,          // SC-001 violation → FelKundeIntStarta
    Crashed { exit_code: Option<i32> }, // → FelOvantat (after retry)
    ShutdownTimeout,         // log only; force-kill follows
}
```

## Model artifact + client

```rust
// src-tauri/src/sidecar/client.rs

pub struct OllamaClient {
    http: reqwest::Client, // base_url = http://127.0.0.1:11434
}

impl OllamaClient {
    pub async fn list_tags(&self) -> Result<Vec<String>, ClientError>;
    pub fn pull_stream(&self, model: &str) -> impl Stream<Item = PullEvent>;
    pub async fn generate(&self, model: &str, prompt: Redacted<String>) -> Result<Redacted<String>, ClientError>;
}

pub enum PullEvent {
    Progress { percent: u8 },
    Completed,
    Failed(PullError),
}

pub enum PullError {
    DiskFull,
    Network,
    Other(String), // never includes prompt/response — pull doesn't have them
}
```

Note the `pull_stream` returning a `Stream` does NOT contradict FR-021. FR-021 forbids streaming for `/api/generate` (inference). `/api/pull` (download progress) is allowed to be a stream because that's the only way to surface progress. R-005 documents this distinction.

## Consent persistence

```rust
// src-tauri/src/sidecar/consent.rs

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ConsentRecord {
    pub schema_version: u8,        // 1
    pub choice: ConsentChoice,
    pub asked_at: Option<chrono::DateTime<chrono::Utc>>,
}

impl ConsentRecord {
    pub async fn load(app: &AppHandle) -> ConsentRecord;        // absent file → NotAsked, asked_at = None
    pub async fn save(&self, app: &AppHandle) -> io::Result<()>; // atomic write (.tmp + rename)
}
```

Path: `app.path().app_data_dir()?.join("consent.json")`.

## Log-safe newtype

```rust
// src-tauri/src/sidecar/log_safe.rs

pub struct Redacted<T>(pub T);

impl<T> fmt::Debug for Redacted<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "<redacted>")
    }
}

impl<T> fmt::Display for Redacted<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "<redacted>")
    }
}

impl<T: AsRef<str>> Redacted<T> {
    pub fn len(&self) -> usize { self.0.as_ref().len() } // length only, never content
    pub fn into_inner(self) -> T { self.0 }
}
```

Every inference call returns `Redacted<String>` and accepts `Redacted<String>`. The compiler enforces no log site can print the inner value with `{}` or `{:?}`.

## TypeScript mirror

```ts
// src/lib/status-store.ts

export type SidecarStatus = 'not_started' | 'starting' | 'ready' | 'crashed' | 'stopping' | 'stopped';
export type ModelStatus = 'not_present' | 'downloading' | 'ready' | 'download_failed';
export type ConsentChoice = 'not_asked' | 'fortsatt' | 'avbryt';
export type UserVisibleStatus =
  | 'startar' | 'klar' | 'laddar_ner_modell' | 'begar_samtycke'
  | 'fel_kunde_inte_starta' | 'fel_porten_upptagen' | 'fel_disk_full'
  | 'fel_modellnedladdning_avbroten' | 'fel_ovantat' | 'modell_saknas_avbruten';

export interface AppStatus {
  visible: UserVisibleStatus;
  sidecar: SidecarStatus;
  model: ModelStatus;
  progress_percent: number | null;
  consent: ConsentChoice;
}

// zustand store
export interface StatusStore {
  status: AppStatus;
  setStatus: (next: AppStatus) => void;
  giveConsent: () => Promise<void>;   // invoke('give_consent')
  cancelConsent: () => Promise<void>; // invoke('cancel_consent')
}
```

Wire-format match between Rust serde and TS is exact (snake_case enums on both sides).

## State transitions (canonical)

Derived from `spec.allium`:

**SidecarStatus**: `not_started → starting → ready → stopping → stopped`. Crash paths: `starting → crashed` and `ready → crashed`. Crash terminal: `crashed → stopped` after kill.

**ModelStatus**: `not_present → downloading → ready`. Failure: `downloading → download_failed → downloading` (on next launch — FR-020 idempotent re-pull). `ready → not_present` only if user manually deletes the model file (edge case).

**ConsentChoice**: `not_asked → fortsatt | avbryt`. Terminal at either. No `avbryt → fortsatt` transition this spec — user must re-launch to be asked again (FR-019b).

**UserVisibleStatus**: derived (computed) from the three above. Not stored independently.
