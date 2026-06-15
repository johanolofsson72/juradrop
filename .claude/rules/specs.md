---
paths:
  - "**/spec*.md"
  - "**/tasks*.md"
  - "**/plan*.md"
  - "**/feature*.md"
  - "**/.specify/**"
  - "**/specs/**"
---

# Spec and task rules (Allium + destructive browser/native E2E tests + TLA+)

> **Native-app note (React Native / Expo · Flutter).** This rule says "browser tests" throughout because it was written for web/.NET. On a native mobile app there is no browser — read every "browser test" / "destructive browser test" here as its native equivalent: a **component/widget test** (React Native Testing Library or Flutter `WidgetTester`) for functional coverage, or a **native E2E flow** (Maestro for RN; Patrol / `integration_test` for Flutter) for the destructive suite. The pipeline (spec → clarify → allium → plan → tasks → analyze → implement → tests → tla), the functional-inventory requirement, and the destructive attack categories all apply identically — only the test tooling differs. **Mobile parity is exact: the destructive suite runs as native E2E flows (Maestro for RN, Patrol for Flutter), not widget tests, and is sized per interactive function (not per spec), exactly as web sizes its Playwright destructive suite per function.** The mobile attack categories (lifecycle/background, process kill, hardware back, permissions, offline) live in `.claude/docs/spec-testing-checklist-mobile.md`, installed as the canonical `spec-testing-checklist.md` on mobile projects.

## Spec triage — pick the right pipeline (READ FIRST)

Not every spec needs the full pipeline. Classify the spec **before** Phase A and pick the matching track:

| Spec shape | Pipeline |
|---|---|
| **Behavior-changing** — new feature, new entity, new state machine, new actor, new concurrency, new API surface | **Full pipeline:** spec → `/speckit-clarify` → `/allium:elicit` → impl → browser tests → `/tla` |
| **UI feature, single actor, no concurrency** — CRUD form, search/filter, simple workflow with linear state | **Light pipeline:** spec → `/speckit-clarify` → `/allium:elicit` → impl → browser tests (skip `/tla` unless state machine is non-trivial — see TLA+ skill triviality gate) |
| **Non-behavior** — pure refactor, doc change, dependency bump, config tweak, cosmetic UI change, i18n, logging/observability only | **Spec only.** spec → `/speckit-clarify` → impl. No `.allium`, no `/tla`. Browser tests still apply if the user-facing surface changes. |
| **Fix / hardening / security** with no new entities AND no new state transitions | **Spec only.** spec → `/speckit-clarify` → impl. Express the constraint as a test, not as an Allium invariant. If the fix introduces a new invariant or state, escalate to behavior-changing. |

`/speckit-clarify` runs on every track immediately after `/speckit-specify` (auto-pick recommended via the settings.json hook). Skipping it is the canonical pipeline failure mode and is forbidden — see `feature-pipeline.md`.

**When in doubt, ask once with `AskUserQuestion`.** Do not default to "full pipeline" — over-applying Allium produces fabricated `.allium` files that then show up as false drift in `/tla` and chew through the per-finding decision protocol for no gain.

## Spec creation flow

After triage, follow the matching track:

### Phase A: Write the spec (all tracks)
1. **Update the scenario map** — add this feature's actors and scenarios (happy / edge / adversarial / error / offline) to `specs/SCENARIOS.md`. If the map is missing or this behaviour isn't in it, run the scenario interview per `.claude/rules/scenarios.md` BEFORE writing the spec — a missed user-case here becomes a hole in the code later. The map is the source the inventory and destructive suite derive from.
2. **Read `.claude/docs/testing.md`** — test layers (unit + integration + E2E always), risk-tiered destructive sizing, PBT, VRT, and the mutation-kill gate.
3. **Read `.claude/docs/spec-testing-checklist.md`** — attack categories checklist.
4. Write the spec with destructive browser tests included (if interactive UI applies), referencing the SC-ids from the scenario map.

### Phase B: Sharpen with Allium (full / light pipelines only — BLOCKING for those)
4. **Run `/allium:elicit`** on the spec to produce a formal `.allium` specification.
   - Allium refuses vague requirements and forces precision on entities, rules, and invariants.
   - The `.allium` file MUST be saved alongside the spec (same directory).
   - This creates the baseline for drift detection after implementation.
5. **For full/light pipelines: a spec without a corresponding `.allium` file is NOT complete.** Do not proceed to implementation.
6. **For spec-only track: Phase B is skipped entirely.** No `.allium` file is required and none should be created. Do not ask Claude to elicit one anyway.

## Requirements for every spec/task file with INTERACTIVE UI

Every spec involving **interactive UI** MUST include a dedicated phase/section for destructive browser tests.

**Interactive UI means:** forms, user input fields, buttons that mutate state, multi-step flows, authentication, file uploads, modals with user actions, search/filter, drag-and-drop, real-time updates.

**NOT interactive UI (skip destructive tests):** static pages, landing pages, content display, styling/CSS changes, i18n/translations, layout adjustments, read-only dashboards without filters, error pages, marketing pages.

When browser tests apply, include TWO phases:

### Functional coverage (PHASE 1 — before destructive tests)

- **List EVERY implemented function** in a functional inventory (the happy-path rows of the scenario map)
- **At least 1 browser test per function** — if you built 12 functions, write 12 functional tests
- Testing 3 out of 12 functions is the #1 failure mode — this is NOT acceptable

### Destructive tests (PHASE 2 — after functional coverage)

- **Each interactive UI function gets its own destructive suite, sized to its input domain — NOT a flat count for the whole spec.** Derive the count per function (ISTQB equivalence partitioning + boundary-value analysis + applicable cross-cutting categories): a toggle lands at ~2-3, a simple form ~6-10, a multi-step/auth flow ~20-30+. See `.claude/docs/testing.md` → "How many destructive tests?" for the floor table. The count is a floor and a guide; **the actual gate is the mutation kill rate** (Stryker, nightly/on-demand, ~80% on critical modules) — a function can have 30 passing destructive tests and still let a flipped operator through. Sizing per function (not a single number per spec) is the discipline this rule enforces.
- **All 6 attack categories** should be represented per function (if relevant):
  1. Invalid input (garbage, XSS, SQL injection, emoji, extreme length)
  2. Wrong order (double-click, browser back, URL jumping, refresh mid-flow)
  3. Skip steps (direct URL, API without UI, DOM manipulation)
  4. Boundary values (max length, empty lists, invalid dates)
  5. Timing/race conditions (click before load, rapid double submit)
  6. Accessibility (tab order, Enter, Escape)

- If features involve **offline/sync**: add additional destructive scenarios:
  - Browser closes mid-autosave/sync
  - Network drops mid-operation
  - Conflict between sessions/devices
  - Token expiry during offline
  - Retry after error state

## Validation

Before a spec/task file is considered complete, verify:

- [ ] Are this spec's scenarios in `specs/SCENARIOS.md` (happy / edge / adversarial / error), with SC-ids the spec references?
- [ ] Is there a "Functional Coverage Tests" phase listing ALL implemented functions?
- [ ] Does every function in the inventory have at least one browser test?
- [ ] Are there **unit AND integration tests** for the behaviour (not just E2E)? Integration is the layer AI code most often fails.
- [ ] Is there a "Destructive Browser Tests" phase AFTER functional coverage?
- [ ] Is each interactive function's destructive suite **sized to its input domain** (equivalence partitions + boundaries + applicable categories), not a flat quota?
- [ ] Do the scenarios cover all relevant attack categories?
- [ ] If logic has a wide input space: is there a **property-based test**? If it's UI: are there **visual-regression baselines** for the key states?
- [ ] If offline/sync: are there additional edge case tests?
- [ ] Does every test scenario have a clear task ID and description?
- [ ] **For full/light tracks only: has `/allium:elicit` been run and a `.allium` file saved alongside the spec?** (Skip this check for the spec-only track.)

If any of these are missing — **the spec is NOT complete**. Do not proceed to implementation.

## Post-implementation: Drift detection + formal verification

After implementation is complete AND browser tests are written:

1. **Run `/tla`** — this automatically:
   - Runs `/allium:distill` on the implemented code to extract what was actually built
   - Compares distilled spec against the `.allium` from pre-implementation (drift detection)
   - Extracts TLA+ invariants and models the state machine
   - Cross-references invariants with browser tests for coverage gaps
2. Any **spec drift** or **TLA+ gaps** MUST be addressed before the feature is considered done
3. This step is auto-triggered after browser tests are written — no manual trigger needed

### The full pipeline

```
Scenario map (SCENARIOS.md) → Spec (markdown) → /speckit-clarify → /allium:elicit → .allium spec →
Implementation → Tests (unit + integration + PBT where apt) →
Browser/native E2E (functional + risk-tiered destructive + visual regression) →
Mutation gate (nightly/on-demand) → /tla (distill + drift + invariants) → Done
```
