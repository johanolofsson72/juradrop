# Feature Specification: Anonymisera PII-residue sweep

**Feature Branch**: `main` (solo direct-push)
**Created**: 2026-05-29
**Status**: Draft
**Track**: Full pipeline (new behavior + new entity + output-side privacy invariant → `.allium` + `/tla`).

**Input**: After the Anonymisera zone produces its model output, run a deterministic regex sweep over that OUTPUT to detect personal data the model failed to redact (personnummer, e-post, telefonnummer). If any residue is found, prepend a Swedish warning paragraph to the sidecar listing the counts per category, so the student is told — in writing, in the file — that automatic anonymisation may have missed something. This is an output-side safety net for the highest-stakes zone: a missed personnummer in the *output* is a privacy leak, the exact thing JuraDrop exists to prevent.

## Why this spec exists

Anonymisera is LLM-only today. Its single safeguard is a static disclaimer paragraph that says "AI-anonymisering är inte hundra procent — granska resultatet". That disclaimer is always the same whether the model did a perfect job or left three personnummer in. A deterministic post-process sweep turns "trust the model, always" into "verify the model, every time" — and tells the user *specifically* what to re-check.

The sweep is intentionally NOT a fixer. It does not edit the model output (that risks corrupting legitimate text and gives false confidence). It detects and reports. The human decides.

## What's IN scope

| Item | Type |
|---|---|
| New `pii_sweep` module: `scan_residual_pii(&str) -> PiiFindings` | Code |
| Detect personnummer, e-post, telefonnummer in text | Code |
| Wire the sweep into the Anonymisera write path only | Code |
| Conditional Swedish warning paragraph in the sidecar when residue found | Code |
| `regex` promoted to a direct dep (already transitive — net new deps: 0) | Dep |
| Unit tests for each pattern (positive + negative) + integration test through the pipeline | Test |

## What's OUT of scope

| Item | Reason |
|---|---|
| Auto-editing/re-redacting the output | Deliberate — detection only; editing risks corrupting text + false confidence |
| Running the sweep on other zones | Kontakter's job is to extract contacts (PII in output is intentional); other zones don't claim to remove PII |
| Names/addresses detection | Names + free-form addresses have no deterministic pattern; regex would be noise. Personnummer/e-post/telefon are structured + high-signal. Names stay the model's job + the disclaimer. |
| Blocking the write on residue | The sidecar is still written (the partial anonymisation is still useful); the warning is informational |

## Clarifications

### Session 2026-05-29 (auto-picked)

- Q: Detect-only or auto-redact the residue? → A: **Detect-only.** Editing model output deterministically risks corrupting legitimate text (e.g. a case number that looks like a personnummer) and gives false "now it's clean" confidence. Report counts; the human re-checks.
- Q: Which PII categories? → A: **Personnummer, e-post, telefonnummer** — the three with reliable deterministic patterns. Names + addresses are excluded (no deterministic pattern; would produce noise). The existing static disclaimer still covers the model's name/address work.
- Q: Where does the warning go in the sidecar? → A: **A paragraph prepended above the existing disclaimer**, only when residue count > 0. Format: `⚠️ Automatisk kontroll hittade möjlig kvarvarande information: N personnummer, M e-postadresser, K telefonnummer. Granska och ta bort manuellt.` Categories with zero count are omitted from the sentence.
- Q: Personnummer pattern strictness? → A: **Shape-based, not Luhn-validated.** Match `(YY)YYMMDD[-+]?NNNN` shape. Validating the Luhn checksum would miss deliberately-fake test numbers AND real numbers the model paraphrased; shape-matching errs toward over-warning, which is the safe direction for a privacy net.
- Q: Should the sweep run on the input too (to size the problem)? → A: **Output only.** The input is the user's own confidential document — they already know it has PII; that's why they used Anonymisera. The contract is about what leaked into the *result*.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — A missed personnummer is surfaced (Priority: P1)

A student anonymises a client memo. The model replaces two of three personnummer but misses one. The sidecar opens with a warning: "⚠️ Automatisk kontroll hittade möjlig kvarvarande information: 1 personnummer. Granska och ta bort manuellt."

**Independent Test**: `cargo test --test zone_pipeline_anonymisera` — a fixture/mock where the model output retains `19010101-0101` produces a sidecar whose text contains the warning paragraph with "1 personnummer".

**Acceptance Scenarios**:
1. **Given** anonymised output containing `19850101-1234`, **When** the sweep runs, **Then** the sidecar contains the warning naming 1 personnummer.
2. **Given** output containing `anna@example.se` and `070-123 45 67`, **When** the sweep runs, **Then** the warning names 1 e-postadress and 1 telefonnummer.
3. **Given** fully-clean output (all placeholders, no residue), **When** the sweep runs, **Then** NO warning paragraph is added — only the existing static disclaimer.

### Edge Cases

- **False positives:** a case number like `T 4521-25` must NOT match the personnummer pattern (wrong shape: too few digits). A year range `2015–2020` must not match.
- **Placeholders are not residue:** `[Personnr 1]` must NOT count as a personnummer.
- **The warning is itself Swedish** and runs through humanizer.
- **Idempotent counts:** the same number appearing twice counts as 2 occurrences (the user must remove both).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A new module `src-tauri/src/zones/pii_sweep.rs` MUST expose `scan_residual_pii(text: &str) -> PiiFindings` where `PiiFindings { personnummer: usize, email: usize, phone: usize }`.
- **FR-002**: Personnummer detection MUST match the shape `(\d{2})?\d{6}[-+]?\d{4}` with word boundaries, counting occurrences. Shape-based, no Luhn check (Clarification Q4).
- **FR-003**: E-post detection MUST match a standard email shape (`\b[\w.+-]+@[\w-]+\.[\w.-]+\b`).
- **FR-004**: Telefonnummer detection MUST match Swedish forms: `0` + 1–3 digit area + 5–8 digits with optional spaces/dashes, OR `+46` international form. Conservative to limit false positives.
- **FR-005**: Placeholders `[Personnr N]`, `[Adress N]`, `[Person N]`, `[Telefon N]`, `[E-post N]` MUST NOT be counted as residue.
- **FR-006**: The sweep MUST run ONLY for `ZoneId::Anonymisera`, ONLY on the model output text, after generation and before/at sidecar write.
- **FR-007**: When total residue count > 0, a Swedish warning paragraph MUST appear in the sidecar as the first body paragraph (immediately following the static disclaimer block). **REFINED 2026-05-29:** the warning is prepended to the output body in the dispatcher — NOT threaded into each format writer's header — so it appears uniformly across `.docx`/`.txt`/`.md` outputs (Anonymisera mirrors its input format). For `.docx` the static disclaimer lives in the header block, so "first body paragraph" is the position directly after it. Categories with zero count are omitted from the sentence. Copy via humanizer.
- **FR-008**: When residue count is 0, the sidecar MUST be byte-identical to today's output (no warning paragraph). No behavior change on the clean path.
- **FR-009**: The warning copy MUST live in the cross-language drift fixture (`zone-error-strings.json` lineage or a new `pii-sweep-strings.json`) if it has a user-facing string template, OR be a pinned Rust constant tested against a fixture.
- **FR-010**: `regex` MUST be a direct dependency (already transitive; net new deps: 0). No new outbound surface (Principle I unaffected — pure local string scan).

### Key Entities

- **PiiFindings**: value object — counts of personnummer / email / phone found in a text. `total()` helper. `is_clean()` = total == 0.

## Success Criteria *(mandatory)*

- **SC-001**: Anonymisera output with a residual personnummer yields a sidecar warning naming it. Verified by integration test.
- **SC-002**: Clean Anonymisera output yields no warning (byte-identical to pre-014 on the clean path). Verified by test.
- **SC-003**: Known false positives (case numbers `T NNNN-NN`, year ranges, placeholders) do NOT trigger warnings. Verified by unit tests.
- **SC-004**: Net new deps: 0 (regex already in lock). Telemetry denylist still green.
- **SC-005**: The sweep adds < 5ms for a 24,000-char document (the truncation cap). Verified by a timing-bounded unit test (or asserted structurally — regex is linear).

## Assumptions

- Shape-based personnummer matching over-warns rather than under-warns; for a privacy net that's the correct error direction.
- The warning strengthens, never weakens, Principle I — it's a pure local computation, no outbound traffic.
- Names/addresses remain the model's responsibility + the static disclaimer; deterministic detection of them is out of scope.
