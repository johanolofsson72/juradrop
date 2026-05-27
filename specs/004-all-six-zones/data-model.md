# Data Model: All six drop zones

**Phase 1 output**. Mirrors `spec.allium` into concrete Rust + TypeScript shapes; mostly an additive layer over the spec 003 data model (re-exported, not redefined).

## Rust (`src-tauri/src/zones/zone_id.rs`)

### `enum ZoneId`

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ZoneId {
    Sammanfatta,
    TillEngelska,
    TillSvenska,
    Punktlista,
    Anonymisera,
    Forenkla,
}

impl ZoneId {
    /// FR-003 — used as the URL slug + filesystem suffix + module name.
    pub fn slug(self) -> &'static str { /* match → "sammanfatta" | "tillengelska" | ... */ }

    /// FR-004 — Swedish title shown in the zone header.
    pub fn title(self) -> &'static str { /* "Sammanfatta" | "Till engelska" | ... */ }

    /// FR-005 — per-zone Swedish hint copy (pulled in from spec 010).
    pub fn hint_copy(self) -> &'static str { /* "Släpp ett .docx för sammanfattning" | ... */ }

    /// FR-007 — the per-zone sidecar filename suffix.
    pub fn sidecar_suffix(self) -> &'static str { /* "sammanfatta" | "tillengelska" | "anonymiserad" | ... */ }

    /// FR-009 — first-header-paragraph template. `{name}` is the
    /// substitution token for the source filename + extension.
    pub fn header_paragraph_template(self) -> &'static str { /* "Sammanfattning av '{name}'" | ... */ }

    /// FR-006 — the per-zone system prompt sent to gemma3:4b.
    /// Loaded from src-tauri/src/prompts/<slug>.rs.
    pub fn system_prompt(self) -> &'static str { /* match → SAMMANFATTA_SYSTEM_PROMPT | ... */ }

    /// FR-013 + FR-014 — Anonymise and Förenkla get a disclaimer
    /// paragraph between the header and the body. Other zones return None.
    pub fn disclaimer_paragraph(self) -> Option<&'static str> { /* ... */ }

    /// Iterate every variant — used by tests and the App.tsx grid layout.
    pub const ALL: [ZoneId; 6] = [
        ZoneId::Sammanfatta,
        ZoneId::TillEngelska,
        ZoneId::TillSvenska,
        ZoneId::Punktlista,
        ZoneId::Anonymisera,
        ZoneId::Forenkla,
    ];
}
```

### `pub struct DropZone` (renamed from `SammanfattaZone`)

```rust
pub struct DropZone {
    id: ZoneId,
    state: Arc<RwLock<ZoneInternalState>>,
}

impl DropZone {
    pub fn new(id: ZoneId) -> Arc<Self> { /* ... */ }
    pub fn id(&self) -> ZoneId { self.id }

    // Methods carry over from SammanfattaZone:
    // handle_drop, dispatch, cancel, refresh_disabled,
    // emit_failure, finalize_with_failure / cancellation,
    // schedule_success_clear / error_clear, auto_clear_to_idle.
}
```

The `state.current_job` slot, the visible-state machine, the cancel-token race, the dispatch pipeline — all unchanged from spec 003's `SammanfattaZone`. Generalisation is mechanical: every spec 003 internal reference to "sammanfatta" / specific suffix / specific prompt now reads from `self.id.{suffix(), system_prompt(), ...}`.

### `AppState`

```rust
#[derive(Clone)]
pub struct AppState {
    pub sidecar: Arc<OllamaSidecar>,
    pub client: Arc<OllamaClient>,
    pub model_status: Arc<RwLock<ModelStatus>>,
    pub progress: Arc<RwLock<Option<u8>>>,
    pub consent: Arc<RwLock<ConsentRecord>>,
    pub error_override: Arc<RwLock<Option<UserVisibleStatus>>>,
    pub zones: HashMap<ZoneId, Arc<DropZone>>,  // NEW — one per ZoneId
}
```

Six `DropZone` instances built at `AppState::new()`. The map is small + immutable after construction; `Arc<DropZone>` clones cheaply.

## TypeScript (`src/components/DropZone.identity.ts`)

```typescript
// Mirror of Rust's ZoneId::associated() functions. Hand-authored;
// drift detected by a vitest test against the
// specs/004-all-six-zones/zone-identity.json fixture.

export type ZoneId =
  | 'sammanfatta'
  | 'tillengelska'
  | 'tillsvenska'
  | 'punktlista'
  | 'anonymisera'
  | 'forenkla';

export interface ZoneIdentity {
  slug: ZoneId;
  title: string;
  hintCopy: string;
  sidecarSuffix: string;
  hasDisclaimer: boolean;
}

export const ZONE_IDENTITIES: Record<ZoneId, ZoneIdentity> = {
  sammanfatta: {
    slug: 'sammanfatta',
    title: 'Sammanfatta',
    hintCopy: 'Släpp ett .docx för sammanfattning',
    sidecarSuffix: 'sammanfatta',
    hasDisclaimer: false,
  },
  tillengelska: {
    slug: 'tillengelska',
    title: 'Till engelska',
    hintCopy: 'Släpp ett .docx för engelsk översättning',
    sidecarSuffix: 'tillengelska',
    hasDisclaimer: false,
  },
  tillsvenska: {
    slug: 'tillsvenska',
    title: 'Till svenska',
    hintCopy: 'Släpp ett .docx för svensk översättning',
    sidecarSuffix: 'tillsvenska',
    hasDisclaimer: false,
  },
  punktlista: {
    slug: 'punktlista',
    title: 'Punktlista',
    hintCopy: 'Släpp ett .docx för punktlista',
    sidecarSuffix: 'punktlista',
    hasDisclaimer: false,
  },
  anonymisera: {
    slug: 'anonymisera',
    title: 'Anonymisera',
    hintCopy: 'Släpp ett .docx för anonymisering',
    sidecarSuffix: 'anonymiserad',  // past-participle adjective
    hasDisclaimer: true,
  },
  forenkla: {
    slug: 'forenkla',
    title: 'Förenkla',
    hintCopy: 'Släpp ett .docx för klarspråk',
    sidecarSuffix: 'forenkla',
    hasDisclaimer: true,
  },
};

export const ZONE_ORDER: ZoneId[] = [
  // Reading order across the 2×3 grid, row 1 then row 2.
  'sammanfatta',
  'tillengelska',
  'tillsvenska',
  'punktlista',
  'anonymisera',
  'forenkla',
];
```

### Zustand store

```typescript
interface StatusStoreState {
  status: AppStatus;                            // existing spec 002
  zones: Record<ZoneId, ZoneSnapshot>;          // NEW — per-zone snapshot
  setZone(id: ZoneId, snapshot: ZoneSnapshot): void;
}
```

Initial state: every zone seeded with `{ state: 'idle', disabled: true, failure: null, job_id: null, progress_hint: null }`. As `juradrop://zone/<slug>` events arrive, each zone's slot updates independently.

## Cross-layer invariant table

| Invariant | Rust enforcement | TS enforcement |
|---|---|---|
| `EachZoneHasUniqueId` | `AppState::new()` constructs the `HashMap<ZoneId, Arc<DropZone>>` with `ZoneId::ALL`; duplicates impossible. | `ZONE_IDENTITIES` is typed `Record<ZoneId, ZoneIdentity>` — the type system rejects missing keys. |
| `SidecarSuffixMatchesZoneId` | `ZoneId::sidecar_suffix()` is an exhaustive `match`; missing variant fails to compile. | `DropZone.identity.test.tsx` asserts the suffix table against the JSON fixture. |
| `PerZoneSingleFlight` | Each `Arc<DropZone>` owns its own `Arc<RwLock<Option<DropJob>>>`. Cross-zone reads aren't possible. | UI maps `zone_id` → component instance; each component reads only its own slot. |
| `DisclaimerOnlyOnAnonymiseAndForenkla` | `ZoneId::disclaimer_paragraph()` returns `Some(...)` only for those two variants. | `ZONE_IDENTITIES[*].hasDisclaimer` is `true` only for those two. |
| `AllZonesShareDisabledGate` | Each `DropZone::refresh_disabled` reads the global `AppState.sidecar.status()`. | The store's `disabled` is the OR of `zones[id].disabled` and `status.visible !== 'klar'`. |
| `OnlyLoopbackOutboundAcrossAllZones` | All six dispatch paths use the shared `AppState.client: Arc<OllamaClient>`. | N/A. |
| `SourceImmutableAcrossAllZones` | Inherited from spec 003 — every dispatch opens the source `O_RDONLY` and never writes. | N/A. |
