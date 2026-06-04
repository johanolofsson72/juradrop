# Research: Privacy Visibility (spec 042)

## R1 — Where the single source of truth for the claims lives

**Decision**: a new `src/lib/privacy-facts.ts` exporting the fact base: `PRIVACY_BADGE_TEXT` (one line), `PRIVACY_NEVER_LEAVES` (documents/instructions/results), `PRIVACY_NETWORK_USES` (the two honest exceptions). The help-entry body quotes these facts; the wizard strings stay in their own spec-008 fixture system but are pinned by the same vocabulary tests.

**Rationale**: SC-004 demands automated fact consistency. Four hand-written strings drift; one module + derived strings cannot. The wizard strings cannot move into this module without breaking the established spec-008 fixture machinery — pinning them by test instead keeps one mechanism per surface while still enforcing the contract.

**Alternatives**: (1) a JSON fixture like the help mirror — overkill: no Rust side needs the badge text (the badge is frontend-only; only the help entry crosses into zone_help.rs, which has its own mirror). (2) Free-floating strings with only review discipline — that is exactly how "din Mac"/"din dator" drift happened between specs 008 and 041.

## R2 — Badge copy shape (input to the humanizer gate)

**Decision (draft, humanizer-gated at impl)**: `"Dina dokument bearbetas på din dator och lämnar den aldrig."` — subject = the user's documents (the thing Meja worried about), verb = where the work happens, claim = scoped to user content (FR-003 honest scoping; the model download/updater are not contradicted).

**Rationale**: one sentence, no marketing, answers "var bearbetas dokumentet?" verbatim. Avoids "AI:n" personification (the established artifact-describing voice) and avoids "ingenting lämnar din dator" which, read literally, the updater check falsifies.

**Alternatives**: "Allt sker lokalt" — vague, "allt" overclaims; "Ingen molntjänst används" — true but negative-definition framing explains nothing to a 19-year-old.

## R3 — Window-fit arithmetic (FR-011)

**Decision**: a single `text-xs` line (≈16 px + margin ≈ 20–24 px total) appended inside the existing `gap-4` column.

**Rationale**: the 1000 px window currently holds: p-6 padding (48), pt-12 offset (48), WelcomeCard (≈0 when null at klar — it returns null in ready state), instruction field (≈44 + 16 gap), 4 grid rows (4 × ≈152 + 3 × 12 gaps ≈ 644). Total ≈ 800–850 px in the ready state — ≈150 px of slack. A 24 px line fits with margin to spare. (WelcomeCard renders only pre-ready; during the wizard the grid — and badge — are absent, so the tall path never stacks.)

**Alternatives**: fixed-position window footer — fights the auto-updater footnote overlay (spec 007 owns bottom-right); inside the grid section as a 13th cell — semantically wrong and breaks the 12-divides-evenly layout from 036.

## R4 — Wizard strings: which sides exist

**Decision**: update `src/lib/wizard-strings.ts` + `src-tauri/tests/fixtures/wizard-strings.json` together (the documented byte-for-byte pair); grep for any Rust-side const mirroring the fixture at impl time and update it too if found. Only `welcome_paragraph` and `welcome_privacy_line` change; `welcome_download_note` is kept verbatim (already states one-time download + offline-after).

**Rationale**: smallest honest diff; the download note is already the best line in the app for US2 and re-wording reviewed copy without cause is churn. The two amended strings fix the vocabulary (canonical "din dator") and widen the never-leaves scope to match 041's instruction field ("dokument, instruktioner och resultat").

## R5 — Help entry mechanism

**Decision**: clone the 041 `_instruction_help` pattern exactly: `PRIVACY_HELP_TITLE`/`PRIVACY_HELP_BODY` consts in zone_help.rs, `_privacy_help` fixture key, `PRIVACY_HELP` export in help-strings.ts, sibling `<section data-privacy-help>` in HelpPanel rendered after the instruction entry, drift assertions added beside the existing `instruction_help_matches_fixture` tests on both sides.

**Rationale**: the mechanism is one spec old, proven, and the drift tests are already structured for additional chrome entries.

## R6 — How to test "visible in 100% of UI states" (SC-001)

**Decision**: Playwright drives the mocked bridge: ready state → assert badge; emit processing/error/success snapshots on a zone → assert badge unchanged; open help panel and settings panel → badge still in DOM (panels are right-edge slide-ins with scrim — the badge may be covered by the scrim, which is acceptable: the claim is about the main window surface, panels are transient). Window-fit: assert badge bounding box bottom ≤ viewport height at the default 1160×1000 viewport.

**Rationale**: maps each FR-002 state word to one cheap assertion against the existing e2e harness.

## R7 — Overclaim guard patterns (SC-004 test shape)

**Decision**: vitest pins on the fact module + wizard strings + help body: (a) every machine reference uses "din dator" (regex `/din dator/`, and `/din Mac/` absent from in-app strings); (b) no string matches overclaim patterns (`/aldrig.*internet/i`, `/utan internetåtkomst/` used as an absolute app-level claim) — EXCEPT the download note's "efter det fungerar allt utan nät", which is a scoped, true claim (offline-capable after download) and is allowlisted explicitly with a comment; (c) the help body contains both "modell" + "uppdater" references (the two network uses).

**Rationale**: turns the honesty contract into failing tests instead of review vigilance. The explicit allowlist forces every future absolute-sounding phrase through a conscious decision.
