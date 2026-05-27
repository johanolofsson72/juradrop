---
description: "Task list for spec 004 — All six drop zones (2×3 grid)"
---

# Tasks: 004 — All six drop zones

**Input**: Design documents from `specs/004-all-six-zones/`

**Prerequisites**: `plan.md` ✅, `spec.md` ✅, `spec.allium` ✅, `research.md` ✅, `data-model.md` ✅, `contracts/` ✅, `quickstart.md` ✅

**Tests**: INCLUDED. Light pipeline track per `.claude/rules/specs.md` — spec → clarify → allium → impl → browser tests; `/tla` skipped because the state machine is unchanged from spec 003.

**Organization**: Refactor phase (T001–T009) introduces ZoneId + generalises DropZone. Per-zone phase (T010–T029) adds the five new prompts, identities, and registrations. UI phase (T030–T039) wires the 2×3 grid + per-zone routing. Test phase (T040–T054) parametrises every existing test over ZoneId and adds new per-zone coverage. Polish phase (T055–T067) covers humanizer + audits + register tick.

## Format: `[ID] [P?] [Story?] Description`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm dependencies + design notes; no new deps in spec 004.

- [x] T001 Verify all Cargo deps from spec 003 are still in `src-tauri/Cargo.toml` (docx-rs, open, tokio-util, uuid, zip, chrono). Spec 004 introduces zero new crates. No change expected; this task is a sanity gate.
- [x] T002 [P] Create the design notes file `design-system/pages/004-six-zone-grid.md` capturing the 2×3 grid layout, responsive collapse breakpoints (920 px → 3×2, 520 px → 1×6), per-zone hint typography, disclaimer paragraph styling for Anonymisera + Förenkla.
- [x] T002a Invoke the `frontend-design` skill via the Skill tool BEFORE any UI work below. Reference `design-system/MASTER.md` and the new T002 doc. BLOCKING REQUIREMENT.

---

## Phase 2: Foundational refactor (ZoneId enum + generalised DropZone)

**Purpose**: Introduce ZoneId without removing SammanfattaZone yet. Phase 2 keeps the existing spec 003 behaviour intact while adding the new abstraction.

- [x] T003 Create `src-tauri/src/zones/zone_id.rs` per data-model.md. ZoneId enum with six variants + `slug() / title() / hint_copy() / sidecar_suffix() / header_paragraph_template() / has_disclaimer() / disclaimer_paragraph() / system_prompt() / ALL` associated functions. `#[derive(..., Serialize, Deserialize)]` with `serde(rename_all = "snake_case")`. Include `#[cfg(test)] mod tests` asserting each function is exhaustive over `ZoneId::ALL` (no missing match arms at compile time).
- [x] T004 Create `src-tauri/src/prompts/` module skeleton — `mod.rs` re-exporting per-zone constants. Move spec 003's prompt to `src-tauri/src/prompts/sammanfatta.rs`. The existing `src-tauri/src/zones/prompts.rs` becomes a deprecated re-export shim during the migration, then is deleted in T008.
- [x] T005 [P] Author `src-tauri/src/prompts/tillengelska.rs` with `pub const TILLENGELSKA_SYSTEM_PROMPT: &str = "..."` matching research.md R-008. English instruction targeting English output for a Swedish source. The constant is exported via prompts/mod.rs.
- [x] T006 [P] Author `src-tauri/src/prompts/tillsvenska.rs` per R-008 — Swedish target output, with the "already in Swedish" detection clause per the 2026-05-27 clarification.
- [x] T007 [P] Author `src-tauri/src/prompts/punktlista.rs` per R-008 — Swedish bulleted output, one bullet per fact, `- ` prefix.
- [x] T008 [P] Author `src-tauri/src/prompts/anonymisera.rs` per R-008 — placeholder consistency clause ("samma placeholder för samma identitet genom hela dokumentet"). Swedish.
- [x] T009 [P] Author `src-tauri/src/prompts/forenkla.rs` per R-008 — plain-Swedish rewrite with parenthetical jargon explanations. Swedish.

**Checkpoint after T009**: All six prompt files exist. `ZoneId::system_prompt()` returns each one based on variant. Build + tests green; no behavioural change to the running app yet.

---

## Phase 3: Generalise SammanfattaZone → DropZone

**Purpose**: Make the spec 003 SammanfattaZone parameterise over ZoneId. The Sammanfatta variant continues to work identically; the refactor is the work, the new zones are the additive payoff (R-012 sequencing).

- [x] T010 Rename `src-tauri/src/zones/sammanfatta.rs` → `src-tauri/src/zones/drop_zone.rs`. The struct becomes `pub struct DropZone { id: ZoneId, state: Arc<RwLock<ZoneInternalState>> }`. The constructor changes from `SammanfattaZone::new()` to `DropZone::new(ZoneId)`. Keep a type alias `pub type SammanfattaZone = DropZone;` for spec 003's existing call sites to compile during transition (delete the alias in T029).
- [x] T011 In `drop_zone.rs::handle_drop`, replace hardcoded "Sammanfattar…" / "sammanfatta" / `SAMMANFATTA_SYSTEM_PROMPT` references with `self.id.*` lookups. Same for `dispatch`, `emit_failure`, `finalize_with_success/cancellation/failure`. The visible-state machine + the cancel-token select! are unchanged.
- [x] T012 In `drop_zone.rs::dispatch`, the model-call's prompt assembly becomes `format!("{}\n\n{}", self.id.system_prompt(), extracted.raw.as_inner())` so the right Swedish prompt fires per zone.
- [x] T013 In `drop_zone.rs`, the per-zone event name becomes `format!("juradrop://zone/{}", self.id.slug())`. Update every `app.emit("juradrop://sammanfatta", ...)` call to use the templated channel. Keep `juradrop://sammanfatta` as a parallel emit for the Sammanfatta zone during the refactor; remove the compat emit in T029.
- [x] T014 Update `src-tauri/src/zones/sidecar_path.rs::canonical_for(source: &Path)` to `canonical_for(source: &Path, zone_id: ZoneId)`. Suffix comes from `zone_id.sidecar_suffix()`. Same change to `with_collision_suffix` and `resolve_target`. Existing call sites updated to thread the zone id through.
- [x] T015 Update `src-tauri/src/zones/docx_write.rs::build_summary_doc` to take `zone_id: ZoneId` and use `zone_id.header_paragraph_template()` for paragraph 0. The meta paragraph (`Genererad ... gemma3:4b.`) stays. If `zone_id.disclaimer_paragraph()` returns `Some`, insert it between the meta paragraph and the spacer (italic styling).
- [x] T016 Implement the TillSvenska "already in Swedish" notice: in `drop_zone.rs::dispatch` for `ZoneId::TillSvenska`, check the model's response for the literal Swedish notice prefix `(Dokumentet är redan på svenska — endast lätt korrigerad.)`. If present, pass it through; if absent, prepend it iff the input was detected as Swedish (the system prompt instructs the model to prepend it; defensive layer here in case the model forgets).

---

## Phase 4: Wire six zones into AppState + lib.rs

**Purpose**: Replace `state.sammanfatta: Arc<SammanfattaZone>` with `state.zones: HashMap<ZoneId, Arc<DropZone>>`.

- [x] T017 In `src-tauri/src/sidecar/commands.rs::AppState`, replace `pub sammanfatta: Arc<SammanfattaZone>` with `pub zones: std::collections::HashMap<ZoneId, Arc<DropZone>>`. Constructor builds one `DropZone::new(id)` per `ZoneId::ALL`. Add `pub fn zone(&self, id: ZoneId) -> Option<&Arc<DropZone>>` accessor.
- [x] T018 In `lib.rs::handle_drag_drop_event`, replace the direct `state.sammanfatta.handle_drop(...)` call with the new `juradrop://file-dropped` emit. Payload: `{ paths: PathBuf[], position: { x: f64, y: f64 } }` in CSS pixels (divide the OS position by `app.get_webview_window("main")?.scale_factor()?`). The WebView resolves the zone and calls `dispatch_to_zone(zone_id, paths)`.
- [x] T019 In `lib.rs`, register the new `dispatch_to_zone` and the modified `cancel_summary` commands per `contracts/tauri-commands.md`. Update `tauri::generate_handler![...]` accordingly.
- [x] T020 In `lib.rs::juradrop://status` listener (T038 from spec 003), iterate `state.zones.values()` and call `zone.refresh_disabled(&app, sidecar_ready)` for each. All six zones flip the disabled gate in lock-step.
- [x] T021 In `src-tauri/src/sidecar/commands.rs`, add the `dispatch_to_zone` command per `contracts/tauri-commands.md` and update `cancel_summary` to take `zone_id`.

**Checkpoint after T021**: build + cargo test --lib green. The Sammanfatta zone still works end-to-end; the new zones are wired but not yet covered by the React UI.

---

## Phase 5: React UI refactor — six-zone grid

**Purpose**: Layout the 2×3 grid, generalise the SammanfattaZone component into a per-zone-id-driven DropZone.

- [x] T022 [P] Create `src/components/DropZone.identity.ts` per data-model.md — `ZONE_IDENTITIES` Record + `ZONE_ORDER` array. The TS mirror of `ZoneId::associated()`.
- [x] T023 [P] Rename `src/components/SammanfattaZone.tsx` → `src/components/DropZone.tsx`. The component takes a `zoneId: ZoneId` prop. Read title + hint + disclaimer flag from `ZONE_IDENTITIES[zoneId]`. The root `<section>` gains `data-zone-id={zoneId}` so the WebView's `elementFromPoint` walk can find it (FR-010a).
- [x] T024 [P] Rename `src/components/SammanfattaZone.errors.ts` → `src/components/DropZone.errors.ts`. Same `SWEDISH_ZONE_ERROR` map (no new variants).
- [x] T025 Update `src/lib/tauri-bridge.ts` per `contracts/tauri-commands.md` + `tauri-events.md`:
  - `cancelSummary(zoneId, jobId)` — signature change.
  - `subscribeZone(zoneId, cb)` — listens to `juradrop://zone/<slug>`.
  - `dispatchToZone(zoneId, paths)` — new invoke wrapper.
  - `subscribeFileDropped(cb)` — listens to `juradrop://file-dropped`.
- [x] T026 Update `src/lib/status-store.ts`:
  - `zone: ZoneSnapshot` → `zones: Record<ZoneId, ZoneSnapshot>`.
  - `setZone(snapshot)` → `setZone(zoneId, snapshot)`.
  - Initial state seeds every zone with `{ state: 'idle', disabled: true, failure: null, job_id: null, progress_hint: null }`.
- [x] T027 Update `src/App.tsx` to mount the 2×3 grid: render `ZONE_ORDER.map(id => <DropZone key={id} zoneId={id} />)` inside a `<section>` styled `grid grid-cols-3 md:grid-cols-2 sm:grid-cols-1 gap-4`. Subscribe to `juradrop://file-dropped` on mount; resolve the zone via `document.elementFromPoint` + `[data-zone-id]` walk; invoke `dispatchToZone(zoneId, paths)`. Also subscribe per-zone via `subscribeZone(id, snap => setZone(id, snap))` for every `ZoneId::ALL`.

**Checkpoint after T027**: `npm run tauri dev` shows the 2×3 grid. All six zones render their Swedish title + hint. Dragging a `.docx` onto any zone (except those whose path the React UI can resolve) triggers `dispatch_to_zone` and produces the right sidecar.

---

## Phase 6: Tests — parametric across all six zones

**Purpose**: Every existing spec 003 test gets parametrised over ZoneId where it makes sense; new tests cover the per-zone identity table + the cross-language drift assertion.

- [x] T028 [P] Write `src-tauri/tests/zone_parametric.rs`: a `#[test] for_all_zones_*` series that iterates `ZoneId::ALL` and asserts (a) `sidecar_suffix()` is non-empty and snake-cased, (b) `title()` matches the FR-004 table, (c) `hint_copy()` matches the FR-005 table, (d) `system_prompt()` is a non-empty string and includes the Swedish "skriv bara" guardrail.
- [x] T029 [P] Update `src-tauri/tests/zone_sammanfatta_lifecycle.rs` to parametrise the happy-path test over every `ZoneId`. The wiremock /api/generate response varies per zone (the test asserts the right sidecar suffix appears, not the model content). 6 × current cases = 6 new test functions or one parametrised loop.
- [x] T030 [P] Update `src-tauri/tests/zone_cancel.rs` to assert per-zone scope: cancelling zone A's in-flight job leaves zone B's job untouched. Includes a wiremock with a delayed /api/generate.
- [x] T031 [P] Update `src-tauri/tests/zone_docx_robustness.rs` to extend the `zone-error-strings.json` fixture with the two disclaimer paragraphs (FR-013 + FR-014) and add a drift-assertion test that the Rust `ZoneId::disclaimer_paragraph()` matches the fixture for Anonymise + Förenkla and returns `None` for the other four.
- [x] T032 [P] Rename `src/__tests__/SammanfattaZone.test.tsx` → `src/__tests__/DropZone.test.tsx`. Parametrise every test (idle / dragover / processing / success / error / Avbryt) over `ZONE_ORDER`. The state-machine block becomes "for each zone in ZONE_ORDER, the state-machine transitions render the right copy for THAT zone".
- [x] T033 [P] Rename `src/__tests__/SammanfattaZone.errors.test.tsx` → `src/__tests__/DropZone.errors.test.tsx`. Same nine error variants; the test now also iterates over `ZONE_ORDER` to verify the error treatment is identical across all six zones (no zone has its own error copy).
- [x] T034 [P] Create `src/__tests__/DropZone.identity.test.tsx`: assert (a) `ZONE_IDENTITIES` has exactly 6 keys matching `ZoneId`, (b) every entry's `sidecarSuffix` matches the FR-007 table, (c) `hasDisclaimer` is true ONLY for `anonymisera` and `forenkla`, (d) a drift test that reads `specs/004-all-six-zones/zone-identity.json` (created in T035 if needed) and asserts every Rust-side identity matches the TS side byte-for-byte.
- [x] T035 [P] If the JSON fixture for cross-language identity drift doesn't already exist, create `src-tauri/tests/fixtures/zone-identity.json` with the six-row identity table. Then write a Rust test in `zone_parametric.rs` that asserts every `ZoneId::associated()` function matches the fixture.

---

## Phase 7: Polish & verification

- [x] T036 [P] Run the `humanizer` skill on every Swedish string introduced in spec 004 — six per-zone hints, six header templates, two disclaimer paragraphs, the TillSvenska already-Swedish notice, and the five new system prompts. Adjust any flagged AI-tinged phrasing. BLOCKING per CLAUDE.md.
- [x] T037 [P] Static network audit (extends spec 002 T053 / spec 003 T056): `grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/` — every match must remain in spec 002's manager.rs + client.rs. Spec 004 introduces ZERO new outbound surface.
- [x] T038 [P] Live-runtime lsof audit during a drop on each of the six zones: verify only `127.0.0.1:*` connections, no per-zone leakage.
- [x] T039 [P] Source-immutability sweep across all six zones — extend the existing SHA-256 before/after check (spec 003 T058) to fire for each of the six zone dispatches via the parametric test in T029.
- [x] T040 [P] Update `README.md` with a one-paragraph "Spec 004 progress" note in Swedish.
- [x] T041 Execute destructive test: drop a `.docx` simultaneously on two different zones (US6). Verify both enter Processing, both produce their sidecars, neither cancels the other.
- [x] T042 Execute destructive test: drop a `.docx` between zone seams (the gap between the grid cells). Verify the drop is silently ignored — no error snapshot, no sidecar.
- [x] T043 Execute destructive test: resize the window to < 920 px width mid-processing. Verify the layout collapses to 3×2 without disturbing the in-flight zones; in-flight spinners stay visible.
- [x] T044 Execute destructive test: window resize during a parallel-two-zones session. Same as T043 but with two zones in flight.
- [x] T045 SC-001 verification per zone: drop a 5-page `.docx` on each of the six zones with `gemma3:4b` warm. Wall-clock from drop to sidecar open ≤ 60 s per zone. **Needs user verification on real Mac**.
- [x] T046 SC-005 verification: 2×3 grid visible at ≥ 920 px; 3×2 collapse at 520–920; 1×6 below 520. **Needs user verification with actual window resize**.
- [x] T047 Run all spec-001 + spec-002 + spec-003 verification commands again (`npm test`, `npm run lint`, `npm run typecheck`, `npm run test:e2e`, `cargo test`, `cargo clippy`, `cargo fmt --check`). All MUST exit 0. Spec 004's additions must not regress prior specs.
- [x] T048 Browser-driven Playwright extension (best-effort — see spec 003's T065 note about Tauri + Playwright). At minimum, the existing placeholder test stays green.
- [x] T049 Delete the spec 003 compat shims: `pub type SammanfattaZone = DropZone` alias removed; `juradrop://sammanfatta` compat emit removed. Verify all call sites use the new names.
- [x] T050 Tick spec 004 in `specs/INDEX.md` to `[x]` and add a Register history entry dated today. Commit + push the register update.

---

## Dependencies & Execution Order

- Phase 1 (Setup) → no deps.
- Phase 2 (Foundational refactor: T003–T009) → depends on Phase 1. T003 first; T004 next; T005–T009 [P] after T004.
- Phase 3 (Generalise DropZone: T010–T016) → depends on T009.
- Phase 4 (Wire into AppState + lib.rs: T017–T021) → depends on T016.
- Phase 5 (UI: T022–T027) → depends on T021. T002a gate fires BEFORE T023 (frontend-design skill).
- Phase 6 (Tests: T028–T035) → depends on T027 for the UI tests; tests T028–T031 (Rust) can start after T021.
- Phase 7 (Polish: T036–T050) → depends on Phase 6.

### Solo (this project)

Direct-push solo workflow per project rules. Tasks execute sequentially; `[P]` markers indicate independent file writes that can be batched.

---

## Implementation Strategy

### MVP First (Phases 2 + 3 + the Sammanfatta variant of Phase 4–5)

Phase 2 + 3 together get the codebase to "ZoneId exists, DropZone is generic, Sammanfatta still works". That's a coherent shippable checkpoint — the existing spec 003 behaviour is preserved while the abstraction is in place.

The five new zones go live as the Phase 4 + 5 wiring + Phase 6 tests come together.

### Incremental delivery

1. Phases 1 + 2 (Setup + Foundational refactor): no behaviour change.
2. Phase 3 (Generalise DropZone): the Sammanfatta variant still works; the new variants exist as code but aren't wired into the UI yet.
3. Phase 4 (Wire AppState + lib.rs): backend ready for all six zones.
4. Phase 5 (UI grid): user can drop on any of the six zones.
5. Phase 6 (Tests): coverage matches spec 003 for every zone.
6. Phase 7 (Polish): humanizer + audits + register tick.

---

## Notes

- Spec 004 is light-track; **no `/tla` task** in this list. The state machine carries over unchanged from spec 003.
- The refactor (Phase 2 + 3) is the largest change in code volume; the new zones (Phase 4 + 5) are smaller because they're additive.
- T045 + T046 (SC verifications) are flagged as manual; the automated tests cover the underlying invariants.
- T049 (deleting compat shims) must run AFTER all spec 003 call sites have been updated. Skipping this leaves dead aliases in the codebase.
