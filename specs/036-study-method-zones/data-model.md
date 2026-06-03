# Data Model: Study-method drop zones

No new entity type or state machine — the three zones are instances of the existing `ZoneId` / drop-zone concept (spec 004/013). This file captures the concrete per-zone values that every touch-point must agree on (the cross-language drift surface).

## ZoneId additions

| Variant (Rust) | serde rename / slug | grid index | ALL position |
|---|---|---|---|
| `Identifiera` | `identifiera` | 9 | `ALL[9]` |
| `Strukturera` | `strukturera` | 10 | `ALL[10]` |
| `Forklara` | `forklara` | 11 | `ALL[11]` |

`ALL: [ZoneId; 9] → [ZoneId; 12]` (append in the above order). The `spec_013_has_exactly_nine_zones` test → twelve, with `ALL[9]==Identifiera`, `ALL[10]==Strukturera`, `ALL[11]==Forklara`.

## Per-zone method return values (the 8 exhaustive matches in zone_id.rs)

| method | identifiera | strukturera | forklara |
|---|---|---|---|
| `slug()` | `identifiera` | `strukturera` | `forklara` |
| `title()` | `Identifiera rättsfrågorna` | `Strukturera (IRAC)` | `Förklara begreppen` |
| `hint_copy()` | `Släpp …/.odt för att hitta rättsfrågorna` | `Släpp …/.odt för IRAC-struktur` | `Släpp …/.odt för begreppsförklaringar` |
| `processing_hint()` | `Letar rättsfrågor…` | `Strukturerar…` | `Förklarar begrepp…` |
| `sidecar_suffix()` | `rattsfragor` | `irac` | `begrepp` |
| `header_paragraph_template()` | `Rättsfrågor i '{name}'` | `IRAC-struktur av '{name}'` | `Begreppsförklaringar för '{name}'` |
| `system_prompt()` | `IDENTIFIERA_SYSTEM_PROMPT` | `STRUKTURERA_SYSTEM_PROMPT` | `FORKLARA_SYSTEM_PROMPT` |
| `disclaimer_paragraph()` | `Some("AI:n kan missa …")` | `Some("AI:n kan placera …")` | `Some("AI:n kan förenkla …")` |

(Final Swedish strings come from research.md R-003 after the humanizer pass.)

## Behavioural classification (no code change needed)

| aspect | value | mechanism |
|---|---|---|
| prompt framing | DATA (delimiters + anti-injection guard) | falls through `framing.rs` `_` arm — NO new arm |
| output format | mirror input | falls through `output_format.rs::for_zone` `_` arm — NO new arm |
| state machine | existing per-zone idle→processing→success/error | unchanged — reused verbatim |

## Help strings (`ZONE_HELP_STRINGS [;9] → [;12]`, canonical ALL order)

| zone | short (≤80) | long (≤300) |
|---|---|---|
| identifiera | `Listar de juridiska frågorna som texten väcker.` | (research.md R-003) |
| strukturera | `Strukturerar om ett svar enligt IRAC-modellen.` | (research.md R-003) |
| forklara | `Förklarar de juridiska begreppen i klartext.` | (research.md R-003) |

## TS mirror (`DropZone.identity.ts`)

`ZONE_IDENTITIES` gains 3 keys (`identifiera`/`strukturera`/`forklara`) with `{ slug, title, hintCopy, sidecarSuffix, processingHint, hasDisclaimer: true }` matching the Rust values exactly. `ZONE_ORDER` appends the 3 slugs (indices 9/10/11). The drift tests enforce equality with the Rust source + JSON fixtures.

## JSON fixtures

- `zone-identity.json`: +3 objects (`slug`/`title`/`hint_copy`/`sidecar_suffix`/`processing_hint`/`has_disclaimer: true`), `_comment` 9→12.
- `zone-help-strings.json`: +3 objects (`short`/`long`), `_comment` 9→12.

## Invariants (from spec.allium, enforced by tests)

- `TwelveZones`: `ZoneId::ALL.len() == 12` (Rust test) + `ZONE_ORDER.length === 12` (TS test).
- `ZoneIdentityDriftFree`: Rust ↔ JSON ↔ TS slugs/titles/hints/help all agree (existing drift tests, parameterised).
- `NewZonesAreTransform` / `NewZonesAreDataFramed`: verified structurally (no new `for_zone`/`frame_prompt` arm) + by the pipeline tests producing mirrored-format sidecars.
- `NewZonesForbidFabricatedCitations`: each system prompt contains the anti-fabrication clause (unit-assertable on the prompt const) + the pipeline test asserts citation-free output (SC-002).
- `NewZonesHaveDisclaimer`: `disclaimer_paragraph()` returns `Some` for all three (assertable via `has_disclaimer()`).
