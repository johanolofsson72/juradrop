# Phase 0 Research — Spec 013

Decisions and corrected premises. Items marked **PREMISE CORRECTION** are spec assumptions falsified by reading the actual codebase during `/plan`; they were amended in `spec.md` and surfaced to the user.

## R-001 — Mock strategy: reuse wiremock (PREMISE CORRECTION)

**Decision**: Reuse `wiremock::MockServer` for all zone-pipeline integration tests. Drop the hand-rolled `TcpListener` mock from Clarification Q4.

**Rationale**: `wiremock = "0.6"` is **already** a `[dev-dependencies]` entry in `src-tauri/Cargo.toml` (added spec 003, T056/T057/T060). The existing `zone_sammanfatta_lifecycle.rs` already uses `wiremock::MockServer` + `tauri::test::mock_builder` and all 6 tests pass in **0.28s** with `--ignored`. Q4's "avoid adding wiremock" rationale was therefore moot. Net dep delta is 0 either way; wiremock is strictly less code to maintain. **User-confirmed 2026-05-28.**

**Alternatives considered**: Hand-rolled TcpListener mock (rejected — more code, no benefit since wiremock is already linked into the test build).

## R-002 — `#[ignore]` audit: tests are not expensive (PREMISE CORRECTION)

**Decision**: Un-ignore the 6 tests in `zone_sammanfatta_lifecycle.rs` and audit `zone_cancel.rs`.

**Rationale**: The `#[ignore = "requires Tauri mock app + wiremock; run with --ignored"]` reason claims expense, but measured runtime is 0.28s for all 6. They are correct, complete, and fast. The genuine hardware-only test is `sidecar_roundtrip.rs` (needs a real `gemma3:4b` pull) — that stays `#[ignore]`'d with a `// HARDWARE:` reason. `settings_dispatch_invariants.rs` references the ignore in a comment only.

**Audit plan (FR-013)**: classify each `#[ignore]` in `src-tauri/tests/`:
- `zone_sammanfatta_lifecycle.rs` (6) → un-ignore (verified passing).
- `zone_cancel.rs` → un-ignore if passing; else `// HARDWARE:` with reason.
- `sidecar_roundtrip.rs` → keep ignored, add `// HARDWARE: needs real gemma3:4b model pull`.
- Any other → classify during phase 5.

## R-003 — Constitution amendment scope (PREMISE CORRECTION)

**Decision**: Amendment = version bump 1.0.0 → 1.1.0 + Sync Impact Report entry + ONE new sentence enumerating the nine zones.

**Rationale**: `grep -niE "six|2×3|6 zones|six drop zones"` against `.specify/memory/constitution.md` returns **nothing**. FR-005's premise (existing zone-count text to find-and-replace) was inaccurate — the constitution references "themed drop zones" generically (line 28) with no count. SC-005 + a planned vitest still require `**Version**: 1.1.0`, so the bump proceeds; it is grounded by adding an explicit nine-zone enumeration so the MINOR bump is material rather than a version-only no-op.

## R-004 — FR-015 env seam: keep, exercise via e2e smoke

**Decision**: Implement the `JURADROP_OLLAMA_URL` debug-only override in `client.rs::with_base_url`/`new`. Exercise it in `zone_pipeline_e2e_smoke.rs` so it is not dead code. **User-confirmed 2026-05-28.**

**Rationale**: Integration tests inject the client via `OllamaClient::with_base_url(server.uri())` and don't need the env var. But the seam gives a manual dev hook (point the running app at a mock) and the e2e smoke can drive the construction path that reads it. Gate strictly on `#[cfg(debug_assertions)]`; release builds never read the env var (Principle I / `ReleaseUsesLocalhostOnly`).

**Implementation shape**: in `OllamaClient::new()`, `#[cfg(debug_assertions)]` reads `std::env::var("JURADROP_OLLAMA_URL")` and routes to `with_base_url` if set; `#[cfg(not(debug_assertions))]` always uses `BASE_URL`.

## R-005 — Help system architecture

**Decision**: Mirror spec 010 settings-panel module shape.
- `src/lib/help-strings.ts` — `ZONE_HELP_STRINGS: Record<ZoneId,{short,long}>` (TS mirror).
- `src-tauri/src/help/zone_help.rs` — `ZONE_HELP_STRINGS` Rust const (drift source of truth).
- `src-tauri/tests/fixtures/zone-help-strings.json` — drift fixture; the existing T035-lineage drift test discovers it.
- `src/lib/use-help-panel.ts` — visibility state machine cloned from `use-settings-panel.ts` (4 states, same animation timings).
- `HelpPanel.tsx` — slide-in from right, 380px, scrim, Esc/X/outside-click (clone of `SettingsPanel.tsx`).
- `HelpIcon.tsx` — chrome-bar button at `fixed right-24 top-3` (left of gear at `right-14`, which is left of UpdateIndicator at `right-3`). Order left→right: help, gear, update. `aria-label` Swedish.
- `ZoneHelpPopover.tsx` — absolute-positioned popover anchored top-right of each card; `role="tooltip"`; Esc/outside/re-click dismiss.

**Mutual exclusion (FR-023)**: wired in `App.tsx` — `openHelpPanel` calls `settingsPanel.closePanel()` first; `openSettingsPanel` calls `helpPanel.closePanel()` first. Enforced structurally; covered by a vitest mutual-exclusion test.

**Modal-gating (FR-022)**: `HelpIcon` reuses the `use-settings-panel` `gearIconEnabled` predicate logic (wizard-up OR restart-up) — extract the predicate into a shared `useChromeModalGate()` hook or duplicate the two store selectors. Decision: duplicate the two selectors in `use-help-panel.ts` (cheap, no refactor risk to spec 010).

## R-006 — Binary fixture generation

**Decision**: Generate fixtures programmatically at test-prep time, committed to the repo (not generated per-run, so CI is deterministic and offline).
- `.docx` — `docx-rs` `Docx::new().add_paragraph(...).build().pack(...)` (same helper the existing tests use). A small Rust `xtask`-style generator binary OR a `#[test]`-gated generator writing into `tests/fixtures/`. Decision: a `tests/fixtures/generate_fixtures.rs` example binary run once; outputs committed.
- `.txt` / `.md` — plain UTF-8 writes (md includes frontmatter to exercise the spec-005 strip/restore).
- `.pdf` — minimal valid PDF embedding the canonical paragraph. `lopdf` (already a dep) can build one, OR commit a pre-built minimal PDF. Decision: build with `lopdf` in the generator.
- `.rtf` — hand-written RTF byte template with `\u` escapes for `å ä ö` (rtf-parser must round-trip these).
- `.odt` — minimal ODT (zip of `content.xml` + `META-INF/manifest.xml` + `mimetype`); `quick-xml` + `zip`. NOTE: check whether `zip` is available; docx-rs uses `zip` transitively. Decision: build the ODT zip in the generator using the same zip crate docx-rs pulls in.
- malformed `.pages` — zero-byte file, written in-test (FR-012a), not committed.

**Canonical probe text (FR-010)**: a single `pub const CANONICAL_EXTRACTION_PROBE_TEXT: &str` (~200 chars) with `å ä ö`, no exotic unicode, defined once in `extraction_probe.rs` and reused by the generator.

**Personal-data marker (FR-008/SC-007)**: every fixture whose content includes fictitious personal data embeds `[TESTDATA — fiktiva uppgifter]` as the first paragraph. A Rust test greps each for the marker.

## R-007 — Generera zone input/output shape

**Decision**: `Generera` accepts `.txt`/`.md` instruction files only (FR hint copy already set in phase 1). Its dispatch reuses the standard pipeline: extract instructions → build prompt → generate → write `.generera.docx` sidecar. The system prompt (phase-1 `generera.rs`) instructs the model to PRODUCE legal text from the outline rather than transform a document. The disclaimer paragraph (FR-003: "AI-genererad text — kontrollera mot källa") is appended on write, same mechanism as anonymisera/forenkla.

**Open consideration**: `Generera`'s output is freshly generated, so the source-immutability invariant still holds (the `.txt` instruction file is read-only input). The integration test asserts the `.txt` source SHA-256 is unchanged.

## R-008 — Kontakter fixture reuse

**Decision**: `kontakter-input.docx` duplicates `anonymisera-input.docx` content (FR-007) — it already contains every contact-type category. A plain file copy in the generator (not a symlink — symlinks complicate git + cross-platform checkout).

## Dependency audit

Net new runtime deps: **0**. Net new dev-deps: **0** (wiremock, tempfile, sha2 all present). `zip`/`lopdf`/`quick-xml` are already in the dependency tree (docx-rs / pdf-extract / odt support). Telemetry denylist (spec 011) unaffected — no brand-name deps added.
