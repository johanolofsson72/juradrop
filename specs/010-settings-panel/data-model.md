# Phase 1 Data Model — Spec 010 Settings Panel

**Date**: 2026-05-28
**Source spec**: [spec.md](spec.md)
**Source Allium**: [spec.allium](spec.allium)

## Entities

### `SettingsSnapshot` (Rust + TypeScript mirror)

In-memory representation of the user's persisted choices. Single source of truth at zone-dispatch time.

**Rust** (`src-tauri/src/settings/snapshot.rs`):

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SettingsSnapshot {
    pub schema_version: SchemaVersion,
    pub model_tier: ModelTier,
}

impl Default for SettingsSnapshot {
    fn default() -> Self {
        Self {
            schema_version: SchemaVersion::V1,
            model_tier: ModelTier::Smart,
        }
    }
}
```

**TypeScript** (`src/types/settings.ts`):

```ts
export type SettingsSnapshot = {
  readonly schema_version: 1;
  readonly model_tier: ModelTier;
};
```

**Lifecycle**:
- Created at app launch by `settings::file_io::load_or_default()`.
- Mutated by `settings::commands::set_model_tier(tier)`.
- Read by `sidecar::commands::dispatch_to_zone()` at every dispatch (FR-009).
- Persisted to disk synchronously inside `set_model_tier` (FR-008).

**Invariants** (enforced by `src-tauri/tests/settings_invariants.rs`):
- `model_tier ∈ {Snabb, Smart, Stor}` — never null, never unset.
- `schema_version = V1` — current version; future migrations bump this.

### `SettingsFile` (on-disk JSON artifact)

JSON at `${app_data_dir}/settings.json`. UTF-8. Exactly two keys.

**Schema** (strict — see [contracts/settings-file-schema.md](contracts/settings-file-schema.md)):

```json
{
  "schema_version": 1,
  "model_tier": "Smart"
}
```

**Allowed `model_tier` values**: `"Snabb"`, `"Smart"`, `"Stor"` (exact-case match, serde-default).

**Forbidden anywhere in the file**:
- Any third key (`telemetry_id`, `session_id`, `last_used_at`, anything).
- Any value of type other than the listed two.
- Any user-content-derived field (document paths, hashes, sample text).
- Any analytics identifier or fingerprint.

**Load behaviour** (rule `RestoreSettingsOnLaunch`):
- File missing → return `SettingsSnapshot::default()`. No error surfaced.
- File present, JSON parses, `schema_version = 1`, `model_tier` is one of the three valid values → return the parsed snapshot.
- File present, JSON parse fails OR `schema_version != 1` OR `model_tier` is unknown → return `SettingsSnapshot::default()` AND emit a debug-only console warning. No Swedish error to the user.

**Save behaviour** (rule `SelectTier`):
- Always overwrite the entire file (no patch-write — full atomic replacement).
- Use `tokio::fs::write` with a temp-file + atomic rename to avoid torn writes if the app is killed mid-write.

### `ModelTier` (Rust enum + TypeScript enum mirror)

The three named tiers.

**Rust** (`src-tauri/src/settings/tier_map.rs`):

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ModelTier {
    Snabb,
    Smart,
    Stor,
}

impl ModelTier {
    pub const fn model_id(self) -> &'static str {
        match self {
            ModelTier::Snabb => "llama3.2:1b",
            ModelTier::Smart => "gemma3:4b",
            ModelTier::Stor  => "gemma3:12b",
        }
    }

    pub const fn size_badge(self) -> &'static str {
        match self {
            ModelTier::Snabb => "~1.3 GB",
            ModelTier::Smart => "~3.3 GB",
            ModelTier::Stor  => "~8.1 GB",
        }
    }

    pub const ALL: [ModelTier; 3] = [ModelTier::Snabb, ModelTier::Smart, ModelTier::Stor];
}
```

**TypeScript** (`src/types/settings.ts`):

```ts
export type ModelTier = 'Snabb' | 'Smart' | 'Stor';
export const MODEL_TIERS: readonly ModelTier[] = ['Snabb', 'Smart', 'Stor'] as const;
```

**Invariant** (`TierMapIsCentralizedAndPinned`): the model ID literals `llama3.2:1b`, `gemma3:4b`, `gemma3:12b` appear in exactly ONE place per codebase — `tier_map.rs`. A CI grep check (in `src-tauri/tests/settings_invariants.rs`) asserts these strings appear nowhere under `src/` (TypeScript) and nowhere under `src-tauri/src/` outside `tier_map.rs`.

### `SchemaVersion` (Rust enum)

Forward-compat sentinel for the on-disk schema.

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(into = "u32", try_from = "u32")]
pub enum SchemaVersion {
    V1 = 1,
}
```

Currently only `V1`. Future migrations bump to `V2` etc. — the load path's malformed-file fallback covers the "encountered an unknown schema_version" case.

### `PanelVisibility` (TypeScript enum, React-side only)

The 4-state panel visibility machine. Lives entirely in React; no Rust mirror.

```ts
export type PanelVisibility = 'closed' | 'opening' | 'open' | 'closing';
```

**Transitions**:

| From      | To        | Trigger                                                  |
|-----------|-----------|----------------------------------------------------------|
| closed    | opening   | Gear icon click; Cmd+, while closed; Cmd+, while closing |
| opening   | open      | Slide-in animation completes                             |
| open      | closing   | Close-X click; Esc; scrim click; Cmd+, while open        |
| closing   | closed    | Slide-out animation completes                            |
| opening   | closing   | Esc / dismiss during slide-in (reverse animation)        |
| closing   | opening   | Repeated open intent during slide-out (coalesce)         |

**Coalescing** (invariant `CoalescedRepeatedOpenIntents`): rapid repeated open intents do NOT stack. The hook tracks a single `PanelVisibility` value at all times; repeated triggers transition through the existing arrows, never spawning a second panel instance.

### `TierRowMode` (TypeScript enum, React-side only)

Per-tier display mode in `ModelTierSection`. Computed from the tier's pull state.

```ts
export type TierRowMode = 'radio_selectable' | 'download_button';
```

**Rule** (`TierRadioIsOnlyEnabledIfModelPulled`):
- `OllamaModelIsPulled(tier.model_id) === true` → `radio_selectable`
- Otherwise → `download_button`

Pull state is fetched from Rust via `get_tier_pull_state` command (see [contracts/settings-commands.md](contracts/settings-commands.md)). Re-fetched after every `Ladda ned` completion via the `settings://tier_pulled` event.

### `TierMapping` (Rust value / config)

The pinned tier → model-ID mapping. One instance, baked into the binary.

```rust
pub struct TierMapping;

impl TierMapping {
    pub const SNABB_MODEL_ID: &'static str = "llama3.2:1b";
    pub const SMART_MODEL_ID: &'static str = "gemma3:4b";
    pub const STOR_MODEL_ID:  &'static str = "gemma3:12b";
}
```

Folded into `tier_map.rs` (not a separate file) to keep the single-source-of-truth promise visible.

### `SettingsPanelStrings` (Rust + TS mirror, drift-fixture sourced)

All user-facing strings for the panel. Read from `fixtures/zone-error-strings.json`'s new `settings_panel` top-level key.

**Keys** (Swedish text in fixture):

```json
{
  "settings_panel": {
    "gear_label": "Inställningar",
    "panel_title": "Inställningar",
    "close_label": "Stäng",
    "section_model_tier_title": "Modell",
    "section_appearance_title": "Utseende",
    "section_about_title": "Om JuraDrop",
    "tier_snabb_label": "Snabb",
    "tier_smart_label": "Smart",
    "tier_stor_label": "Stor",
    "tier_snabb_helper": "Snabbast och minst. Bra för korta texter.",
    "tier_smart_helper": "Standardvalet. Bra balans mellan fart och kvalitet.",
    "tier_stor_helper": "Bästa kvaliteten. Tar längre tid och mer plats på disken.",
    "tier_snabb_size": "~1.3 GB",
    "tier_smart_size": "~3.3 GB",
    "tier_stor_size": "~8.1 GB",
    "tier_ladda_ned_button": "Ladda ned",
    "tier_not_downloaded_badge": "Inte nedladdad",
    "appearance_light": "Ljust läge (följer systemet)",
    "appearance_dark": "Mörkt läge (följer systemet)",
    "about_app_name": "JuraDrop",
    "about_license": "Öppen källkod, MIT-licens",
    "about_github_button": "Visa utgåvor på GitHub"
  }
}
```

**Drift test** (`src/__tests__/settings-strings-drift.test.ts`): asserts every key in `SETTINGS_PANEL_STRINGS` (TypeScript) matches the fixture, AND every key in `SettingsPanelStrings` (Rust, exposed via a build-time generated TS fixture or via a Tauri command) matches.

## Relationships

```text
  ┌───────────────────────┐
  │  SettingsFile (JSON)  │
  └──────────┬────────────┘
             │ load_or_default()    save()
             ▼                ▲
  ┌───────────────────────┐  │
  │  SettingsSnapshot     │──┘
  │  (Rust + TS mirror)   │
  └──────────┬────────────┘
             │ read at every dispatch
             ▼
  ┌───────────────────────┐         ┌───────────────────────┐
  │  sidecar::commands::  │         │  TierMapping           │
  │  dispatch_to_zone()   │────────▶│  (model_id lookup)     │
  └──────────┬────────────┘         └───────────────────────┘
             │ HTTP POST
             ▼
  ┌───────────────────────┐
  │  Ollama @ 127.0.0.1   │
  │  with chosen model_id │
  └───────────────────────┘
```

```text
  ┌─────────────────────────┐
  │  PanelVisibility (TS)   │
  │  closed/opening/open/   │
  │  closing                │
  └──────────┬──────────────┘
             │ rendering gate
             ▼
  ┌─────────────────────────┐    fetch     ┌─────────────────────┐
  │  ModelTierSection       │─────────────▶│  get_tier_pull_state │
  │  per-row mode lookup    │              │  (Rust command)      │
  └──────────┬──────────────┘              └─────────────────────┘
             │
             ▼
  ┌─────────────────────────┐
  │  TierRowMode per tier   │
  │  radio_selectable OR    │
  │  download_button        │
  └─────────────────────────┘
```

## State transitions covered by tests

| State machine        | Tests                                                                                   |
|----------------------|-----------------------------------------------------------------------------------------|
| `PanelVisibility`    | `useSettingsPanel.test.tsx` — 4 states × 6 transitions × repeated-open coalescing       |
| `SchemaVersion` load | `settings_file_io.rs` — V1 round-trip + V2-stub forward-compat triggers default fallback |
| `TierRowMode`        | `ModelTierSection.test.tsx` — radio mode vs Ladda-ned mode per pull-state               |
| `Snapshot → File`    | `settings_file_io.rs` — atomic rename, malformed file, missing file                     |

## Constraints summary

- Zero new outbound HTTP from any data-model touchpoint.
- Settings file is byte-bounded (~50 bytes); the schema cannot grow without bumping `SchemaVersion`.
- All user-facing strings flow through the drift fixture — no inline string literals in components.
- Model ID literals appear in exactly one Rust file (`tier_map.rs`); a grep test enforces this.
