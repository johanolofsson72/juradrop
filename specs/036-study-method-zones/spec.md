# Feature Specification: Study-method drop zones (9 → 12)

**Feature Branch**: `036-study-method-zones` (direct-push to `main`, no feature branch per project workflow)

**Created**: 2026-06-03

**Status**: Draft

**Input**: User description: "Three new study-method drop zones (9→12 grid): Identifiera rättsfrågorna (issue-spotting), Strukturera (IRAC), Förklara begreppen (extract + define legal jargon in plain Swedish). All transform/extract the DROPPED document only — deliberately NOT a citation/lagrum-hunting zone."

## Why these three (and why NOT a citation zone)

JuraDrop's existing nine zones cover translation, summary, bullets, anonymisation, plain-language rewrite, contact extraction, drafting, and source-listing. They do not cover the *study methods* a Swedish law student actually practises: spotting the legal issues in a case, structuring an answer in IRAC, and decoding jargon. These three zones add that, and every one operates **only on the text the student dropped** — the model reorganises, extracts, or explains the student's own material; it never supplies external legal content.

A fourth obvious-sounding zone — "find the relevant statutes / case law" — is **deliberately rejected**. A local model with no retrieval will *hallucinate* SFS paragraph numbers and NJA references that look authoritative and are wrong. For a law student that is worse than useless — it is actively harmful (Principle VIII: honest failure over confident fiction). So all three new zones carry an explicit instruction to the model: **do not invent statutes or case-law references.**

## Clarifications

### Session 2026-06-03

- Q: The lowercase-ASCII slugs (Rust identifier / serde rename / filesystem suffix) for the three zones? → A: **`identifiera`** (Identifiera rättsfrågorna), **`strukturera`** (Strukturera (IRAC)), **`forklara`** (Förklara begreppen) — verb-stem slugs consistent with the existing `sammanfatta`/`anonymisera`/`forenkla`/`generera`.
- Q: Do any of the three carry a `disclaimer_paragraph`? → A: **All three do** — a short Swedish "granska …" disclaimer (humanizer-reviewed), because issue-spotting, IRAC labelling, and term definitions all involve fallible model judgment in a high-stakes study context. Consistent with the existing Anonymisera/Förenkla/Generera disclaimers (Principle VIII).
- Q: Window size for the new fourth grid row? → A: **Increase the window height** so the full 3×4 grid is visible at launch without scrolling (target ≈1000px from 760). The exact height (and whether `minHeight` changes) is set by the BLOCKING `frontend-design` review before the layout edit.
- Q: The Swedish IRAC section headings for Strukturera, in order? → A: **Rättsfråga → Gällande rätt → Subsumtion → Slutsats** (the standard Swedish IRAC mapping of Issue → Rule → Application → Conclusion).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Identifiera rättsfrågorna (issue-spotting) (Priority: P1)

A student drops a case PM or an old exam question onto **Identifiera rättsfrågorna**. The zone produces a list of the legal questions (rättsfrågor) the material raises — the issues to be resolved — without answering them and without citing any statute or case. A sidecar file appears next to the original and opens automatically, exactly like every other zone.

**Why this priority**: Issue-spotting is the first skill taught in Swedish legal education and the most reusable; it is the clearest standalone value of the three.

**Independent Test**: Drop a fixture document on the zone (mock model returning a Swedish rättsfråge-list) → a sidecar with the zone's suffix appears, mirrors the input format, contains the listed issues, contains no fabricated SFS/NJA reference, and the source file is untouched.

**Acceptance Scenarios**:

1. **Given** a dropped case/PM document, **When** the zone runs, **Then** a sidecar opens listing the legal issues as a list, the source is unchanged, and the output format mirrors the input (e.g. `.docx → .docx`, `.txt → .txt`).
2. **Given** the model's output, **When** the sidecar is produced, **Then** it does not contain a fabricated statute/case citation (the system prompt instructs against it).

### User Story 2 - Strukturera (IRAC) (Priority: P2)

A student drops their own draft answer onto **Strukturera (IRAC)**. The zone reshapes that text into the four IRAC sections in Swedish — Rättsfråga, Gällande rätt, Subsumtion, Slutsats — reorganising the student's own reasoning under those headings. It does not add new legal content or citations.

**Why this priority**: High pedagogical value but narrower input (a draft answer, not any document); depends on the same pipeline as US1.

**Independent Test**: Drop a fixture answer (mock model returning IRAC-headed Swedish) → sidecar contains the four Swedish IRAC section headings in order, mirrors input format, source untouched, no fabricated citation.

**Acceptance Scenarios**:

1. **Given** a dropped draft answer, **When** the zone runs, **Then** the sidecar presents the four IRAC sections (Rättsfråga → Gällande rätt → Subsumtion → Slutsats) in that order.
2. **Given** the output, **Then** it reorganises the dropped text and introduces no fabricated statute/case reference.

### User Story 3 - Förklara begreppen (explain the terms) (Priority: P3)

A student drops a dense judgment or doctrine excerpt onto **Förklara begreppen**. The zone extracts the legal terms/jargon that appear in the document and gives each a short plain-Swedish explanation (term → explanation), so the student can read the original. Definitions are general plain-language, not citations.

**Why this priority**: Valuable comprehension aid; lowest priority only because issue-spotting and IRAC are more central to graded work.

**Independent Test**: Drop a fixture with legal jargon (mock model returning term→definition pairs) → sidecar lists terms with plain-Swedish explanations, mirrors input format, source untouched, no fabricated citation.

**Acceptance Scenarios**:

1. **Given** a dropped document containing legal terminology, **When** the zone runs, **Then** the sidecar pairs each extracted term with a plain-Swedish explanation.
2. **Given** the output, **Then** explanations are plain-language and contain no fabricated statute/case reference.

### Edge Cases

- **All twelve zones must remain visible at launch.** Adding a fourth row to the grid must not push zones below the fold at the default window size — the window grows so the full 3×4 grid shows without scrolling (the layout decision is confirmed via the `frontend-design` skill before implementation).
- **A document with no identifiable issues / no jargon / not an answer**: the zone still produces an honest best-effort sidecar (or the model returns little) — it never crashes and never fabricates content to fill space. Existing empty/short-output handling applies unchanged.
- **The model tries to cite a statute anyway**: the system prompt forbids it, but the spec does not claim a hard guarantee the model never emits a reference — the requirement is that the *prompt instructs against it* and the zone-pipeline test asserts the fixture/mock output is citation-free. (No new runtime citation-stripping filter is in scope.)
- **Cross-language drift**: the three new zones must appear, with identical identity (slug/title/hints/help), in BOTH the Rust source of truth and the TypeScript frontend — enforced by the existing drift fixtures/tests (which will fail until all sides agree on twelve zones).
- **Input format coverage**: the three zones accept the same input formats as every other transform zone (`.docx`/`.pdf`/`.txt`/`.md`/`.rtf`/`.odt`) and mirror the output format, with no new format handling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST add exactly three new drop zones — Identifiera rättsfrågorna, Strukturera (IRAC), Förklara begreppen — bringing the total from nine to twelve, each appearing in the zone grid in a defined order.
- **FR-002**: Each new zone MUST process **only the dropped document's content** through the existing local-only pipeline (drop → local Ollama → sidecar next to the original that opens automatically). No new outbound network call, no new integration (Principle I).
- **FR-003**: Each new zone's system prompt MUST instruct the model, in Swedish, to (a) output only the requested result with no meta-preamble, and (b) **not invent or cite statutes (lagrum/SFS) or case law (rättsfall/NJA)**. The "no fabricated citations" instruction is the Principle-VIII guard that distinguishes these from a (rejected) citation zone.
- **FR-004**: **Identifiera rättsfrågorna** MUST produce a list of the legal questions/issues the dropped document raises, without answering them.
- **FR-005**: **Strukturera (IRAC)** MUST reshape the dropped text into four Swedish-headed sections in order: Rättsfråga, Gällande rätt, Subsumtion, Slutsats.
- **FR-006**: **Förklara begreppen** MUST extract legal terms appearing in the dropped document and give each a short plain-Swedish explanation.
- **FR-007**: Each new zone MUST mirror the input format in its output (same rule as the existing transform zones; no zone is generative like the drafting zone). The three zones accept the existing supported input formats with no new format handling.
- **FR-008**: The three new zones MUST be treated as untrusted **data** (not instructions) by the prompt-assembly layer — wrapped in the document delimiters + anti-injection guard, exactly like the existing transform/extract zones (spec 022). None is an instruction-zone exception.
- **FR-009**: Each new zone MUST have complete, humanizer-reviewed Swedish copy: a title, a drop-zone hint, a processing-hint verb, a help short + long string, and a short "granska …" disclaimer paragraph (all three carry one — Clarifications Q2) — all consistent in voice with the existing zones.
- **FR-010**: The zone identity of all twelve zones (slug, title, hints, help) MUST be identical across the Rust source of truth and the TypeScript frontend, enforced by the existing cross-language drift fixtures/tests.
- **FR-011**: All twelve zones MUST be fully visible at the default window size at launch (no scrolling needed to reach the new fourth row) — the window dimensions adjust to fit the larger grid.
- **FR-012**: The project constitution MUST be updated (version bump + re-enumeration) to reflect twelve zones instead of nine, since it enumerates the zone set as a governing fact. No principle is weakened (all zones share the same local-only pipeline).
- **FR-013**: A citation/lagrum-hunting zone MUST NOT be added; the spec records this rejection and its rationale (local-model citation hallucination harms a law student — Principle VIII).

### Key Entities

- **Drop zone (study-method)**: a themed target that transforms/extracts the dropped document via a per-zone Swedish system prompt and writes a sidecar mirroring the input format. The three new ones are instances of the existing drop-zone concept — no new entity type, no new state machine.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After the change there are exactly **twelve** zones, each independently exercisable: dropping a document on any of the three new zones produces a sidecar (mirroring input format) next to the original that opens automatically — verified by one zone-pipeline integration test per new zone (mock model), each asserting source-unchanged + correct suffix + expected markers.
- **SC-002**: Each new zone's pipeline test asserts the produced sidecar contains **no fabricated statute/case citation** for the citation-free mock output (the Principle-VIII guard is exercised, not merely asserted in prose).
- **SC-003**: All twelve zones are visible without scrolling at the default launch window size (verified visually via the running app and/or a layout assertion; the layout/window decision passes the `frontend-design` review).
- **SC-004**: Zone identity is drift-free across Rust and TypeScript: the cross-language drift tests pass with twelve zones (slugs/titles/hints/help all agree), and the zone-count assertions are updated 9→12 and pass.
- **SC-005**: No new outbound network endpoints, no new dependencies, and no change to the privacy posture — every new zone runs the same local Ollama pipeline (Principle I intact; verified by the existing no-outbound/privacy tests staying green).
- **SC-006**: All new Swedish copy reads as natural Swedish (humanizer-reviewed) and is consistent in voice with the existing zones (verified by the `humanizer` skill pass before shipping).

## Assumptions

- The three zones reuse the **existing** DropZone state machine and dispatch pipeline unchanged (same as the spec-013 zones) — no new states or transitions → `/tla` is out of scope per the light-track triviality gate (the only state machine is the unchanged per-zone idle→processing→success/error one already verified).
- Output mirrors input format for all three (none is generative); they accept the existing input formats with no new parser work.
- The grid component (`lg:grid-cols-3`) renders twelve zones as 3×4 automatically; the only layout change is the **window height** so the fourth row shows — confirmed via `frontend-design` before implementation.
- The constitution bump is **1.1.0 → 1.2.0** (MINOR — material expansion, new zones), mirroring the spec-013 6→9 bump.
- Whether any of the three carries a `disclaimer_paragraph` (the model's issue-spotting / IRAC judgment can be wrong) is decided in `/clarify`; the existing Anonymisera/Förenkla "granska …" disclaimer pattern is available to reuse.
- Slugs are lowercase ASCII (Rust identifier convention, e.g. `kallor` for Källor); the exact three slugs are decided in `/clarify`.
- Light track: spec → `/clarify` → `/allium:elicit` → impl → browser tests (vitest functional coverage + Playwright smoke for the twelve-zone render). Destructive UI tests: the new zones reuse the existing DropZone component and its already-tested destructive behaviours; no new interactive surface is introduced, so the destructive battery is covered by the existing DropZone tests plus the new functional + smoke coverage.
