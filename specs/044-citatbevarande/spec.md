# Feature Specification: Citatbevarande (deterministic quote preservation in translation)

**Feature Branch**: `044-citatbevarande`

**Created**: 2026-06-05

**Status**: Draft

**Track**: light (new deterministic transform step, no new UI, no new zone states)

**Input**: Field finding (Johan, manual testing 2026-06-05): the instruction "behåll citaten på svenska" is empirically beyond gemma3:4b AND 12b as model behavior (7 prompt variants, 0 obedience — lab + field confirmed). But it is trivial as STRUCTURE: mask quoted spans to placeholders before the model, restore the originals after — the model cannot translate what it never sees. Reuses the proven spec-039 pre-replace/post-restore architecture.

## Clarifications

### Session 2026-06-05

- Q: What activates quote masking? → A: Deterministic phrase detection — the normalized per-drop instruction contains the substring "behåll citat" (case-insensitive, covers "behåll citaten", "behåll citaten på svenska") AND the zone is a translation zone (Till engelska / Till svenska). No NLP, no model judgment, no new UI; the rule is documented in the instruction help. Auto-picked recommended.
- Q: Which quote styles count as a citation? → A: Balanced pairs of Swedish/typographic and straight double quotes: `”…”`, `“…”`, `"…"`, `»…«`/`»…»` — with a per-span length cap (a "quote" longer than 1 000 chars is treated as unbalanced punctuation and left untouched rather than masking half the document). Auto-picked recommended.
- Q: What if the model damages or drops a placeholder? → A: Restoration is best-effort per placeholder: every `[CITAT N]` found in the output is replaced with its original span (including quote marks); placeholders the model destroyed are simply absent from the output (the surrounding translation stands). Both translation prompts gain an unconditional one-line "reproduce [CITAT N] markers exactly" guard (the spec-039 placeholder-preservation pattern, which the models demonstrably obey). Auto-picked recommended.

## User Scenarios & Testing

### US1 — The quotes survive translation, guaranteed (P1)

Johan writes "behåll citaten på svenska" in the instruction field and drops a Swedish contract with three quoted passages on Till engelska. The body comes back in English; the three quoted passages are character-identical to the source — not because the model behaved, but because it never saw them.

**Acceptance Scenarios**:

1. **Given** the instruction "behåll citaten på svenska" and a document with quoted spans, **When** dropped on Till engelska, **Then** every model request contains `[CITAT N]` placeholders instead of the quoted text, and the sidecar contains the original quoted spans character-identically.
2. **Given** the same document WITHOUT the trigger phrase in the instruction (empty field, or an unrelated instruction), **Then** behavior is byte-identical to today — everything translates, no placeholders anywhere.
3. **Given** the trigger phrase but a non-translation zone (e.g. Sammanfatta), **Then** no masking occurs (the instruction still rides the trusted slot as plain guidance).

### US2 — Long documents keep the guarantee (P2)

A long quoted-rich document chunks into several parts. Masking happens on the whole text BEFORE chunking (global placeholder indices — the spec-039 lesson), restoration on the full combined output. No chunk boundary can split the guarantee.

**Acceptance**: a multi-chunk run with quotes in different chunks restores all of them; placeholder numbering is globally consistent.

### Edge Cases

- Unbalanced quote marks (an opening `”` with no closer) → nothing masked for that mark; the document translates as today. No error.
- A quoted span longer than the cap → left unmasked (treated as suspect balance), documented behavior.
- Nested or adjacent quotes (`”a” och ”b”`) → two spans, two placeholders.
- The document already contains literal `[CITAT 1]` text → masking still works: restoration only replaces placeholders the masker ISSUED (collision-safe numbering continues past any pre-existing markers is NOT attempted — instead the pre-existing literal is left alone and the masker starts numbering above any collision, or uses an occurrence-bound replace; the implementation must be collision-deterministic and tested).
- Empty quote `””` → masked and restored like any span (degenerate but harmless).
- Instruction "översätt även citaten" → does NOT contain "behåll citat" → no masking (correct: the user asked the opposite).
- Quotes containing PII → irrelevant interplay: masking applies only to translation zones; the 039 scrub applies only to Anonymisera. Disjoint by construction.

## Requirements

- **FR-001**: When the normalized instruction contains "behåll citat" (case-insensitive) and the zone is Till engelska or Till svenska, all balanced quoted spans (per the clarified mark set, ≤ 1 000 chars each) MUST be replaced by `[CITAT N]` placeholders before the model sees the text, and the original spans restored verbatim (marks included) in the final output.
- **FR-002**: Masking MUST run on the whole extracted text before chunking; restoration on the full combined output (global indices).
- **FR-003**: Without the trigger (phrase absent, or non-translation zone), prompt and output MUST be byte-identical to current behavior.
- **FR-004**: Both translation system prompts MUST gain an unconditional one-line instruction to reproduce `[CITAT N]` markers exactly (inert when no markers exist).
- **FR-005**: Restoration is per-placeholder best-effort; destroyed placeholders simply vanish — no error state, no partial-failure UI.
- **FR-006**: The span registry (original quote texts) lives only on the call stack for the run — never logged, never persisted (the 039 no-log discipline; quotes are document content).
- **FR-007**: The instruction help entry MUST document the trigger phrase and the guarantee (humanizer-gated copy; three-way mirror).
- **FR-008**: TESTMANUS step 2's keep-quotes case is promoted from "known limitation" back to a testable PASS criterion.
- **FR-009**: Collision handling for pre-existing literal `[CITAT N]` text in documents MUST be deterministic and tested (no misrestoration).

## Success Criteria

- **SC-001**: With the trigger, 100% of balanced quoted spans in test fixtures survive translation character-identically (integration-proven against mocks; real-model-proven in the gated suite).
- **SC-002**: Without the trigger, assembled prompts and outputs are byte-identical to pre-044 (existing suites pass unchanged).
- **SC-003**: Multi-chunk runs restore quotes across chunk boundaries with globally consistent numbering.
- **SC-004**: The quote registry appears in no log and no file other than the output document (static invariant, 039 pattern).
- **SC-005**: Johan's exact field case (avtal-med-citat.txt + "behåll citaten på svenska" på Till engelska) passes in the real-model manus suite: all three Swedish quotes verbatim in the English output.

## Assumptions

- Trigger-phrase detection is deliberately humble: one documented Swedish phrase, no synonyms ("bevara citaten" does NOT trigger v1 — the help text teaches the phrase). Extensible later if field data demands.
- The placeholder format `[CITAT N]` mirrors `[Personnr N]` — the models' demonstrated ability to preserve that shape (039) is the load-bearing precedent.
- No new UI: the existing instruction field is the surface; the help entry is the documentation.
- `/tla` skipped per triviality gate expectation (pure transformation, no new states) — same call as 039/040.
