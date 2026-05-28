# Phase 1 Data Model — Spec 013

Mirrors `spec.allium`. Rust is the source of truth; TS + JSON fixtures mirror it.

## ZoneId (enum) — DONE phase 1

Nine variants in canonical grid order. Variant order = grid position.

| # | Variant | slug / serde | title (sv) | sidecar suffix | disclaimer |
|---|---|---|---|---|---|
| 0 | `Sammanfatta` | `sammanfatta` | Sammanfatta | `.sammanfatta` | no |
| 1 | `TillEngelska` | `tillengelska` | Till engelska | `.tillengelska` | no |
| 2 | `TillSvenska` | `tillsvenska` | Till svenska | `.tillsvenska` | no |
| 3 | `Punktlista` | `punktlista` | Punktlista | `.punktlista` | no |
| 4 | `Anonymisera` | `anonymisera` | Anonymisera | `.anonymiserad` ⚠️ | **yes** |
| 5 | `Forenkla` | `forenkla` | Förenkla | `.forenkla` | **yes** |
| 6 | `Kontakter` | `kontakter` | Plocka ut kontaktuppgifter | `.kontakter` | no |
| 7 | `Generera` | `generera` | Generera juridisk text | `.generera` | **yes** |
| 8 | `Kallor` | `kallor` | Källförteckning | `.kallor` | no |

⚠️ **Anonymisera's sidecar suffix is `anonymiserad`** (past participle, reads better as a filename) — NOT the slug `anonymisera`. The suffix is its own field, ASCII + unique per zone, but does not equal the slug for this one zone.

**Invariant `DisclaimerZonesPinned`**: disclaimer carriers = exactly {anonymisera, forenkla, generera}.
**Invariant `ExactlyNineZones`**: `ZoneId::ALL.len() == 9`.

## ZoneHelp (value) — NEW phase 2

Two Swedish strings per zone. Char-budgeted. Mirrored Rust ↔ TS ↔ JSON.

| Field | Type | Constraint |
|---|---|---|
| `short` | String | `1..=80` chars; popover body |
| `long` | String | `1..=300` chars; HelpPanel body (2–3 sentences) |

Source of truth: `src-tauri/src/help/zone_help.rs` `ZONE_HELP_STRINGS: [(ZoneId,&str,&str); 9]`.
TS mirror: `src/lib/help-strings.ts`.
Drift fixture: `src-tauri/tests/fixtures/zone-help-strings.json` — `{ "<slug>": { "short": "...", "long": "..." } }`.

## HelpPanel visibility (state machine) — NEW phase 2

Clone of spec 010 `PanelVisibility`. 4 states, 6 transitions.

```
closed → opening   (chrome (?) click, when enabled)
opening → open     (animation completes, 220ms)
open → closing     (Esc / X / scrim / outside-click)
closing → closed   (animation completes, 180ms)
opening → closing  (Esc mid-animation)
closing → opening  (repeated open intent during slide-out)
```

**Coalescing invariant**: at most one HelpPanel instance open (same as settings).
**Mutual-exclusion invariant `AtMostOneSlideInPanel`**: `!(HelpPanel.open && SettingsPanel.open)`. Enforced in `App.tsx`: open-help closes settings; open-settings closes help.
**Modal-gate (FR-022)**: chrome `(?)` disabled when `wizardUp || restartUp` (identical predicate to `gearIconEnabled`).

## ZonePopover (per-zone) — NEW phase 2

Boolean open/closed per zone card. Independent per card. No mutual exclusion between popovers (clicking one card's `(?)` while another's is open is allowed; each dismisses on its own Esc/outside/re-click). `role="tooltip"`, `aria-label="Hjälp om <title>"`.

## ZoneDispatch (pipeline) — existing, unchanged

State machine from spec 003 (`idle → processing → success|error → idle`). Spec 013 adds 3 new zones routed through the same `DropZone::handle_drop`. Invariants preserved:
- `SourceImmutable` — source SHA-256 unchanged across dispatch (success AND error paths).
- `SidecarSuffixMatchesZone` — on success, sidecar path contains the zone's suffix.

## Test-only entities

- **`CANONICAL_EXTRACTION_PROBE_TEXT`** (`&'static str`) — ~200-char Swedish paragraph with `å ä ö`, byte-pinned in `extraction_probe.rs`.
- **`MockOllamaServer`** = `wiremock::MockServer` bound to `127.0.0.1:0`, deterministic `/api/generate` response per zone.
- **`FixtureDocument`** — committed file under `tests/fixtures/`; `contains_personal_data` ones carry `[TESTDATA — fiktiva uppgifter]`.
- **`IntegrationTest`** — `#[ignore]`'d ones must carry a `// HARDWARE:` reason comment (`IgnoredTestsJustified`).

## Config constants

| Name | Value |
|---|---|
| `zone_count` | 9 |
| `constitution_version` | "1.1.0" |
| `default_ollama_url` | `http://127.0.0.1:11434` |
| `ollama_url_env_var` | `JURADROP_OLLAMA_URL` (debug-only) |
| `extraction_probe_formats` | {docx, pdf, txt, md, rtf, odt} (NOT pages) |
| `truncation_cap_chars` | 24000 (spec 005, unchanged) |
