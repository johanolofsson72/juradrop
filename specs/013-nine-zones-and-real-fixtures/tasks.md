# Tasks: Nine zones + real-document fixtures + integration tests (Spec 013)

**Feature dir**: `specs/013-nine-zones-and-real-fixtures/`
**Track**: Full pipeline. `.allium` baseline established; `/tla` required.
**Inputs**: plan.md, spec.md, data-model.md, contracts/{help-system,zone-pipeline,test-seam}.md, research.md, quickstart.md.

Legend: `[P]` = parallelizable (different files, no incomplete dep). `[US1/2/3]` = user-story label.

---

## Phase 1: Zones data + type layer — ✅ DONE (commit 0f3381b)

- [x] T001 Expand `ZoneId` enum to 9 variants (Kontakter, Generera, Kallor) in `src-tauri/src/zones/zone_id.rs` + all per-variant match arms + `ALL`.
- [x] T002 Add 3 Swedish system prompts `src-tauri/src/prompts/{kontakter,generera,kallor}.rs` + `mod.rs` exports.
- [x] T003 Refactor `src-tauri/src/lib.rs` per-zone channel-listener loop to iterate `ZoneId::ALL`.
- [x] T004 Extend TS `ZoneId` type + `ZONE_IDENTITIES`/`ZONE_ORDER` (9 entries) in `src/lib/tauri-bridge.ts` + `src/components/DropZone.identity.ts`.
- [x] T005 Populate `initialZones` for 9 in `src/lib/status-store.ts`; update `zone-identity.json` fixture (9) + `zone_parametric.rs` count.
- [x] T006 Update channel-uniqueness test in `src-tauri/src/updater/commands.rs` for 9 zone channels.

> **Phase-1 follow-up gap**: verify `dragoverVerb()` in `DropZone.tsx` has arms for kontakter/generera/kallor (phase 1 may have left the 6-case fallback). Captured as T010 below.

---

## Phase 2: Help system (FR-018 – FR-024)

**BLOCKING before any UI code**: invoke `frontend-design` skill; all Swedish copy through `humanizer` skill.

- [ ] T007 [P] Author 18 Swedish help strings (9 short ≤80, 9 long ≤300) and create `src-tauri/tests/fixtures/zone-help-strings.json` (`{"<slug>":{"short","long"}}`). Run all 18 through the `humanizer` skill before committing.
- [ ] T008 [P] Create Rust `ZONE_HELP_STRINGS` const + accessor in `src-tauri/src/help/zone_help.rs`; wire `mod help;` in `lib.rs`.
- [ ] T009 [P] Create TS mirror `src/lib/help-strings.ts` (`ZONE_HELP_STRINGS: Record<ZoneId,{short,long}>`).
- [ ] T010 Fix `dragoverVerb()` + any 6-case switch in `src/components/DropZone.tsx` to cover kontakter/generera/kallor.
- [ ] T011 [US-help] Create `src/components/ZoneHelpPopover.tsx` (role="tooltip", short string, Esc/outside/re-click dismiss, stopPropagation so it never starts a drop).
- [ ] T012 [US-help] Add the per-zone `(?)` button (top-right, `aria-label="Hjälp om <title>"`) to `src/components/DropZone.tsx`; wire popover open state.
- [ ] T013 [P] Create `src/lib/use-help-panel.ts` — clone of `use-settings-panel.ts` (4-state visibility machine, 220/180ms timers, `helpIconEnabled = !wizardUp && !restartUp`).
- [ ] T014 [P] Create `src/components/HelpIcon.tsx` — chrome-bar `(?)` at `fixed right-24 top-3 z-40`, disabled-when-modal, `data-help-icon`.
- [ ] T015 Create `src/components/HelpPanel.tsx` — slide-in clone of `SettingsPanel.tsx`; body lists 9 zones (title + short + long + format badges; Generera shows `[TXT] [MD]`).
- [ ] T016 Mount `HelpIcon` + `HelpPanel` in `src/App.tsx`; wire mutual exclusion (FR-023): open-help → `settingsPanel.closePanel()`; open-settings → `helpPanel.closePanel()`.
- [ ] T017 [P] vitest `src/__tests__/HelpPanel.test.tsx` — open/close/Esc/X/scrim; 9-zone + 18-string render.
- [ ] T018 [P] vitest `src/__tests__/ZoneHelpPopover.test.tsx` — open/close/Esc/outside/re-click; no-dispatch-on-click.
- [ ] T019 [P] vitest `src/__tests__/help-mutual-exclusion.test.tsx` — open-help-closes-settings + reverse; FR-022 modal-gating (disabled during wizard/restart).
- [ ] T020 [P] vitest `src/__tests__/help-layout.test.tsx` — FR-017/SC-010: `data-settings-gear` present + clickable + `data-help-icon` left of it with 9-zone grid mounted.
- [ ] T021 [P] Rust `src-tauri/tests/help_strings_drift.rs` — `ZONE_HELP_STRINGS` (Rust) == `zone-help-strings.json` byte-for-byte; short ≤80, long ≤300 budget asserts; TS-mirror drift via existing T035-lineage test extension.

---

## Phase 3: Test seam (FR-015)

- [ ] T022 Add `#[cfg(debug_assertions)]` `JURADROP_OLLAMA_URL` override to `OllamaClient::new()` in `src-tauri/src/sidecar/client.rs`; release path unchanged (always `BASE_URL`).
- [ ] T023 [P] Rust unit test in `client.rs` (or `tests/`) — debug: env var routes to mock URL; assert env-read is inside a `#[cfg(debug_assertions)]` gate (source-grep invariant, Principle I / `ReleaseUsesLocalhostOnly`).

---

## Phase 4: Binary fixtures (FR-007 – FR-010, FR-008)

- [ ] T024 Define `pub const CANONICAL_EXTRACTION_PROBE_TEXT: &str` (~200 chars, `å ä ö`, no exotic unicode) in a shared module `src-tauri/tests/common/probe_text.rs` (or `src-tauri/src/zones/` if reused by the generator), so both the generator (T025) and `extraction_probe.rs` (T039) import the same literal. (analyze F7 — avoids the const living in a not-yet-created file.)
- [ ] T024a Special-case `OutputFormat::mirror_from(ZoneId::Generera) → docx` (analyze F2) so Generera writes `.generera.docx` regardless of `.txt`/`.md` input.
- [ ] T025 Create fixture-generator `src-tauri/tests/fixtures/generate_fixtures.rs` (example binary) — emits all committed fixtures deterministically (offline, no network).
- [ ] T026 [P] Generate 9 zone `.docx`/`.txt` fixtures in `src-tauri/tests/fixtures/documents/` per FR-007 (sammanfatta ~800w ruling; tillengelska ~500w sv; tillsvenska ~500w EN; punktlista ~1000w memo; anonymisera ~600w with 3+ fake names/2+ addr/2+ personnr(19010101-0101 style)/2+ phone/2+ email; forenkla ~600w lagspråk; kontakter = copy of anonymisera; generera-input.txt ~10-line outline; kallor ~700w PM with 10 mixed citations). Swedish content authored, run register/quality check.
- [ ] T027 [P] Embed `[TESTDATA — fiktiva uppgifter]` header in every personal-data fixture (FR-008).
- [ ] T028 [P] Generate 6 cross-format probes `src-tauri/tests/fixtures/extraction-probe/extraction-probe.{docx,pdf,txt,md,rtf,odt}` — same canonical paragraph (FR-009). `.md` includes frontmatter to exercise strip/restore. `.pdf` via lopdf, `.rtf` via `\u`-escaped byte template, `.odt` via zip(content.xml+manifest+mimetype).
- [ ] T029 Run the generator once; commit the produced binary fixtures.

---

## Phase 5: Integration tests + un-ignore audit

### User Story 1 — All 9 zones produce correct output (P1)

**Independent test**: `cargo test --test 'zone_pipeline_*'` → 9 zone tests green, each opening a real fixture through extract→prompt→mocked-generate→write.

- [ ] T030 [P] [US1] `src-tauri/tests/zone_pipeline_sammanfatta.rs` — wiremock + mock_builder; copy fixture to TempDir; handle_drop; assert source SHA unchanged + sidecar `.sammanfatta.docx` + non-empty + marker.
- [ ] T031 [P] [US1] `zone_pipeline_tillengelska.rs` (same shape; English-output marker).
- [ ] T032 [P] [US1] `zone_pipeline_tillsvenska.rs` (Swedish-output marker; English input fixture).
- [ ] T033 [P] [US1] `zone_pipeline_punktlista.rs` (bullet markers).
- [ ] T034 [P] [US1] `zone_pipeline_anonymisera.rs` (placeholder markers `[Person 1]` etc. + disclaimer paragraph present).
- [ ] T035 [P] [US1] `zone_pipeline_forenkla.rs` (klarspråk marker + disclaimer present).
- [ ] T036 [P] [US1] `zone_pipeline_kontakter.rs` (5 contact-type categories grouped).
- [ ] T037 [P] [US1] `zone_pipeline_generera.rs` (.txt input; generated-text marker + AI-disclaimer; .txt source SHA unchanged).
- [ ] T038 [P] [US1] `zone_pipeline_kallor.rs` (numbered citation list marker).

### User Story 2 — Every supported format extracts correctly (P2)

**Independent test**: `cargo test --test extraction_probe` → 6 format tests + 1 pages-failure green.

- [ ] T039 [US2] Create `src-tauri/tests/extraction_probe.rs` with `CANONICAL_EXTRACTION_PROBE_TEXT` const + 6 tests `{docx,pdf,txt,md,rtf,odt}` asserting extracted text == canonical (normalized; md after frontmatter strip).
- [ ] T040 [US2] Add the `.pages` failure-mode test (FR-012a): zero-byte `.pages` in TempDir → assert `PagesParseError` (spec 009 FR-006).

### User Story 3 — Un-ignored zone-pipeline tests run on every build (P3)

**Independent test**: `cargo test` runs zone tests without `--ignored`; `grep '#\[ignore\]'` shows only `// HARDWARE:`-justified entries.

- [ ] T041 [US3] Un-ignore the 6 tests in `src-tauri/tests/zone_sammanfatta_lifecycle.rs` (verified passing 0.28s); refresh header comment.
- [ ] T042 [US3] Audit `src-tauri/tests/zone_cancel.rs`: un-ignore if passing, else add `// HARDWARE:` reason.
- [ ] T043 [US3] Add `// HARDWARE: needs real gemma3:4b pull` to `sidecar_roundtrip.rs` `#[ignore]`; sweep all other `#[ignore]`'d tests in `src-tauri/tests/` and ensure each has a one-line reason (SC-004).
- [ ] T044 [US3] `src-tauri/tests/zone_pipeline_e2e_smoke.rs` (FR-014) — set `JURADROP_OLLAMA_URL` to wiremock URL (serial-guarded), drive one zone via the `new()` seam path, assert mock received the request + sidecar landed, unset env var.

---

## Phase 6: Constitution + docs + verification

- [ ] T045 Amend `.specify/memory/constitution.md`: version 1.0.0 → 1.1.0, add Sync Impact Report entry (FR-006), add one sentence enumerating the nine zones (FR-005, per R-003 correction — no find-and-replace needed).
- [ ] T046 [P] vitest `src/__tests__/constitution-version.test.tsx` (or extend existing) — assert `**Version**: 1.1.0` (SC-005).
- [ ] T047 [P] Rust `tests/fixture_markers.rs` — open each personal-data fixture, grep `[TESTDATA — fiktiva uppgifter]` (SC-007).
- [ ] T048 [P] Update `README.md` status/zone section (9 zones, help system) + `CHANGELOG.md` `[Unreleased]` Swedish body.
- [ ] T049 Run full suite: `npm test`, `npm run lint`, `npm run typecheck`, `cd src-tauri && cargo test && cargo clippy -- -D warnings && cargo fmt --check`. Confirm SC-008 (`time cargo test` growth ≤ 30s) + SC-009 (spec-011 denylist tests green).
- [ ] T050 Run `/tla` — distill + drift vs spec.allium + invariant coverage. Surface findings per validation-followup.md.
- [ ] T051 Commit + push to main; tick spec 013 `[x]` in `specs/INDEX.md` + register-history line.

---

## Dependencies

- Phase 1 ✅ → unblocks all.
- Phase 2 (help) is independent of Phases 3–5 (test infra) — can interleave.
- Phase 4 (fixtures) blocks Phase 5 US1/US2 (tests need the files). T024/T039 share the canonical const.
- Phase 3 (seam) blocks T044 only.
- Phase 6 T049/T050 depend on all prior; T045 blocks T046.

## Parallel opportunities

- T007/T008/T009 (strings: fixture/Rust/TS) in parallel.
- T013/T014 (hook/icon) in parallel; T017–T021 vitest in parallel.
- T030–T038 (9 zone tests) fully parallel once fixtures exist.
- T026/T027/T028 (fixtures) parallel.

## MVP scope

US1 (T030–T038) on real fixtures is the proof-of-correctness MVP. Help system (Phase 2) is the user-facing feature increment. Both required for spec completion.
