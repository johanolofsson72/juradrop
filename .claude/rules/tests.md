---
paths:
  - "**/*Test*.cs"
  - "**/*test*.ts"
  - "**/*test*.tsx"
  - "**/*spec*.ts"
  - "**/*spec*.tsx"
  - "**/*.Tests*/**"
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/tests/**"
  - "**/e2e/**"
  - "**/playwright/**"
---

# Browser/E2E test rules — functional coverage FIRST, then destruction

> **Native-app note (React Native / Expo · Flutter).** This rule is worded for the browser/.NET case (Playwright, `.cs` examples). A native app has no browser — read every "browser test" here as a **component/widget test** (React Native Testing Library, or Flutter `WidgetTester`) **or native E2E flow** (Maestro for RN; Patrol / `integration_test` for Flutter), and every `dotnet test --filter "Category=UI"` as `npm test` + `maestro test` (RN) or `flutter test` + `patrol test` (Flutter). The discipline is identical and fully transfers: build a functional inventory, write at least one test per function, THEN destructive tests. The native attack categories (lifecycle/background, process kill, hardware back, permissions, offline) live in `.claude/docs/testing-mobile.md` and `.claude/docs/spec-testing-checklist-mobile.md` (installed as the canonical `testing.md`/`spec-testing-checklist.md` on mobile projects per sync-prompt Step 7c).

## The #1 failure mode (STOP AND READ THIS)

The most common mistake is writing tests for 20% of the features and calling it done. If you built search, filtering, pagination, breadcrumbs, tree view, sorting, and bulk actions — **every single one of those needs at least one browser test that verifies it works**. Not just search. Not just the "main" feature. ALL of them.

A test suite that covers 3 out of 12 implemented features is NOT a test suite. It's a liability.

## Mandatory workflow when writing browser tests

### Step 1: Functional inventory (BLOCKING — do this FIRST)

Before writing a single test, create a comment block listing EVERY user-facing function that was implemented or changed. This is not optional. The list IS the happy-path rows of the scenario map (`specs/SCENARIOS.md`) — if a function you built isn't in the map, you found a scenario gap: stop and run the scenario interview (`.claude/rules/scenarios.md`) before testing.

```csharp
// ===== FUNCTIONAL COVERAGE INVENTORY =====
// Every function listed here MUST have at least one browser test.
//
// 1. Search — user can search by keyword, results update live
// 2. Filter by category — dropdown filters results
// 3. Filter by date range — date picker narrows results
// 4. Sort by column — clicking column header sorts asc/desc
// 5. Pagination — navigate between pages, page size selector
// 6. Breadcrumbs — reflect current navigation path, clickable
// 7. Tree view toggle — expand/collapse sidebar tree
// 8. Bulk select — checkbox to select multiple items
// 9. Bulk delete — delete selected items with confirmation
// 10. Detail view — clicking item shows detail panel
// 11. Edit inline — double-click to edit field in place
// 12. Export CSV — download filtered results as CSV
// =============================================
```

### Step 2: Functional tests (one per inventory item, MINIMUM)

Write at least one test per inventory item that verifies the function **actually works end-to-end**. These are NOT happy-path-only — they should use realistic data and verify the outcome.

### Step 3: Destructive tests (per .claude/docs/testing.md)

AFTER functional coverage is complete, add a destructive suite **per interactive function, sized to its input domain** (equivalence partitions + boundary values + applicable attack categories — a toggle ~3, a multi-step/auth flow ~20-30+; not a flat quota). Destructive tests without functional coverage are worthless — you're stress-testing a building where half the rooms were never inspected.

### Don't forget the other layers

E2E destructive tests are the top of the pyramid, not the whole of it. Every behaviour-changing feature also needs **unit + integration tests** (integration is where AI-written code most often breaks — units pass, the seams don't), and **property-based tests** for wide-input logic, **visual-regression baselines** for UI. The **mutation kill rate** (Stryker, nightly/on-demand) — not the test count — is the real proof the suite bites. See `.claude/docs/testing.md`.

## Coverage check before declaring done

Count your inventory items. Count your functional tests. If functional tests < inventory items, you are NOT done. Every gap is a function that has zero test coverage. Then confirm the mutation kill rate on the changed critical module(s) meets target — a green suite that kills no mutants is not coverage, it's theatre.

## What counts as a "function"

Any user-visible behavior that was implemented or modified:
- UI interactions (click, type, select, drag, toggle)
- Navigation (routes, breadcrumbs, back button, deep links)
- Data operations (CRUD, filter, sort, search, paginate, export)
- State changes (loading states, error states, empty states, success feedback)
- Responsive behavior (mobile menu, collapsible panels)

If the user can see it or interact with it, it needs a test.
