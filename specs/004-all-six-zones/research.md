# Research: All six drop zones

**Phase 0 output** for spec 004's `/speckit-plan`. Each decision below resolves a candidate "NEEDS CLARIFICATION" from the plan's Technical Context section into a concrete pick with rationale.

## R-001: ZoneId discriminator shape

**Decision**: Plain Rust enum with six unit variants — `Sammanfatta`, `TillEngelska`, `TillSvenska`, `Punktlista`, `Anonymisera`, `Forenkla`. `#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]` with `serde(rename_all = "snake_case")`. Associated functions on the enum (`slug()`, `title()`, `hint_copy()`, `sidecar_suffix()`, `header_paragraph_template()`, `system_prompt()`, `has_disclaimer()`) instead of a parallel struct, so `match` exhaustiveness catches a missing handler at compile time.

**Rationale**: Compile-time exhaustiveness is the dominant safety property. A struct would let a future PR add a seventh variant without forcing six call sites to update; an enum-with-match makes every call site light up red until handled. Matches spec 003's `ZoneFailure` pattern exactly.

**Alternatives considered**:
- `HashMap<ZoneId, ZoneIdentity>` lookup: lookups can fail at runtime; loses exhaustiveness checking.
- Trait-object dispatch (`Box<dyn Zone>`): heavyweight for six fixed variants; harder to serialise across the Tauri boundary.

## R-002: Drop-position → zone routing

**Decision**: Rust handler emits `juradrop://file-dropped` with `{ paths: PathBuf[], position: { x: f64, y: f64 } }` in **CSS pixels** (divide physical position by the window's `scale_factor`). The WebView subscribes, calls `document.elementFromPoint(x, y)`, walks up to the nearest `[data-zone-id]` ancestor, and invokes `dispatch_to_zone(zone_id, paths)`. Drops outside any zone are silently ignored.

**Rationale**: The OS-level `WindowEvent::DragDrop` carries one `PhysicalPosition<f64>` per event. Mapping that to a React component is naturally a DOM-side concern (we don't want Rust to know about layout). `elementFromPoint` is a standard DOM API; the data flow keeps paths in the Rust event payload (no HTML5 drag-drop blob), preserving the privacy boundary.

**Alternatives considered**:
- Tracking zone bounding rects in Rust: requires React to push layout coordinates to Rust on every resize. Brittle and chatty.
- HTML5 drag-and-drop in the WebView: doesn't expose the OS file path on macOS (sandboxed blob). Already rejected in spec 003 R-006.
- Two-step modal "which zone?": user-hostile.

## R-003: Per-zone event channel naming

**Decision**: `juradrop://zone/<slug>` — e.g. `juradrop://zone/sammanfatta`, `juradrop://zone/tillengelska`. The React layer subscribes per-zone (one `listen()` call per slug at component mount). The payload shape (`ZoneSnapshot`) is unchanged from spec 003.

**Rationale**: Per-channel subscription means each zone's React component only re-renders on its own snapshots. Cleaner than one shared channel with a `zone_id` discriminator that every subscriber has to filter on.

**Alternatives considered**:
- Single channel `juradrop://zone` with `zone_id` in payload: every zone listens, filters by id, wastes re-renders.
- Channel per (zone_id, event_kind): too granular; the snapshot payload is the natural unit.

## R-004: Shared OllamaClient + Ollama queue

**Decision**: All six zones share the existing `Arc<OllamaClient>` held in `AppState`. When two zones dispatch concurrently, Ollama's own HTTP request queue serialises the actual inference (Ollama serves one /api/generate at a time per model). The UI shows both zones in Processing; the second's spinner just runs longer.

**Rationale**: `gemma3:4b` runs one inference at a time on the M-series GPU regardless. Trying to make the zones "really parallel" would only mean queueing in our code instead of in Ollama — same observable outcome, more code. The user sees honest UI state (both in Processing); the actual sequencing is transparent.

**Alternatives considered**:
- Six `OllamaClient` instances: same effect, more allocation.
- App-side priority queue: premature optimisation. Spec 011 (error-recovery) can revisit.

## R-005: ZoneIdentity discoverability across Rust ↔ TS

**Decision**: Rust is the source of truth. The Rust `ZoneId::associated()` functions emit a JSON fixture at test time (or at build time via `build.rs` if we want compile-time guarantees) into `specs/004-all-six-zones/zone-identity.json`. The TS `DropZone.identity.ts` is hand-authored from the same fixture, with a vitest test that reads the JSON and asserts the TS table matches byte-for-byte — same drift pattern as spec 003 T048.

**Rationale**: Spec 003's `zone-error-strings.json` proved the pattern works. Six small string tables aren't worth a code-gen pipeline; explicit fixture + drift test is the right shape.

**Alternatives considered**:
- TypeScript generation via `wasm-bindgen` / `ts-rs`: too much machinery for six strings.
- Hand-author both sides without a fixture: invites drift.

## R-006: 2×3 grid layout via CSS grid

**Decision**: CSS `display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); grid-template-rows: repeat(2, 1fr); gap: 1rem;`. On viewports < 920 px wide, collapse via `@media` to `grid-template-columns: repeat(2, minmax(0, 1fr)); grid-template-rows: repeat(3, 1fr);`. On viewports < 520 px, collapse to single column.

**Rationale**: Native CSS grid handles all three breakpoints declaratively. No JS, no resize listener. Tailwind v3 supports the breakpoints via responsive utilities (`grid-cols-3 md:grid-cols-2 sm:grid-cols-1` ordering reversed if needed).

**Alternatives considered**:
- Flexbox row-wrap: works but `gap` + alignment is fiddlier.
- A `<table>`-based grid: semantically wrong (zones aren't tabular data) and breaks ARIA.

## R-007: Per-zone single-flight enforcement

**Decision**: Each `DropZone` instance owns its own `Arc<RwLock<Option<DropJob>>>` (one slot per instance). The drop handler checks ONLY its own zone's slot — a zone-A drop sees only zone A's current_job, never zone B's. No global mutex; no cross-zone communication.

**Rationale**: Mirrors the spec 003 design exactly, just multiplied. Per-zone state isolation is the whole point of US6.

**Alternatives considered**:
- Global `HashMap<ZoneId, DropJob>` in `AppState`: same effect; more contention on the map lock.
- Per-zone tokio task: spawns a long-lived task per zone for no behavioural gain.

## R-008: Per-zone Swedish prompts — content + structure

**Decision**: Six `pub const <SLUG>_SYSTEM_PROMPT: &str` constants, one per zone, each in its own `src-tauri/src/prompts/<slug>.rs` file. Each prompt follows the spec 003 R-010 shape — Swedish system instruction, "no greeting, no meta-commentary" guardrail, "skriv bara själva [sammanfattningen | översättningen | listan | …]" closer.

Initial prompt drafts (to be reviewed via the `humanizer` skill in Phase 8):

- **sammanfatta** (existing): `Du är en svensk juriststudent som hjälper en annan student. Skriv en saklig, koncis sammanfattning på svenska av följande dokument. …`
- **tillengelska**: `You are translating a Swedish legal document into careful English for a non-Swedish-speaking law student. Preserve the structure (parties, holding, reasoning). Translate Swedish legal terms with the closest English equivalent and include the Swedish original in parentheses on first use. Output English text only — no commentary.`
- **tillsvenska**: `Du översätter ett dokument till svenska för en svensk juriststudent. Bevara dokumentets struktur. Om dokumentet redan är på svenska, gör en lätt språklig städning och lägg till noteringen "(Dokumentet är redan på svenska — endast lätt korrigerad.)" först. Skriv bara översättningen.`
- **punktlista**: `Du är en svensk juriststudent. Strukturera följande dokument som en svensk punktlista. En punkt per faktum eller juridisk poäng. Inga inledande meningar — bara punkterna. Använd "- " som punktmarkör.`
- **anonymisera**: `Du anonymiserar ett svenskt juridiskt dokument. Ersätt varje personnamn med "Person A", "Person B", och så vidare i förekomstordning. Ersätt varje organisation med "Företag X", "Företag Y", och så vidare. Ersätt varje adress med "Adress 1", "Adress 2". Ersätt varje personnummer med "ÅÅÅÅÅÅ-XXXX". Behåll samma placeholder för samma identitet genom hela dokumentet. Bevara meningsstrukturen i övrigt. Skriv bara den anonymiserade texten.`
- **forenkla**: `Du skriver om ett juridiskt dokument på klarspråk för en icke-jurist. Bevara varje juridisk poäng men använd kortare meningar och förklara svenska juridiska termer parentetiskt (t.ex. "preskription (rätten att kräva har gått ut)"). Skriv bara den förenklade versionen.`

**Rationale**: One prompt per file gives each prompt its own commit history. The text is documented here so the planning phase is reviewable; the `humanizer` skill will re-check naturalness in Phase 8.

**Alternatives considered**:
- A single `prompts.rs` with all six constants: muddier git blame.
- External prompt files (.txt): adds a runtime read step; doesn't earn its complexity.

## R-009: Per-zone header template (FR-009)

**Decision**: Header paragraph 0 per zone — paragraph 1 (timestamp + model label) is unchanged from spec 003 FR-005a:

| ZoneId | Header paragraph 0 |
|---|---|
| Sammanfatta | `Sammanfattning av '<filename>'` |
| TillEngelska | `Översättning till engelska av '<filename>'` |
| TillSvenska | `Översättning till svenska av '<filename>'` |
| Punktlista | `Punktlista över '<filename>'` |
| Anonymisera | `Anonymiserad version av '<filename>'` |
| Förenkla | `Förenklad version av '<filename>'` |

**Rationale**: Each header is a natural Swedish phrase for the action; the surrounding metadata stays consistent.

## R-010: Disclaimer paragraph placement (FR-013 + FR-014)

**Decision**: For Anonymise and Förenkla only, insert the disclaimer paragraph BETWEEN the FR-005a header pair and the blank-line separator (so the structure becomes: header_filename → header_meta → disclaimer → blank → body_paragraphs). The disclaimer is italicised in the `.docx` (Word "italic" run formatting); the disclaimer counts as a body paragraph from the test's POV (`body_paragraph_count >= 1` already accommodates it).

**Rationale**: The disclaimer must be visible immediately when the user opens the file, before the body content. Placing it after the header pair gives it visual weight without competing with the title.

**Alternatives considered**:
- Disclaimer as a separate `.docx` footer: hidden until print preview; defeats the "visible immediately" goal.
- Disclaimer as a Word comment: requires Word; not portable to Pages / LibreOffice.

## R-011: Sidecar suffix table

| ZoneId | Sidecar suffix | Canonical filename example |
|---|---|---|
| Sammanfatta | `sammanfatta` | `dom.sammanfatta.docx` |
| TillEngelska | `tillengelska` | `dom.tillengelska.docx` |
| TillSvenska | `tillsvenska` | `dom.tillsvenska.docx` |
| Punktlista | `punktlista` | `dom.punktlista.docx` |
| Anonymisera | `anonymiserad` | `dom.anonymiserad.docx` (past-participle adjective — reads better than the verb stem) |
| Förenkla | `forenkla` | `dom.forenkla.docx` |

**Rationale**: Suffixes are short, lowercase, Swedish, and unambiguous in a filesystem context. "Anonymiserad" is the past-participle form because the file is the result of an anonymisation action, not the verb itself — that matches Swedish convention for derived filenames.

**Alternatives considered**:
- All suffixes as verbs (`anonymisera`, `forenkla`): grammatically off for Swedish noun-form filenames.
- English suffixes (`anonymized`, `simplified`): violates Principle V's filesystem-visible-strings-in-Swedish clause.

## R-012: Refactor sequencing

**Decision**: Three-phase refactor inside Phase 3 (implementation):
1. Introduce the `ZoneId` enum + `ZoneIdentity` associated functions alongside the existing `SammanfattaZone`. Build green at this point.
2. Generalise `SammanfattaZone` → `DropZone` by parameterising over `ZoneId`. The `Sammanfatta` variant continues to work identically.
3. Add the five new prompt modules + register five new `DropZone` instances. Layout the 2×3 grid in `App.tsx`.

**Rationale**: Each phase compiles + tests green before the next starts. No "big bang" refactor; the refactor is the work, the new zones are the additive payoff.

**Alternatives considered**:
- All-at-once rewrite: harder to bisect when it breaks.
- Parallel implementation (new `DropZone` next to old `SammanfattaZone` until everything migrates): two code paths during refactor invite drift.
