# Testing conventions

## Testing philosophy

Tests are an **insurance policy**, not a checklist. An insurance policy that only covers "the house is still standing" is worthless — it should cover fire, flood, burglary, and the neighbor driving into the wall.

**Every test should try to break the application.**

The starting point is a hostile, unpredictable user who:

- Enters garbage, SQL injections, `<script>` tags, and emoji orgies in every field
- Clicks in the wrong order, double-clicks submit, presses back mid-flow
- Skips mandatory steps and tries to reach the final step directly via URL
- Leaves fields empty, enters 10,000 characters, pastes binary data
- Submits forms before the page has finished loading
- Uses keyboard navigation and tab order no one thought of

If a test only verifies that "the page loads" or "the form submits with valid data" — that test lacks value. Happy path tests are necessary but NOT sufficient.

## General

- All new features must have tests.
- Tests should be isolated and reproducible.
- Naming: `MethodName_Scenario_ExpectedResult` (e.g., `GetUser_WithValidId_ReturnsUser`).

## Test layers — every feature gets ALL of them (not just E2E)

A feature is not covered by destructive E2E tests alone. The mix follows the architecture (pyramid for backend/domain logic, more integration weight for service-heavy code — there's no universal ratio, the shape follows the code), but every behaviour-changing feature carries all three layers:

| Layer | Tool (.NET) | Covers | Rule of thumb |
|---|---|---|---|
| **Unit** | xUnit (+ Moq), FsCheck/CsCheck for wide-input logic | Pure functions, domain rules, validators, mappers, calculations — fast, no I/O | The broad base. Every non-trivial function with a decision in it. |
| **Integration** | xUnit + `WebApplicationFactory` / Testcontainers | API endpoints against a real (test) DB, EF Core queries, middleware, auth, transactions, the wiring between units | **Mandatory** — AI-written code passes unit tests but fails at the seams (this is where the real bugs concentrate). |
| **E2E (destructive)** | Playwright | Full user journeys + the destructive suite below + visual regression | Critical journeys + adversarial input. Thin but vicious. |

Unit + integration are **always required**, not optional extras on top of E2E. Integration tests are the layer AI code most often fails (units pass, the seams don't) — never skip them. Keep the full suite fast enough to run locally in one go (if it creeps past ~5 min you have too many high-level tests — push coverage down the pyramid).

## .NET projects

- Use **xUnit** as test framework.
- Use **Moq** or similar for mocking when needed.
- Separate unit tests in a dedicated project: `<ProjectName>.Tests`.

## UI tests (Playwright)

- Use **Playwright** with **.NET** (Microsoft.Playwright) for UI and end-to-end tests.
- Playwright tests run with **xUnit** as test runner.
- Place UI tests in `<ProjectName>.Tests.UI` or similar.
- UI tests must be green before anything is reported as "done".

## Install Playwright browsers

```bash
pwsh bin/Debug/net*/playwright.ps1 install
```

## Running tests

```bash
# Unit tests
dotnet test

# E2E tests
dotnet test --filter "Category=UI"

# Single test (faster feedback)
dotnet test --filter "FullyQualifiedName~TestClassName.TestMethodName"
```

## Functional coverage (MANDATORY — before destructive tests)

Before writing any destructive tests, you MUST first ensure **every implemented function has at least one browser test**. This is the #1 failure mode: Claude writes tests for 3 out of 12 features and calls it done.

### Step 1: Create a functional inventory

List EVERY user-facing function that was implemented or changed. Put this as a comment block at the top of the test file:

```csharp
// ===== FUNCTIONAL COVERAGE INVENTORY =====
// Every function listed here MUST have at least one browser test.
//
// 1. Search — user can search by keyword, results update live
// 2. Filter by category — dropdown filters results  
// 3. Pagination — navigate between pages
// 4. Sort by column — clicking header sorts asc/desc
// 5. Detail view — clicking item opens detail panel
// 6. Edit inline — double-click to edit in place
// 7. Breadcrumbs — reflect current path, clickable
// ... (list ALL functions, not just the "main" ones)
// =============================================
```

### Step 2: Write one test per function (MINIMUM)

Each inventory item needs at least one test that verifies the function **actually works end-to-end** with realistic data. Not a smoke test. Not "page loads". A test that proves the feature does what it should.

### Step 3: Verify coverage

Count inventory items. Count functional tests. If tests < items, you are NOT done. Move to destructive tests only after 100% functional coverage.

**What counts as a function:** Any user-visible behavior — UI interactions, navigation, data operations (CRUD, filter, sort, search, paginate, export), state changes (loading, error, empty, success), responsive behavior.

## Every interactive function must prove all four states at runtime (MANDATORY)

Functional coverage is not "the happy path renders". For every interactive/async function, a test must observe **all four states actually working** — a missing one is a failed validation, not a cosmetic gap (see `.claude/rules/scenarios.md` → post-implementation validation):

1. **Success** — the action actually happens (submit creates the record; clicking the map fires the pin/sheet/action). Assert the real outcome, not that a function was called.
2. **Error** — a **specific, visible** message. Never silent, never blank, never a raw stack trace. A failed login MUST say *why*. "There must never be a missing error message" is the canonical case.
3. **Empty** — zero results renders a real empty state, not a blank void.
4. **Loading** — feedback during async, and it resolves (no infinite spinner).

And validate the **real behaviour**: a test that asserts on a stub, never invokes the function, or only checks "page loaded" gives false confidence (high coverage, zero bite — the mutation gate is the backstop). Validate critical-path/prerequisite functions FIRST — if login or the primary interaction is broken, everything behind it is untestable, so fix the prerequisite before fanning out to deeper scenarios.

## Destructive browser tests (MANDATORY)

Every spec/feature involving **interactive UI** MUST include destructive Playwright tests AFTER functional coverage is complete. These tests should actively try to break the application.

**Interactive UI** = forms, user input, buttons that mutate state, multi-step flows, authentication, file uploads, modals with user actions, search/filter, drag-and-drop, real-time updates. Static pages, landing pages, content display, styling/CSS, i18n/translations, layout changes, and read-only dashboards do NOT require destructive tests.

Destructive tests without functional coverage are worthless — you're stress-testing a building where half the rooms were never inspected.

### How many destructive tests? Derive the count from the input domain — do NOT staple a constant to every function

There is no magic number. A flat "N per function" over-tests a toggle and under-tests a 12-field wizard — the count must scale with how much surface each function actually exposes. Derive it the way ISTQB does, per function:

1. **Equivalence partitioning** — one destructive test per *invalid* input class. A status toggle has ~1 invalid class; an email+password+date form has many.
2. **Boundary value analysis** — ISTQB 3-value BVA: for each boundary, test the value plus both neighbours (so ~2-3 boundary tests per bounded field).
3. **Cross-cutting attack scenarios** — the order/race/skip-step/auth/accessibility categories below that apply *regardless* of input count (double-submit, back-button, direct-URL, tab-order…).

Sum those three and you get a count that fits the function. As a sanity-check floor (the real reason a minimum exists at all is to fight the well-documented *positive-test bias* — developers naturally under-write negatives; the one solid empirical figure is Infosys' ~29%-of-tests-but-71%-of-defects result):

| Function shape | Destructive floor (guide, not gate) |
|---|---|
| Trivial interactive — toggle, single non-input button, pure navigation | **2-3** (mostly order/race + a11y; almost no input partitions) |
| Simple form — 1-3 input fields | **~6-10** (a handful of invalid partitions + boundaries) |
| Moderate form / filterable dashboard — 4-8 fields | **~12-20** (partitions multiply across fields) |
| Multi-step flow / auth / money / state machine | **~20-30+** (add skip-step, order, race on top of per-field partitions) |
| Offline/sync | the relevant tier **+** the offline/sync category |

The old flat "8" survives only as roughly the *simple-form* case — it was never a universal constant. **The count is a floor and a guide. It is NOT the definition of done.** The actual quality gate is the mutation kill rate (see below): a function can have 30 destructive tests that all pass and still let a flipped `>`/`<` through. Count proves tests *exist*; mutation score proves they *bite*.

### Attack categories — every UI spec should cover ALL relevant categories

#### 1. Invalid input (Garbage In)

- Empty fields — submit form without filling in anything
- Extremely long input — 10,000+ characters in text fields, 999999999 in number fields
- Unicode/emoji — `💩🍆👻`, Chinese characters, Arabic (RTL), zero-width spaces (`\u200B`)
- Special characters — `<script>alert('xss')</script>`, `'; DROP TABLE users;--`, `../../../etc/passwd`
- Negative numbers, decimals with comma and period, dates in wrong format
- HTML in text fields — `<b>bold</b>`, `<img src=x onerror=alert(1)>`
- Whitespace-only input — only spaces, only tabs, only newlines

#### 2. Wrong order and unexpected behavior

- Double-click the submit button quickly (should not create duplicate records)
- Press back (browser back) mid-flow in a multi-step process and then forward again
- Navigate directly to step 3 via URL without going through steps 1-2
- Refresh the page mid-form — is state preserved?
- Open the same view in two tabs and submit in both

#### 3. Skip steps

- Try to reach a protected page without being logged in
- Call API endpoints directly without going through the UI
- Skip mandatory fields by manipulating the DOM (remove `required` attribute)
- Submit form via the JavaScript console

#### 4. Boundary values and edge cases

- Exactly at max length, exactly one character over max length
- Fields with only spaces (should not be accepted as valid input)
- Dates: February 31, January 1 year 0000, dates far in the future
- Negative numbers where only positive are expected
- Empty list/zero results — what does the UI look like?

#### 5. Timing and race conditions

- Click buttons before the page has finished loading
- Submit form multiple times quickly in succession
- Abort an ongoing operation (navigate away mid-save)

#### 6. Accessibility and keyboard

- Tab through all form elements — is the order logical?
- Enter in text field — does it trigger submit?
- Escape — does it close modals/dialogs?

### Naming of destructive tests

Use prefixes that clearly show the test is destructive:

```csharp
SubmitForm_WithEmptyRequiredFields_ShowsValidationErrors
SubmitForm_WithXssPayload_SanitizesInput
SubmitForm_DoubleClick_CreatesOnlyOneRecord
Checkout_NavigateDirectlyToStep3_RedirectsToStep1
LoginForm_With10000CharacterPassword_ShowsError
UserProfile_WithUnicodeEmoji_DisplaysCorrectly
```

### Test structure per spec

Every spec involving UI should have tests in this order:

1. **Functional inventory** — list ALL implemented functions in a comment block
2. **Functional tests** (1 per function, MINIMUM) — verify each function works end-to-end
3. Then, **for EACH interactive function**, a destructive suite sized to that function's input domain (see "How many destructive tests?" above), spanning the relevant attack categories:
   - **Invalid input** — one test per invalid equivalence class (garbage, empty, extreme, injection)
   - **Boundary values** — 3-value BVA per bounded field (value + both neighbours)
   - **Wrong order / race** — double-click, back button, URL jumping, rapid re-submit
   - **Skip steps / security** — XSS, injection, unauthorized access, DOM tampering
   - **Accessibility** — tab order, Enter-to-submit, Escape-closes-modal

The minimum is **1 functional test per implemented function** plus a per-function destructive floor scaled to its shape (trivial ~3 → multi-step/auth ~20-30+). Don't pad a toggle to hit a quota and don't stop a wizard at 8.

## Property-based tests (RECOMMENDED — the rung between example tests and TLA+)

For logic with a wide input space, hand-picked example tests sample a few points and miss the rest. Property-based testing (PBT) asserts an *invariant* and lets the framework generate hundreds of inputs (including the nasty boundaries it shrinks toward). It's the broadly-adopted "semi-formal" middle ground — lighter than TLA+, far stronger than a dozen `[Theory]` rows — and combined PBT + example testing measurably out-detects either alone.

- **.NET:** **FsCheck** (`FsCheck.Xunit`, callable from C#) or **CsCheck** (C#-native, less ceremony). Wire into the existing xUnit project.
- Best ROI on: parsers / serializers (round-trip: `parse(render(x)) == x`), money & date math, sorting/dedup/merge, any pure function with algebraic invariants, and stateful models (CsCheck/FsCheck command-based testing).
- **Recommended, not blocking.** Inventing a meaningful property is real work — apply PBT where the input space is wide and the invariant is clear; skip it where example tests already pin the behaviour.

## Visual regression tests (REQUIRED for UI — AI writes code, not pixels)

Functional and destructive tests pass while the page still looks broken: AI reasons over code tokens, not rendered output, so it ships wrong spacing, dead design tokens, and collapsed responsive layouts that no `getByRole` assertion catches. Screenshot baselines close that gap and Playwright does it natively — no new infra, **local-only** (respects `github-actions.md` CI-minimalism).

```csharp
// Baseline the key states of each screen (default, empty, error, loaded, dark mode, mobile width)
await Expect(Page).ToHaveScreenshotAsync("dashboard-default.png");
await Page.SetViewportSizeAsync(375, 812);
await Expect(Page).ToHaveScreenshotAsync("dashboard-mobile.png");
```

- Capture the *states that matter* (empty / loading / error / loaded, plus dark mode and one mobile width), not every pixel of every page.
- First run writes baselines (`--update-snapshots`); commit them. Later runs diff against them and fail on drift.
- Update baselines **deliberately** when a design change is intended — a baseline update is a reviewable diff, never an automatic overwrite.
- For component-level isolation (fewer false positives on churny output) a Storybook + Chromatic setup is the heavier alternative; default to Playwright screenshots first.

## Mutation testing (THE quality gate — replaces "count the tests" as proof of done)

Line coverage proves a line *executed*; it says nothing about whether a test would *notice* if that line were wrong. Mutation testing injects deliberate bugs (flip `>` to `>=`, `&&` to `||`, delete a statement) and checks your tests kill them. The kill rate is the only metric that measures whether tests actually bite — Google, Meta, and AWS all converge on this over coverage %.

- **.NET:** **Stryker.NET** — `dotnet tool install -g dotnet-stryker`, run `dotnet stryker`.
- **NEVER in CI per push** (see `github-actions.md` — it's minutes-expensive and was a budget incident). Run it **nightly or on-demand**, and incrementally (changed files) on a branch.
- **Thresholds:** `break: 60, low: 60, high: 80`. Target **~80% kill on critical modules** (auth, money, state machines, parsers). Don't chase 100% — the last 20% buys fragile tests for vanishing return.
- Flaky tests poison the score (a flaky test "survives" mutants at random) — stabilize flakiness first.

## Verification order

Before anything is declared "done":

1. `dotnet build` — no compilation errors
2. `dotnet test` — all unit tests pass (incl. any property-based tests)
3. `dotnet test --filter "Category=UI"` — all E2E tests pass (functional + destructive + visual-regression)
4. `dotnet stryker` on the changed critical module(s) — **nightly/on-demand, never in per-push CI** — kill rate ≥ target (80% on critical modules). This is the gate that proves the tests above actually catch bugs.

## Native window smoke (spec 037 — macOS XCUITest, OPT-IN ONLY)

The only suite that drives the REAL built `.app` (real WKWebView, real IPC,
real `NSOpenPanel`). Local-only by register amendment — deliberately absent
from `npm test`, `cargo test`, Playwright, and CI (github-actions budget rule).

```bash
scripts/native-smoke.sh              # build-if-stale → mock → XCUITest → clean
scripts/native-smoke.sh --probe-only # just the a11y exposure probe (test00)
```

- Hermetic: the app launches against `scripts/mock-ollama.py` via the
  debug-only seam (env + `/tmp/juradrop-ollama-url-override` file channel);
  a green run REQUIRES the mock to have served the generation (tripwire).
- CRITICAL: tests launch the app by exact bundle URL — NEVER by bundle id
  (LaunchServices resolves the id to an installed release copy in
  /Applications, which has no seam and talks to a real Ollama).
- Cadence: run when native wiring changes (drop/pick paths, window config,
  IPC surface) or before a release. Needs a GUI session + a one-time
  macOS automation permission grant (the runner's preflight explains).
