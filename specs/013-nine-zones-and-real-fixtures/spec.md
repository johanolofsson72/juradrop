# Feature Specification: Nine zones + real-document fixtures + integration tests

**Feature Branch**: `main` (solo direct-push)
**Created**: 2026-05-28
**Status**: Draft
**Track**: Full pipeline (per `specs/INDEX.md` row 013). Constitution amendment + behavior change + state-machine impact → `.allium` + `/tla` required.

**Input**: Add 3 new zones to the existing 6 (total = 9), update App.tsx grid from 2×3 to 3×3, amend the constitution's "Six drop zones in v1.0" clause to "Nine drop zones", and — most importantly — fill the test-fixture gap that has existed since spec 003 by creating realistic Swedish-legal-text documents for every zone in every supported format, AND by un-marking the `#[ignore]`'d zone-pipeline integration tests so they actually run on every `cargo test`.

## Why this spec exists (read first)

Two motivations, only one of which is "new feature":

1. **Three new zones** the user requested: `Plocka ut kontaktuppgifter`, `Generera juridisk text`, `Källförteckning`.
2. **A nine-spec-old test-fixture gap**: zero `.docx` / `.pdf` / `.txt` / `.md` / `.rtf` / `.pages` / `.odt` files exist anywhere in the repo. Zero. All 369 Rust tests and 325 vitest tests run against JSON-string fixtures, mocked extractor functions, or pure logic. The zone-pipeline integration tests (`zone_sammanfatta_lifecycle.rs`, `zone_cancel.rs`) are all `#[ignore]`'d because they were never wired up to a Tauri mock + wiremock harness. This is why a critical drag-drop position bug (post-spec-012 hardware test) lived in production from spec 003 → spec 012 undetected: no end-to-end test ever opened a real document.

Spec 013 closes both gaps in one commit so the test coverage problem doesn't persist into the 9-zone expansion.

## What's IN scope

| Item | Type | Estimated impact |
|---|---|---|
| Add `Kontakter`, `Generera`, `Kallor` to `ZoneId` enum (Rust + TS mirror) | Code | 3 new enum variants |
| 3 new Swedish system prompts in `src-tauri/src/prompts/` | Code | 3 new files |
| Update `zone-identity.json` fixture with 3 new entries | Fixture | +30 lines |
| Update App.tsx grid layout 2×3 → 3×3 | Code | 1 CSS class change |
| Amend constitution Principle VII ("Six drop zones in v1.0" → "Nine drop zones") | Constitution | MINOR bump 1.0.0 → 1.1.0 |
| Update README status section + CHANGELOG | Docs | ~20 lines |
| **Create 9 zone-representative Swedish .docx fixtures** | Fixture | 9 new files |
| **Create 7 cross-format extraction-probe fixtures** (same content, 7 formats) | Fixture | 7 new files |
| **Un-ignore the existing `zone_sammanfatta_lifecycle.rs` + `zone_cancel.rs` tests** | Test | Refactor to wiremock-based, drop Tauri mock requirement |
| **Add 9 new zone-specific integration tests** | Test | One per zone, all running on every `cargo test` |
| **Add 1 end-to-end smoke test** | Test | Programmatic drag-drop simulation via test-seam |

## What's OUT of scope (defer to follow-up)

| Item | Reason |
|---|---|
| Real Playwright browser-driving | tauri-driver still doesn't support macOS (per withdrawn earlier spec 013). The "integration test" route is the right substitute for now. |
| Real-Ollama (un-mocked) periodic validation | Out of scope; would need a separate slow-test-suite. Mocked-Ollama with deterministic responses is sufficient for the contract this spec ships. |
| Settings panel 4th tier or per-zone tier override | Spec 010 deferred items, still deferred. |
| Crash diagnostic log (spec 011 `deferred CrashReproductionLogging`) | Out of scope. |

## Clarifications

### Session 2026-05-28

- Q: Source of the Swedish legal fixture content — write from scratch or use public-domain sources (riksdagen.se, dom.se)? → A: **Write from scratch.** Original content has zero license/IP risk, can be deliberately crafted to include the edge cases each zone needs (e.g., the Anonymisera fixture needs explicit fake personnummer + addresses; the Källförteckning fixture needs ~10 citations in mixed conventions; the Plocka-ut-kontaktuppgifter fixture needs all 5 contact-type categories). Real court rulings would be authentic but uncontrolled. Fully synthesized = fully deterministic.
- Q: Fixture content language register — informal vs formal? → A: **Formal but readable.** Each fixture imitates the register of a junior-lawyer-written memo: complete sentences, correct Swedish, proper legal vocabulary (`hyresavtal`, `preskription`, `klagofrist`), but no archaic constructions that would distract. Anything tested specifically for formality/informality (e.g., Förenkla's input) gets the appropriate register.
- Q: Cross-format probe — same content or one-per-format with different content? → A: **Same content across all 7 formats.** One canonical Swedish paragraph (~200 chars) embedded in `.docx`, `.pdf`, `.txt`, `.md`, `.rtf`, `.pages`, `.odt`. This isolates the extraction layer from the content layer: any extractor regression manifests as the same fixture failing in only one format, not as a chase across multiple per-format-tailored documents. The zone-specific fixtures are SEPARATE — they're the canonical-content-per-zone files used to test zone behaviour.
- Q: Test mocking strategy for the Ollama HTTP layer? → A: **~~Hand-rolled HTTP mock, no new dep.~~ SUPERSEDED 2026-05-28 during /plan.** The hand-rolled rationale ("avoid adding wiremock") was based on a false premise: `wiremock = "0.6"` is ALREADY a dev-dependency (`src-tauri/Cargo.toml` `[dev-dependencies]`, added at spec 003 T056/T057/T060), and the existing zone-pipeline integration tests already use the `wiremock::MockServer` + `tauri::test::mock_builder` pattern and pass in 0.28s. Per user decision, the plan REUSES the existing wiremock pattern instead of hand-rolling. Net dep delta remains 0 (wiremock already present). The `MockOllamaServer` entity in `.allium` is therefore the wiremock `MockServer`, not a custom TcpListener.
- Q: How aggressive on un-ignoring existing tests? Full un-ignore or selective? → A: **Selective + audit.** Walk every `#[ignore]`'d test in `src-tauri/tests/`, classify each as: (a) un-ignorable with the new wiremock harness (un-ignore + run), (b) genuinely requires real hardware (keep `#[ignore]`'d, add comment explaining why), (c) obsolete (delete). Expected breakdown: ~6 un-ignorable, ~3 hardware-only, ~0 obsolete. Final state: every `#[ignore]`'d test has an explicit one-line reason comment.
- Q: How should users discover what each zone does? → A: **Hybrid (option C).** Per-zone `(?)` icon at top-right of each zone card opens a popover with the short Swedish explanation (≤ 80 chars). Chrome-bar `(?)` icon (placed left of the spec 010 gear icon) opens a full slide-in help panel listing all 9 zones with longer Swedish explanations (≤ 300 chars each, 2-3 sentences). Mirrors spec 010's gear/panel design exactly: slide-in from right, scrim, Esc / close-X / outside-click dismissal. Two Swedish strings per zone × 9 zones = 18 new strings in the drift fixture.
- Q: `.pages` cross-format probe — include or defer? → A: **Defer per spec 009's "best-effort" contract (option B3).** Spec 009 already ratified that `.pages` extraction may fail with `pages_parse_error`. Spec 013's cross-format probe is 6 formats (`.docx/.pdf/.txt/.md/.rtf/.odt`), all required to extract the canonical paragraph successfully. `.pages` gets a SEPARATE failure-mode test: drop a deliberately-malformed zero-byte `.pages` file, assert the named-format error fires. Real `.pages` extraction validation deferred until a future spec where the user supplies a manually-exported Pages fixture (Apple IWA is proprietary and undocumented; cannot be synthesized).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — All 9 zones produce correct output for realistic Swedish legal input (Priority: P1)

A law student drops realistic Swedish documents on each of the 9 zones; each zone produces a sidecar file with zone-appropriate content. The behavior is verified deterministically against fixtures, not just manually on the developer's machine.

**Why this priority**: This is the proof that the system works end-to-end. Without it, the 9-zone expansion is just code that compiles — same trap that hid the drag-drop bug for nine specs.

**Independent Test**: Run `cd src-tauri && cargo test -- --test-threads=4` and observe 9 new zone-pipeline tests pass, each opening a real `.docx`, running it through extract → prompt-build → mocked-generate → write, and asserting the output sidecar's path + non-empty content + zone-specific markers.

**Acceptance Scenarios**:

1. **Given** the `klientuppgifter.docx` fixture (contains "Anna Andersson, personnummer 19010101-0101, Storgatan 1, Stockholm"), **When** the Anonymisera pipeline runs against it, **Then** the sidecar file `klientuppgifter.anonymisera.docx` is created with content where the original name/personnummer/address have been replaced with `[Person 1]`, `[Personnr 1]`, `[Adress 1]` placeholders (or whatever the system prompt instructs).
2. **Given** the same `klientuppgifter.docx`, **When** the Plocka-ut-kontaktuppgifter pipeline runs, **Then** the sidecar lists all 5 contact-type categories: namn, adress, personnummer, telefonnummer, e-post — each as a sorted list grouping the same type.
3. **Given** the `pm-med-kallor.docx` fixture (contains 10 mixed-format citations), **When** the Källförteckning pipeline runs, **Then** the sidecar contains a numbered list of all 10 citations formatted consistently per the system prompt's chosen convention.

---

### User Story 2 — Every supported file format extracts correctly (Priority: P2)

The cross-format probe fixture (`extraction-probe.{docx,pdf,txt,md,rtf,pages,odt}`) — all 7 files containing the same canonical Swedish paragraph — is dropped on the Sammanfatta zone in turn. All 7 produce a sidecar with the same upstream extracted text reaching the model.

**Why this priority**: Format-extraction regressions (`pdf-extract` bumping a version, `docx-rs` changing API, `rtf-parser` breaking on a Swedish character) are the single most common silent breakage class. A canonical probe catches them per-format-per-CI-run.

**Independent Test**: 7 new integration tests in `src-tauri/tests/extraction_probe.rs`, one per format. Each opens its probe file, runs the extractor, asserts the extracted text equals the canonical paragraph (modulo expected per-format normalization: e.g., `.md` strips frontmatter).

**Acceptance Scenarios**:

1. **Given** `extraction-probe.docx`, **When** the docx extractor runs, **Then** the returned text equals the canonical paragraph (UTF-8 byte-comparison after newline normalization).
2. **Given** `extraction-probe.pdf`, **When** the pdf-extract pipeline runs, **Then** the returned text equals the canonical paragraph (some PDF whitespace variation is permitted; assert against a normalized form).
3. **Given** `extraction-probe.pages` (a real macOS Pages bundle, not a fake), **When** the pages extractor runs, **Then** either the canonical paragraph extracts OR a clear `PagesParseError` returns with the named-format Swedish error (per spec 009 FR-006).

---

### User Story 3 — Un-ignored zone-pipeline integration tests run on every CI build (Priority: P3)

The 6 `#[ignore]`'d tests in `zone_sammanfatta_lifecycle.rs` and `zone_cancel.rs` (8 total per earlier audit) are converted to run against the hand-rolled mock instead of the never-wired Tauri+wiremock combination. Result: `cargo test` actually exercises the full handle_drop → dispatch → output-write pipeline.

**Why this priority**: This is the long-overdue cleanup. Tests labeled `#[ignore]` are tests that don't run, which is the same as no test at all.

**Independent Test**: `cd src-tauri && cargo test --test zone_sammanfatta_lifecycle --test zone_cancel` — every test in those files runs (none stays `#[ignore]`'d), all pass, total runtime under 30 seconds.

**Acceptance Scenarios**:

1. **Given** the existing `drop_docx_writes_sidecar_and_leaves_source_byte_identical` test, **When** it runs against the new mock harness, **Then** it passes without `#[ignore]` and asserts: (a) source file SHA-256 unchanged, (b) sidecar file created next to source.
2. **Given** the `multi_file_drop_emits_multiple_files_failure` test, **When** un-ignored, **Then** it passes — proving the multiple-files guard from spec 003 actually fires.
3. **Given** any test that genuinely requires real hardware (e.g., one needing a real macOS file dialog), **When** the spec-013 audit runs, **Then** it stays `#[ignore]`'d AND has a one-line comment explaining why.

---

### Edge Cases

- **`.pages` extractor failure on macOS-only IWA format**: spec 009 anticipated this. The cross-format probe accepts either successful extraction OR `PagesParseError`. Not both = test fail.
- **Fixture truncation cap**: the 24,000-char truncation cap from spec 005 must NOT apply to the cross-format probes (they're ~200 chars each). But it MUST still apply to zone fixtures that happen to exceed it. Fixtures are kept well under to avoid testing the truncation behavior twice (spec 005 already does).
- **Anonymisera fixture must contain OBVIOUSLY FAKE personnummer**: using `19010101-0101` or `20000101-0001`. Real personnummer accidentally committed = privacy nightmare.
- **README's screenshot embeds** (spec 012 placeholders) must NOT break — they're still placeholders. This spec doesn't regenerate them.
- **Settings panel grid** (spec 010 was designed for 2×3) — verify the gear icon + panel placement still works on a 3×3 layout. Should be invisible to the change since panel is fixed-positioned.
- **Cross-language drift fixture** must grow to include the 3 new zone strings — drift test from spec 004 lineage extends naturally.

## Requirements *(mandatory)*

### Functional Requirements

#### Three new zones
- **FR-001**: `ZoneId` enum (Rust `src-tauri/src/zones/zone_id.rs` + TS `src/components/DropZone.identity.ts`) MUST gain 3 new variants: `Kontakter`, `Generera`, `Kallor` (Rust naming; TS uses corresponding camelCase if convention is camelCase, otherwise mirror). Variant order in the canonical list determines grid position.
- **FR-002**: 3 new Swedish system prompts MUST live at `src-tauri/src/prompts/kontakter.rs`, `generera.rs`, `kallor.rs`. Each follows the existing prompt style (zone-specific instruction in Swedish, ≤ 80 chars per line in the prompt body for readability, no English fallback).
- **FR-003**: `src-tauri/tests/fixtures/zone-identity.json` MUST gain 3 new entries with `slug`, `title`, `hint_copy`, `sidecar_suffix`, `has_disclaimer_paragraph` fields per existing schema. Specifically:
  - Kontakter: title `Plocka ut kontaktuppgifter`, slug `kontakter`, sidecar suffix `.kontakter`, no disclaimer.
  - Generera: title `Generera juridisk text`, slug `generera`, sidecar suffix `.generera`, **HAS DISCLAIMER** (AI-genererad text — kontrollera mot källa). **OUTPUT FORMAT (analyze F2, 2026-05-28):** Generera ALWAYS writes a `.generera.docx` sidecar regardless of the `.txt`/`.md` instruction-file input — it generates a new legal *document*, so the spec-005 input-mirror rule (`.txt → .txt`) does NOT apply. `OutputFormat::mirror_from` special-cases `ZoneId::Generera → docx`.
  - Kallor: title `Källförteckning`, slug `kallor`, sidecar suffix `.kallor`, no disclaimer.
- **FR-004**: `App.tsx` grid CSS classes require **no change** — `lg:grid-cols-3` produces 2 rows × 3 cols with 6 zones and 3 rows × 3 cols with 9 zones automatically (same column count, more rows). The `sm:grid-cols-2` breakpoint and `grid-cols-1` mobile fallback remain as-is. **CLARIFIED 2026-05-28 (analyze F5):** phase 1 confirmed the grid auto-expands; this FR is satisfied with zero CSS edits.

#### Constitution amendment
- **FR-005**: `.specify/memory/constitution.md` MUST be amended for the zone expansion. **CORRECTION 2026-05-28 (/plan):** a grep of the constitution found NO occurrence of `six zones`/`six drop zones`/`2×3`/`6 zones`/zone names — the original premise (existing zone-count text to replace) was inaccurate. The constitution only references "themed drop zones" generically (line 28) with no count. Therefore the amendment is: (a) version bump 1.0.0 → 1.1.0 (MINOR — "material expansion" per Governance), (b) a Sync Impact Report entry per FR-006, and (c) add ONE explicit sentence enumerating the nine zones to the relevant principle so the bump is materially grounded (not a version-only no-op). No existing text needs find-and-replace.
- **FR-006**: Add a Sync Impact Report entry to constitution.md documenting the 1.0.0 → 1.1.0 change. Per existing convention at the top of the constitution.

#### Zone-representative fixtures
- **FR-007**: 9 new `.docx` fixtures MUST exist at `src-tauri/tests/fixtures/documents/<zone>-input.docx`. Each contains realistic Swedish legal-or-administrative content sized between 300-1500 words, deliberately constructed to exercise its zone:
  - `sammanfatta-input.docx`: ~800-word fictional civil ruling.
  - `tillengelska-input.docx`: ~500-word Swedish legal text suitable for translation.
  - `tillsvenska-input.docx`: ~500-word English contract text (the ONLY non-Swedish fixture).
  - `punktlista-input.docx`: ~1000-word legal memo with multiple discrete points.
  - `anonymisera-input.docx`: ~600-word client matter with 3+ fictitious personal names, 2+ addresses, 2+ personnummer (ALL obviously fake), 2+ phone numbers, 2+ emails.
  - `forenkla-input.docx`: ~600-word dense lagspråk text ripe for klarspråk rewrite.
  - `kontakter-input.docx`: REUSES `anonymisera-input.docx` content (already has every contact-type the zone extracts) — symlink or duplicate file.
  - `generera-input.txt`: ~10-line prompt/outline ("skapa en uppsägning av hyreskontrakt enligt jordabalken 12 kap, hyresgäst Anna Andersson, fastighet Storgatan 1 Stockholm, avflyttningsdatum 2026-09-30, hyresvärd...").
  - `kallor-input.docx`: ~700-word juridisk PM with 10 citations of mixed types (SFS, NJA, böcker, EU-direktiv).
- **FR-008**: All fixture personal data MUST be flagged-as-fake in the file content itself (header comment `[TESTDATA — fiktiva uppgifter]`) to ensure no future contributor accidentally treats them as real.

#### Cross-format probe fixtures (post-clarification: 6 formats, not 7)
- **FR-009**: 6 `extraction-probe.<ext>` fixtures MUST exist at `src-tauri/tests/fixtures/extraction-probe/extraction-probe.<ext>` for `<ext> ∈ {docx, pdf, txt, md, rtf, odt}`. All contain the SAME canonical Swedish paragraph: a single 200-character paragraph with `å ä ö` to verify UTF-8 encoding, no unicode edge cases that PDF/RTF would mangle.
- **FR-009a**: `.pages` is EXCLUDED from the cross-format probe (option B3 per Clarification Q7). A separate failure-mode test (FR-012a) drops a deliberately-malformed zero-byte `.pages` file to assert `pages_parse_error` fires correctly. Real `.pages` extraction validation is deferred until a future spec where the user supplies a manually-exported Pages bundle.
- **FR-010**: The canonical paragraph MUST be byte-pinned in a Rust constant `CANONICAL_EXTRACTION_PROBE_TEXT` so the assertion is deterministic.

#### Integration tests
- **FR-011**: 9 new Rust integration tests at `src-tauri/tests/zone_pipeline_<zone>.rs` (one per zone). Each:
  - Spawns a `wiremock::MockServer` (already a dev-dep) with a deterministic `/api/generate` response keyed to the zone's expected output shape.
  - Builds the Tauri mock app via `tauri::test::mock_builder` (existing pattern) and injects the mock client via `OllamaClient::with_base_url(server.uri())`.
  - Opens the zone's fixture document.
  - Calls `DropZone::handle_drop` (the same entry point lib.rs's DragDrop handler uses; no decomposition needed — the existing tests prove this path works).
  - Asserts: (a) source file SHA-256 unchanged, (b) sidecar file created with correct name + extension, (c) sidecar content non-empty, (d) sidecar content contains zone-specific markers per the system prompt's contract.
- **FR-012**: 6 new Rust integration tests at `src-tauri/tests/extraction_probe.rs` (one per format in `{docx, pdf, txt, md, rtf, odt}`). Each opens its `extraction-probe.<ext>`, runs the extractor, asserts the returned text equals (or extends-with-known-prefix) the `CANONICAL_EXTRACTION_PROBE_TEXT`.
- **FR-012a**: 1 additional test in `extraction_probe.rs` covering `.pages` failure mode: writes a zero-byte file to a tempdir as `.pages`, runs the pages extractor, asserts it returns `pages_parse_error` per spec 009 FR-006. Proves the named-format-error path stays wired even though full `.pages` extraction is deferred.
- **FR-013**: Walk every `#[ignore]`'d test in `src-tauri/tests/*.rs`. For each:
  - If un-ignorable → un-ignore + verify it passes. **VERIFIED 2026-05-28 (/plan):** the 6 tests in `zone_sammanfatta_lifecycle.rs` already pass with `--ignored` in 0.28s; the `#[ignore]` "expensive Tauri runtime" reason is false. These un-ignore cleanly.
  - If genuinely hardware-required (e.g. `sidecar_roundtrip.rs` needs a real `gemma3:4b` model pull) → keep `#[ignore]`'d + add one-line `// HARDWARE: <reason>` comment.
  - Document the audit in this spec's tasks.md.
- **FR-014**: One end-to-end smoke test at `src-tauri/tests/zone_pipeline_e2e_smoke.rs` that exercises a programmatic drag-drop simulation through ALL the layers up to (and including) the mocked HTTP call. Proves the wiring stays intact across refactors.

#### Test-seam env vars (debug-only)
- **FR-015**: `src-tauri/src/sidecar/client.rs` MUST read `JURADROP_OLLAMA_URL` env var in debug builds (`#[cfg(debug_assertions)]`) and use it as the base URL if set. Release builds always use the hardcoded `http://127.0.0.1:11434`. Mirrors the pattern proposed in withdrawn spec 013 contract `settings-commands.md` § AppDataDirSandbox + Clarification Q4 there.

#### Help system (post-clarification Q6 — hybrid C)
- **FR-018**: Each zone card MUST render a small `(?)` icon at its top-right corner. Click opens a popover (CSS-positioned absolute, no portal needed) containing the zone's **short Swedish help string** (≤ 80 chars). Popover dismissed by Esc, clicking outside, or clicking the icon again. ARIA: button has `aria-label="Hjälp om <zone-title>"`, popover has `role="tooltip"`.
- **FR-019**: A chrome-bar `(?)` icon MUST appear to the LEFT of the spec 010 gear icon (canonical chrome-bar order: help, gear, update-indicator — leftmost to rightmost). Click opens a slide-in `HelpPanel` from the right edge, mirroring spec 010's `SettingsPanel` mechanics: scrim, Esc / close-X / outside-click dismiss, fixed 380px width.
- **FR-020**: The `HelpPanel` MUST list all 9 zones in the canonical order with: zone title (large), short string (helper line), long Swedish explanation (≤ 300 chars, 2-3 sentences), and a small visual indicator of what file formats the zone accepts (reuse the `[DOCX]` badge convention).
- **FR-021**: Per-zone help strings (9 short + 9 long = 18 strings) MUST live in the cross-language drift fixture at `src-tauri/tests/fixtures/zone-help-strings.json` with a new top-level structure: `{ "<slug>": { "short": "...", "long": "..." } }` for each of the 9 zones. Rust + TS mirrors enforced by the existing T035-lineage drift test.
- **FR-022**: The chrome-bar `(?)` MUST be disabled (same pattern as spec 010 FR-005a) when any other modal/wizard is up (first-run wizard, update-restart confirm, settings panel open).
- **FR-023**: Opening the `HelpPanel` while the settings panel is open MUST close the settings panel first (mutual-exclusion — at most one slide-in panel visible at a time). Same the other direction.
- **FR-024**: All help copy MUST flow through the `humanizer` skill before shipping (Swedish, no AI-tells, ≤ char budgets). Per existing convention from specs 008-012.

#### Cross-language drift
- **FR-016**: `zone-identity.json` gaining 3 new entries automatically extends the drift test from spec 004 lineage. No new drift-test code needed; the test asserts every entry matches the Rust + TS sides byte-for-byte, which the test runner discovers automatically.
- **FR-016a**: `zone-help-strings.json` (NEW) drift test extends the same lineage: every entry matches the Rust `ZONE_HELP_STRINGS` constant (lives somewhere in `src/lib/` matching the spec 010 settings-panel-strings pattern) byte-for-byte.

#### Layout sanity
- **FR-017**: Spec 010 settings panel MUST continue to work without modification. The gear icon is fixed-positioned (per spec 010 FR-001 / Clarification Q5) and unaffected by the grid layout change. Verified by a vitest assertion that the gear icon renders + can be opened on a window with the 9-zone grid mounted.

### Key Entities

- **ZoneId**: Rust enum (`src-tauri/src/zones/zone_id.rs`) — gains `Kontakter`, `Generera`, `Kallor` variants. Variant ORDER determines grid position.
- **ZoneIdentity**: per-zone metadata (slug, title, hint_copy, sidecar_suffix, has_disclaimer). 3 new entries.
- **CanonicalExtractionProbeText**: a `&'static str` constant in test code holding the 200-char paragraph. Asserts deterministic extraction across 7 formats.
- **MockOllamaServer**: hand-rolled TcpListener-based HTTP mock. Per-test-spawned, deterministic responses, no new deps.
- **JURADROP_OLLAMA_URL**: debug-only env var test seam (FR-015).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All 9 zones present in the rendered grid after spec 013 ships. Verified by a vitest test asserting `ZONE_ORDER.length === 9` (and the Rust `ZoneId::ALL.len() == 9`). **CORRECTED 2026-05-28 (analyze F1):** the original `MODEL_TIERS.length === 9` was a copy-paste error — `MODEL_TIERS` is the spec-010 settings tier set (3 entries), unrelated to zone count.
- **SC-002**: 9 zone-pipeline integration tests pass on every `cargo test`. Verified by test output: each test prints its zone name + sidecar-file-created confirmation.
- **SC-003**: 6 cross-format probe tests (`docx, pdf, txt, md, rtf, odt`) + 1 `.pages` failure-mode test pass on every `cargo test`. The 6 each extract the canonical paragraph; the `.pages` test asserts the spec-009 named-format error fires. **CLARIFIED 2026-05-28 (analyze F3):** `.pages` is NOT part of the 6-format probe set (FR-009a) — it has a dedicated failure-mode test (FR-012a).
- **SC-004**: Zero tests remain `#[ignore]`'d without a one-line reason comment. Verified by a grep in CI: `grep -rE '#\[ignore\]' src-tauri/tests/ | xargs -I {} test (lookbehind for // HARDWARE: comment within 3 lines above)`.
- **SC-005**: Constitution version bumped to 1.1.0 with Sync Impact Report entry. Verified by a vitest test reading the constitution file and asserting `**Version**: 1.1.0`.
- **SC-006**: 9-zone grid uses the same `lg:grid-cols-3` class (= 3 columns = 3 rows for 9 zones), preserving spec 004's responsive breakpoints.
- **SC-007**: Every fixture document containing personal data has the `[TESTDATA — fiktiva uppgifter]` header. Verified by a Rust test that opens each fixture and greps for the marker.
- **SC-008**: Total `cargo test` runtime grows by ≤ 30 seconds (the 9 zone-pipeline tests + 7 extraction-probe tests + un-ignored tests must complete inside this budget).
- **SC-009**: Spec 011 grep tests (English-leakage denylist, telemetry denylist) still pass after spec 013 ships.
- **SC-010**: Spec 010 settings panel still renders correctly + the gear icon is clickable in the 9-zone layout. Verified by a vitest test mounting `<App />` with klar state and asserting `data-settings-gear` attribute is present and clickable.

## Assumptions

- **Constitution amendment is appropriate.** MINOR bump 1.0.0 → 1.1.0 per Governance "material expansion" clause. Adding three zones is a material expansion of the user-facing surface; doesn't weaken any principle.
- **Net dep delta: 0.** The hand-rolled HTTP mock uses only `tokio::net::TcpListener` + `httparse` (already transitive). No `wiremock`, no `mockito`. Per spec 011 telemetry-denylist discipline.
- **Settings panel layout survives the grid change.** Gear icon is fixed-positioned at top-right; panel slides in from the right edge; neither depends on the zone grid's dimensions. Verified by FR-017.
- **`.pages` extraction may fail on the cross-format probe.** That's acceptable per spec 009's "best-effort" contract — the test accepts either successful extraction OR a `PagesParseError`. Other 6 formats MUST extract successfully (hard fail otherwise).
- **3 new zone names don't collide with macOS reserved words or Swedish naming conventions.** Kontakter, Generera, Kallor (with `K-` to avoid `Källor` containing the å character in the identifier — Rust enum variants are conventionally ASCII).
- **Generera zone takes a prompt/outline, not a full document.** The user drops a `.txt` (or `.md`) file containing instructions; the zone generates new legal text from those instructions. Different input/output shape from the other 8 zones (which transform an existing document). This may need extra prompt engineering — captured in spec 013's tasks.
- **Manual real-hardware verification (spec 011 T016 lineage) is still acceptable for the slowest tests.** Some `#[ignore]`'d tests may stay ignored after the audit if un-ignoring them would require a real macOS file dialog or a signed-DMG. Documented per FR-013.
