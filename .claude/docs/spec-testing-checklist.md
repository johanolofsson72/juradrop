# Spec Testing Checklist — Destructive Browser Tests

This checklist MUST be completed for every spec/feature that involves **interactive UI** (forms, user input, state-mutating buttons, multi-step flows, authentication, file uploads, search/filter). Does NOT apply to static pages, landing pages, content display, styling/CSS, i18n/translations, or read-only dashboards. Read `.claude/docs/testing.md` for full details on each attack category.

> **Scenarios come from the living scenario map.** The functional inventory below is derived from the `happy` rows of `specs/SCENARIOS.md`, and the destructive suite from its `edge` / `adversarial` / `error` / `offline` rows (see `.claude/rules/scenarios.md`). If a function or destructive case here has no matching `SC-id`, the scenario was never mapped — add it (or run the scenario interview) before writing the test.

## When to use

- Writing a new spec (`spec.md`, `spec-*.md`)
- Writing task breakdowns (`tasks.md`, `tasks-*.md`)
- Writing implementation plans (`plan.md`, `plan-*.md`)
- Reviewing existing specs for completeness

## Mandatory structure in task files

Every task file with UI features MUST include TWO dedicated test phases: functional coverage FIRST, then destructive tests. The #1 failure mode is testing 3 out of 12 features and calling it done.

### Phase N-1: Functional Coverage Tests (BEFORE destructive tests)

```markdown
## Phase N-1: Functional Coverage Tests

### Functional inventory (list ALL implemented functions)
- [ ] T0XX: [Function 1] — e.g., Search by keyword updates results live
- [ ] T0XX: [Function 2] — e.g., Filter by category narrows displayed items
- [ ] T0XX: [Function 3] — e.g., Sort by column header toggles asc/desc
- [ ] T0XX: [Function 4] — e.g., Pagination navigates between result pages
- [ ] T0XX: [Function 5] — e.g., Breadcrumbs reflect path and are clickable
- [ ] T0XX: [Function 6] — e.g., Detail view opens on item click
- [ ] T0XX: [Function N] — ... (continue until ALL functions are listed)

Every function above MUST have at least one browser test that verifies it works end-to-end. If you implemented 12 functions, you need at least 12 functional tests. No exceptions.
```

### Phase N: Destructive Browser Tests

> **The destructive suite is sized PER interactive UI function, not per spec.** Each function in the inventory above gets its own destructive suite spanning the relevant attack categories — but the *size* of that suite is derived from the function's input domain, not from a flat constant. Per function, the count is `(one test per invalid equivalence class) + (3-value boundary-value analysis per bounded field) + (applicable cross-cutting attack scenarios)`. A status toggle lands around 2-3; a 12-field wizard lands at 20-30+ (see the floor table below). The block below is the template for ONE function — repeat it for every interactive function and prune/expand each category to fit that function's domain. A single number covering the whole spec is NOT compliant; neither is padding a toggle to a quota nor stopping a wizard short.

```markdown
## Phase N: Destructive Browser Tests — Function: [Function 1] (repeat this whole block per interactive function)

### Category 1: Invalid Input (Garbage In)
- [ ] T0XX: Empty required fields — submit form with all required fields empty, verify validation errors
- [ ] T0XX: XSS payload — inject `<script>alert('xss')</script>` in text fields, verify sanitization
- [ ] T0XX: Extreme length — paste 10,000+ characters in text fields, verify truncation or error
- [ ] T0XX: Unicode/emoji — enter `💩🍆👻`, RTL text, zero-width spaces, verify correct display

### Category 2: Wrong Order / Unexpected Behavior
- [ ] T0XX: Double-click submit — rapid double-click on submit button, verify only one record created
- [ ] T0XX: Browser back mid-flow — navigate back during multi-step flow, verify state preserved
- [ ] T0XX: Direct URL to protected step — navigate directly to step 3 without completing step 1-2

### Category 3: Skip Steps
- [ ] T0XX: Unauthenticated access — access protected page without login, verify redirect
- [ ] T0XX: DOM manipulation — remove `required` attribute via DevTools, submit form

### Category 4: Boundary Values
- [ ] T0XX: Max length boundary — input exactly at max length and one character over
- [ ] T0XX: Whitespace-only — fields with only spaces should not pass validation
- [ ] T0XX: Empty state — verify UI handles zero results gracefully

### Category 5: Timing / Race Conditions
- [ ] T0XX: Click before load — interact with UI elements before page fully loads
- [ ] T0XX: Rapid repeated submit — submit form 5 times in quick succession

### Category 6: Accessibility / Keyboard
- [ ] T0XX: Tab order — verify logical tab order through all form elements
- [ ] T0XX: Escape closes modals — verify Escape key closes dialogs/modals
```

## Extra categories for offline/sync features

If the spec involves offline functionality, service workers, or data synchronization, add:

```markdown
### Category 7: Offline / Sync Destruction
- [ ] T0XX: Browser close mid-autosave — close browser during autosave, reopen, verify data preserved
- [ ] T0XX: Browser close mid-sync — close browser during sync push, verify outbox not corrupted
- [ ] T0XX: Network drop mid-push — disable network during sync, verify retry and error state
- [ ] T0XX: Conflict scenario — edit same record in two sessions, verify conflict resolution UI
- [ ] T0XX: Token expiry — expire JWT during offline, trigger sync, verify silent refresh or login dialog
- [ ] T0XX: Retry after error — verify manual retry button works after sync failure
- [ ] T0XX: Storage quota — simulate IndexedDB quota exceeded, verify graceful degradation
- [ ] T0XX: Multi-device — same record edited on two devices, verify UUID-based conflict handling
```

## Sizing the destructive suite (per interactive function, input-domain-derived)

**The size is decided PER interactive UI function, NOT per spec — but it is derived from each function's input domain, not stapled on as a constant.** For every function in the inventory, the destructive count is:

```
(one test per invalid equivalence class)
  + (3-value boundary-value analysis per bounded field — value + both neighbours)
  + (applicable cross-cutting attack scenarios — order/race/skip-step/auth/a11y that apply regardless of field count)
```

A status toggle has ~1 invalid class and no bounded fields, so it lands low; an email + password + date form multiplies partitions and boundaries across three fields, so it lands high. The table below is a **floor and a guide — a sanity check, not a gate.** Its only job is to fight the well-documented positive-test bias (developers under-write negatives). The "Required categories" column still tells you which attack categories apply to each shape — that part is load-bearing.

| Function shape (per interactive function) | Destructive floor (guide, not gate) | Required categories |
|---|---|---|
| Trivial interactive — toggle, single non-input button, pure navigation | **~2-3** (mostly order/race + a11y; almost no input partitions) | 2, 5, 6 |
| Simple form — 1-3 input fields | **~6-10** (a handful of invalid partitions + boundaries) | 1, 2, 4, 5 |
| Moderate form / filterable dashboard — 4-8 fields | **~12-20** (partitions multiply across fields) | 1, 2, 4, 5, 6 |
| Multi-step flow / auth / money / state machine | **~20-30+** (add skip-step, order, race on top of per-field partitions) | 1, 2, 3, 4, 5, 6 |
| Offline/sync | the matching tier above **+** the offline/sync category | tier's categories + 7 |

Do not pad a toggle to hit a number, and do not stop a wizard at the simple-form floor. The old flat "8" survives only as roughly the simple-form case — it was never a universal constant.

### The real gate is mutation kill rate, not the count

The destructive count is a **floor to fight positive-test bias** — it proves the negative tests *exist*. It is NOT the definition of done. The actual quality gate is the **mutation kill rate** (Stryker.NET, run nightly / on-demand per `github-actions.md`, target **~80% on critical modules** — auth, money, state machines, parsers). A function can have 30 green destructive tests and still let a flipped `>`/`<` through; the count says tests exist, the mutation score says they *bite*. A spec that hits its count but whose tests don't kill mutants is NOT done.

## Validation

A spec is NOT complete unless:

1. A "Functional Coverage Tests" phase exists with an inventory of ALL implemented functions
2. Every function in the inventory has at least one browser test
3. A dedicated "Destructive Browser Tests" phase exists AFTER functional coverage
4. Each test has a unique task ID (T0XX)
5. The destructive suite **per interactive function** is sized to its input domain (equivalence partitions + boundaries + applicable categories), not a flat quota — sized individually per function, NOT a single number for the whole spec
6. All relevant attack categories covered per function
7. Tests describe what they verify, not just what they do

**The functional coverage check is the most important item.** A spec with a destructive suite but only 3 out of 12 functions tested is NOT complete — and a single destructive block covering the whole spec is itself non-compliant: each interactive function gets its own suite, sized to its own input domain. And remember the count is only the floor: the actual gate is the mutation kill rate (~80% on critical modules) — a spec that hits its counts but whose tests don't kill mutants is NOT done.
