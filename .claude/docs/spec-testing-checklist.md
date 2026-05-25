# Spec Testing Checklist — Destructive Browser Tests

This checklist MUST be completed for every spec/feature that involves **interactive UI** (forms, user input, state-mutating buttons, multi-step flows, authentication, file uploads, search/filter). Does NOT apply to static pages, landing pages, content display, styling/CSS, i18n/translations, or read-only dashboards. Read `.claude/docs/testing.md` for full details on each attack category.

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

```markdown
## Phase N: Destructive Browser Tests

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

## Minimum requirements

| Feature type              | Min destructive tests | Required categories |
|---------------------------|----------------------|---------------------|
| Simple form               | 8                    | 1, 2, 4, 5         |
| Multi-step flow           | 10                   | 1, 2, 3, 4, 5      |
| Auth-related              | 10                   | 1, 2, 3, 4, 6      |
| Offline/sync              | 15                   | 1-7 (all)           |
| Dashboard/data display    | 8                    | 2, 4, 5, 6          |

## Validation

A spec is NOT complete unless:

1. A "Functional Coverage Tests" phase exists with an inventory of ALL implemented functions
2. Every function in the inventory has at least one browser test
3. A dedicated "Destructive Browser Tests" phase exists AFTER functional coverage
4. Each test has a unique task ID (T0XX)
5. Minimum destructive test count met per feature type
6. All relevant attack categories covered
7. Tests describe what they verify, not just what they do

**The functional coverage check is the most important item.** A spec with 8 destructive tests but only 3 out of 12 functions tested is NOT complete.
