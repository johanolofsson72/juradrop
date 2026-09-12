# Spec register rule (per-project register, one-stop-per-spec)

Every project maintains a **spec register** at `specs/INDEX.md` — a numbered, ordered list of the specs planned for the project. The register is the source of truth for what to build, in what order, and how far the project has progressed.

This rule defines how Claude reads, executes, and updates the register. It interacts with `.claude/rules/feature-pipeline.md` (which defines the per-spec pipeline) and `.claude/rules/continuous-execution.md` (which forbids stopping inside a spec). Together they form: **continuous within a spec, one stop between specs.**

## The contract (BLOCKING)

When `specs/INDEX.md` exists in a project:

1. **Read the register first — targeted, not whole.** Before doing any feature work, identify the next unchecked spec. The SessionStart orientation hook already prints the next row, so on a fresh session you usually need no read at all. When you must open `specs/INDEX.md`, read only the `## Specs` list — **do not** load the `## Register history` section or `INDEX.history.md` into context; they are an audit trail, never an input to the current spec. On a large register, `grep -nE '^- \[[ /!]\]' specs/INDEX.md | head` finds the next row without swallowing the file. See **Keep the register lean** below.
2. **Run the full pipeline for that one spec, end-to-end.** Triage per `specs.md`, run `/speckit-specify`, `/speckit-clarify` (all tracks, auto-pick), `/allium:elicit` if applicable, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze` (auto-apply), `/speckit-implement`, browser tests (functional + destructive), `/tla` if applicable. No stops between phases — this is one task per `continuous-execution.md`.
3. **Commit and push to `main` directly.** Per `project_workflow` memory (solo, direct-push, no PRs), each spec finishes with `git add` + `git commit` + `git push origin main`. No feature branches, no merge step.
4. **Tick the register.** Mark the spec as `[x]` in `specs/INDEX.md` and commit + push the register update along with (or immediately after) the spec's final commit.
5. **Stop with a status summary.** This is the **only** legitimate stop between specs. The summary follows the template in this rule. The user resumes the next spec when ready.

Specs run **one at a time per lane**. Claude does not chain multiple specs in a single execution unless the user explicitly says so ("run specs 003 and 004 back to back", "do the whole register in one go"). The default is one spec per run.

## Two lanes (owner tags — only when a project runs more than one developer)

The default is one lane, and on a one-lane project nothing below applies. **When a project does run two developers against the same register**, a row may carry an **owner**: a trailing `@name` tag, last on the line.

```
- [ ] 004 — properties — full track — own object model, the upstream feed … — @alex
- [ ] 017 — mfa — full track [hardened] — two-factor, platform admins first … — @sam
- [ ] 009 — public-site — full track [hardened] — the agency's own website …
```

Each machine names its own lane in `.claude/settings.local.json` (gitignored, per machine):

```json
{ "env": { "SPEC_OWNER": "sam", "CLAUDE_TEMPLATE_AUTOSYNC": "0" } }
```

**Template sync belongs to one machine.** `template-autosync-hook.sh` fires at every session start and, when the template has moved, syncs the config, commits it and pushes to the current branch. With two developers that becomes duplicate config commits and a push from whichever session opened first. The second lane sets `CLAUDE_TEMPLATE_AUTOSYNC=0`; the owning machine keeps it on and the change reaches the other lane the normal way, by pulling.

**Three hooks read it** — `spec-register-orientation`, `pipeline-state-guard`, `spec-interview-guard` — and they resolve "the active spec" identically, in this priority: **my in-progress row → my next row → an unowned in-progress row → the next unowned row.** Two guards that disagree about which spec a developer is on would block work for opposite reasons, so if you change the resolution in one, change it in all three.

- **A row assigned to me beats an unowned row higher up the register.** The order is dependency-driven, so the top of the shared tail is usually blocked behind the *other* lane's current row. Without this, the second developer is pointed straight at a spec they cannot start.
- **Unowned rows stay visible in both lanes.** The bulk of a register needs no tags; tag a row when someone actually takes it.
- **With `SPEC_OWNER` unset, everything behaves exactly as it did with one developer.** The lane logic is additive — it never changes single-lane behaviour, which is why it ships enabled and costs one-lane projects nothing.
- **Ordering still rules inside a lane.** Parallel work needs two rows that do not depend on each other; on a dependency-ordered register those are rare and usually live in the tail. Working a tail row early is a deliberate, recorded exception (a Register history line), not a reordering of everything in front of it.
- **The other lane's row is not yours to tick, start, or renumber.** A register-rewrite proposal that touches the other developer's in-flight row is a conversation with the user first.

**A held row (`- [!]`) is never offered as the active row.** Held means somebody stopped for a reason the register cannot express as a dependency, and pointing a fresh session at it is how that decision gets quietly overruled by a banner. The two PreToolUse guards already match only `- [/]` and `- [ ]`; the orientation hook was the one out of step, and now matches them.

## The register format

`specs/INDEX.md` looks like this:

```markdown
# Spec register

Order of execution. Tick when done. Append new specs to the end unless renumbering is justified.

## Specs

- [x] 001 — user-auth — full track [hardened] — short one-line goal
- [x] 002 — profile-page — light track — short one-line goal
- [ ] 003 — search — full track — short one-line goal
- [ ] 004 — admin-dashboard — full track — short one-line goal
- [ ] 005 — billing-integration — full track [hardened] — short one-line goal
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after spec 005

## Register history (newest first)

(Append a line every time the register is rewritten or reordered. Date + reason.)

- 2026-05-14 — initial register, 5 specs identified during project kickoff
```

Each row carries:
- **Order number** (`001`, `002`, ...) — pad to 3 digits for sort stability.
- **Slug** (`user-auth`, `search`) — kebab-case, matches the spec folder name (`.specify/specs/003-search/` or `specs/003-search/spec.md`, depending on project layout).
- **Pipeline track** (`full`, `light`, `spec-only`) — triage per `.claude/rules/specs.md`. Recorded here so the track is visible at a glance. Append the **`[hardened]`** tag (e.g. `full track [hardened]`) when the spec crosses a risk threshold per `.claude/rules/spec-hardening.md` (auth / payments / PII / upload / new external surface, full-track state machine, large surface, or an explicit author call). The tag is load-bearing: it forces the four hardening additions (threat model, expanded destructive + stress, hard mutation gate, adversarial review) and triggers the SessionStart `/clear` banner.
- **One-line goal** — what this spec accomplishes. Not the full requirement — that lives in the spec itself.

**Checkpoint rows** (`integration-hardening — checkpoint`) are not specs — they are the cross-spec hardening pass per `.claude/rules/spec-hardening.md`. Insert one after every 5th completed spec (`H1`, `H2`, … as the id), before the next feature spec. They are worked, ticked, committed, and pushed exactly like a spec row, and they produce a status summary before the per-row stop.

Status markers:
- `- [ ]` — not started
- `- [/]` — in progress (only one spec carries this at a time)
- `- [x]` — done, committed, pushed
- `- [!]` — blocked or needs register rewrite (Claude sets this when surfacing a register-rewrite proposal)

## Keep the register lean (BLOCKING — context-cost hygiene)

The register is read (and often re-read) on essentially every spec. If it balloons, every spec pays for it. A 60-spec register with a paragraph of history per spec becomes tens of thousands of tokens that buy nothing — the live rows are all the pipeline needs; the history is an audit trail nobody reads in-flight. Keep it small:

- **History entries are ONE line each.** `- YYYY-MM-DD — <one sentence>`. Not a paragraph. Not a retrospective. If a spec needs more explanation, that belongs in the spec's own `plan.md` / commit message, not the register. Writing a paragraph-long history entry is the self-reinforcing cost that this rule exists to stop — you write it once and then re-read it on every subsequent spec.
- **And that is now measured: 300 bytes per entry that stays inline.** `scripts/archive-spec-history.sh` enforces it (`--max-bytes N`, `0` disables); an over-budget entry is named with its line, date and size and the run exits 4 — a report about what is still there, not a refusal to write, so the archiving still completes. The budget is the measurable floor under "one sentence", not a replacement for it: an entry can be over budget while being one very long sentence, and 400 bytes costs 400 bytes either way. 300 is the smallest round number above the 95th percentile of the entries across this project's history files that already comply. **Archived entries are exempt** — `INDEX.history.md` is never read during the pipeline, which is the whole reason it exists. Until spec 007bt nothing measured this at all: `--keep` counts entries, and a one-line markdown bullet has no length limit, so a 2,925-byte entry satisfied "ONE line each" by the letter while being a paragraph by every other measure.
- **Cap inline history at ~5 entries; archive the rest.** When `## Register history` grows past ~5 entries, move the older ones to `specs/INDEX.history.md` (a sibling file that is **never** read during the pipeline). Run `scripts/archive-spec-history.sh` — it does this mechanically and reversibly (`--keep 5` by default, `--dry-run` to preview). The live `INDEX.md` keeps only the current spec rows + the last handful of history lines.
- **Declare which end of the history section is the newest.** Write the heading as `## Register history (newest first)` — or `(newest last)` if the register appends at the bottom. Which end holds the newest entry is what decides which end gets archived, and getting it backwards moves the entry most likely to be read next into the file the pipeline never reads, while reporting that it kept the newest inline. Until row H7bb the archiver inferred this from one comparison (first entry's date greater than the last entry's), which is false whenever every inline entry shares a date — an ordinary state on a register that closes several rows in a day, and the state this project's own register was in when the defect was found. The archiver now takes the declaration when there is one, infers from the date trend only when that trend is decisive (at least twice as much evidence one way as the other), and otherwise **moves nothing and exits 5** rather than guessing. There is deliberately no default: measured across 46 history sections, 21 are newest-first and 3 are newest-last, so a silent default would archive the newest entries in those three.
- **Never load the history section as pipeline input.** When you read the register to find the next row, read the `## Specs` list only. `INDEX.history.md` exists so it can be consulted *deliberately* (an audit question), not swallowed by default.
- **A row is 300 bytes, and the same 300 as a history entry.** The history budget above caps an
  entry; this caps a **row**, and rows are where the bytes actually are. Measured on this project
  2026-08-29, after `archive-spec-history.sh` had done its job: 36,521 of 39,950 bytes — **91.4%** —
  were the 106 spec rows, against 1,918 for the whole history section. `scripts/archive-completed-rows.sh`
  reports every row over `--max-bytes` (default 300, `0` disables). The number is calibrated the same
  way 007bt calibrated the history one: across the 78 rows that already complied, p95 was 265 and the
  maximum 293, so 300 is the smallest round number that admits every compliant row. That it matches
  the history budget is two independent measurements landing on the same figure, which is convenient
  — one number for "a line in the register" — but it was derived, not copied.

- **A row is a pointer; the diagnosis lives in one of two archives.** Completed rows keep a one-line
  goal, with the row verbatim as it read at tick time in `specs/INDEX.completed.md`. A row that is
  **not started** keeps a pointer, with its diagnosis in `specs/INDEX.pending.md`. Neither file is
  pipeline input; each is read deliberately, by the one spec that needs it.

  This is not the same trade as history, and the difference is why the row still has to say
  something. A history entry is an audit trail nobody's next action depends on. A row is the
  **handoff** — the SessionStart banner prints it, and for a defect row it is often all a fresh
  session sees before deciding what to build. What makes the budget affordable is that the two costs
  fall on different readers: *every* spec pays for a long row, *one* spec reads it. So a row must
  stay a self-sufficient pointer — what is wrong, where, and which archive holds the rest — never
  "fix the thing".

  A row for unstarted work is long for an honest reason: the finding was understood the moment it
  was surfaced, and the spec directory that would hold it does not exist until someone starts. That
  is the correct instinct meeting a missing container. `INDEX.pending.md` is the container; its entry
  moves to `INDEX.completed.md` when the spec is ticked.

- **Preserve first, shorten second.** A row may only be shortened once its long form is in an
  archive. This is the one operation here that can destroy understanding, and it is exactly what a
  hurried pass would do — so `archive-completed-rows.sh` labels every over-budget row either
  `shortenable` (its diagnosis is preserved) or `archive first`. Run it when you tick a row, not as
  a cleanup someday: the archive was built by hand on 2026-08-22 and again on 2026-08-25, and then
  nobody remembered, so twenty ticked rows sat inline at full length — 35% of the file — as debt the
  project already knew how to pay. A mechanism that depends on memory is a mechanism with an expiry
  date.

- **Never pick a row id by eye.** `bash scripts/next-register-id.sh` returns the next free one
  (`--count N`, `--alpha S`, `--checkpoint`). An id is a permanent handle: `spec_active.py` resolves
  it, both PreToolUse guards glob `specs/<id>-*` from it, and the archiver keys on it. Reading a
  150-row register and guessing is a coin toss — three colliding ids were picked by hand on
  2026-09-03 alone, each caught by `validate-register-ids.sh` and each costing a commit, a renumber
  and a second push. The allocator appends past the highest id in the register AND in every
  `INDEX*.md` archive beside it, so it cannot collide with a row that has already been moved out.

- **Ticking a row is an Edit, not a rewrite.** Change `- [ ]` to `- [x]` on the one row with a surgical `Edit`; do not read-and-rewrite the whole register to tick one box.
- **A tick is refused while the project owes the template CORE work.** `scripts/core-owed-tick-guard-hook.sh` (layer 3 under Enforcement below) checks that at the moment of the tick and denies it if `--owed` or `--unlisted` has anything to say. If you meet that deny, the fix is to land the change in the template and sync it back — not to reach for the override.

## Failure memory across `/clear` (`<spec-dir>/run-log.md`)

The register says *which* spec is next; the on-disk artifacts (`spec.md`, `spec.allium`, `plan.md`, `tasks.md`) say *which phase* it reached. Neither remembers what went **wrong** getting there — and `.claude/rules/spec-hardening.md` actively tells you to resume big specs in a fresh session, which throws that memory away.

`scripts/spec-run-log-hook.sh` keeps it: one line per event in `<spec-dir>/run-log.md`, appended automatically when a pipeline artifact is written, and manually for anything worth remembering:

```bash
bash scripts/spec-run-log-hook.sh --note "mutation gate FAILED — 41% on AuthService, tests are theatre"
bash scripts/spec-run-log-hook.sh --note "Q7 authz escalated to developer — anonymous search deferred to a later spec"
```

Rules: **one line per entry, never a paragraph** (the same discipline as "Keep the register lean" — this file is read on resume). It is **not** pipeline input and nothing gates on it; the SessionStart hook surfaces only the last 5 lines, and only while the row is `- [/]`. Log the things a fresh session would otherwise rediscover the hard way: failed gates, escalated answers, deferred findings, a phase you had to redo.

## The status summary (the one stop per spec)

When a spec is complete, Claude's stop message uses this exact shape:

```
**Spec NNN — <slug> — DONE**

- Track: <full|light|spec-only>[ +hardened]
- Commits: <count> (last: <short-sha> — "<commit subject>")
- Push: origin/main <short-sha>
- Pipeline: spec → interview (<I> answers, <interview mode>) → <clarify status> → <allium status> → impl → <N> functional + <M> destructive browser tests → <tla status>
- Hardening: <hardening status>
- Open findings: <count> (or "none")
- Maintenance due: <what ticking this row just made stale, or "nothing">

**Next: NNN — <slug>** (or "register complete")

→ Before starting the next spec, run `/clear`. A spec is one self-contained unit of work; carrying this spec's transcript into the next one is the single biggest per-spec token cost (a long unbroken session re-bills the whole growing transcript every turn, and cache expires after ~5 min idle). Fresh context per spec is the cheap default — the register + orientation hook restore all the state the next spec needs.

(Resume when ready.)
```

Fields:
- `<I> answers, <interview mode>` — the count of answered questions recorded in `interview.md` (must be ≥15, target 15–25, per `.claude/rules/spec-interview.md`; the `spec-interview-guard` hook blocks implementation below 15). `<interview mode>` is one of: `auto` (base auto-answered, not flagged) / `auto +N overflow` (flagged large/advanced, N human overflow questions) / `manual` (`SPEC_INTERVIEW_MODE=manual` or a `[interview:manual]` override — fully human).
- `<clarify status>` — `clarify auto-picked N answers` / `clarify clean (no questions raised)` / `clarify deferred N questions to user`
- `<allium status>` — `allium ok` / `allium skipped (spec-only track)` / `allium with N open questions surfaced`
- `<tla status>` — `tla clean` / `tla skipped (spec-only or trivial state)` / `tla with N gaps surfaced`
- `<hardening status>` — `n/a (not a hardened spec)` / `threat-model + stress + mutation-gate + adversarial-review all passed` / `hardened with N findings surfaced` (per `.claude/rules/spec-hardening.md`). For a checkpoint row, this line instead reads `integration checkpoint: regression + security sweep + scenario reconciliation + mutation spot-check — <result>`.
- `Maintenance due` — read from `bash scripts/maintenance-due.sh --brief`, never composed by hand.
  Ticking a row is what makes the whole-project suite stale (one spec) and moves the mutation gate
  toward its cadence (five), so the moment a spec closes is exactly when the developer can decide to
  run it now or leave it for the night. Deferring is safe and explicitly allowed: nothing is cleared
  until the job actually runs, so the next session's banner says so again. This replaces the blind
  nightly cron — a scheduled `project-maintenance.sh --if-due` now exits in a second on a night with
  no work, and a night the laptop sleeps through costs nothing, because the obligation is still
  recorded in the state file rather than in a missed timer.

- If `Open findings` is non-zero, the findings MUST have been surfaced individually per `validation-followup.md` before this status summary is written — the summary cites the count for the audit trail, not as a deferral mechanism.

After printing the summary, Claude stops. No follow-up question like "want me to continue with 004?" — the stop **is** the question.

## Register rewrite exception (the legitimate mid-spec stop)

The only time Claude breaks the one-stop-per-spec pattern is when, while working on spec N, Claude discovers that the register itself is wrong. Examples:

- Spec N+1 depends on infrastructure or behavior that spec N was supposed to provide but the spec text never specified it — both N and N+1 need rewriting.
- Spec N reveals a hidden assumption that invalidates spec N+2 entirely.
- Scope creep during spec N produces work that genuinely belongs in a new spec — the register needs a new row, not silent inclusion.
- The user's project goal has shifted (new info from external source) and the remaining register no longer reflects what they want.

When this happens:

1. **Pause the current spec mid-execution.** Mark it `- [!]` in the register.
2. **Surface the problem with `AskUserQuestion`.** State the conflict in one sentence, cite the source (which spec, which line), and offer concrete register-change options (renumber, split, merge, add, remove, reorder).
3. **Wait for user decision.** The register rewrite is a user-only call — Claude proposes, the user disposes.
4. **Apply the agreed changes** to `specs/INDEX.md`, append a line to the Register history section explaining why, then resume from the appropriate point.

Mid-spec stops that are NOT register rewrites (typos in the spec, small refinements, missing test cases) are not exceptions — those get handled inside the pipeline per existing rules.

## Enforcement (four layers)

The register is enforced deterministically — Claude cannot silently skip it because the hooks fire regardless of conversation state.

1. **SessionStart orientation** (`scripts/spec-register-orientation-hook.sh`) — at every session start, this hook walks up from `$PWD` to the repo root, looks for `specs/INDEX.md`, and emits one of:
   - **Register exists** → a `systemMessage` with totals (done / in-progress / blocked / todo) and the next unchecked row. Claude knows immediately which spec is on deck.
   - **No register, but the project has a language marker** (`package.json`, `*.csproj`, `*.sln`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `composer.json`, `Gemfile`, `build.gradle*`, `pom.xml`, `pubspec.yaml`) → a bootstrap reminder.
   - **No register, no language marker** (template/scratch repo) → silent.

2. **PreToolUse guard** (`scripts/spec-register-guard-hook.sh`) — fires on `Edit`/`Write`/`MultiEdit`. Walks up from the file path to the `.git` boundary, checks for a language marker, and if there is one AND `specs/INDEX.md` is missing AND the file's extension is in the source-code allowlist, returns `permissionDecision: deny` with a bootstrap instruction. Allowed without register: anything under `specs/`, `.claude/**`, `scripts/**`, `README*`, `CHANGELOG*`, `LICENSE*`, `CLAUDE.md`, `.gitignore`, `.env*`, `.editorconfig`, `Dockerfile`, `docker-compose*`, and any non-source-code extension. Source-code extensions blocked: `.cs`, `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py`, `.go`, `.rs`, `.java`, `.rb`, `.php`, `.swift`, `.kt`, `.kts`, `.cpp`, `.cxx`, `.cc`, `.c`, `.h`, `.hpp`, `.hxx`, `.razor`, `.cshtml`, `.vbhtml`, `.vue`, `.svelte`, `.astro`, `.dart`, `.scala`, `.clj`, `.cljs`, `.ex`, `.exs`, `.erl`, `.hrl`, `.fs`, `.fsx`, `.fsi`, `.hs`, `.elm`, `.lua`, `.jl`, `.nim`, `.zig`, `.sh`, `.bash`, `.zsh`, `.pl`, `.pm`.

3. **PreToolUse tick gate** (`scripts/core-owed-tick-guard-hook.sh`) — fires on `Edit`/`Write`/`MultiEdit` against `specs/INDEX.md`, and only when the written bytes introduce a `- [x]`. It asks `scripts/template-autosync.sh` two questions — `--owed` (CORE files whose bytes no longer match the manifest) and `--unlisted` (scripts a CORE file depends on that the template has never shipped) — and denies the tick if either answers. Both questions are local: they read the manifest and the working tree and return before template resolution, so nothing waits on a clone.

   **Why the tick and not the edit.** `core-machinery-guard-hook.sh` already refuses the CORE *edit*, and there is a legitimate way past it, because sometimes the edit is right. What had no gate was the moment the spec declares itself finished. Spec 007bl edited eight CORE files and added nine scripts in one project, landed none of them in the template, and ticked; `[owed]` named the eight for three days, nothing acted, and a later sync reverted the split layout inside the project that had authored it. After the tick the spec is closed and the finding is addressed to nobody — the same failure `CLAUDE.md` records for a diagnosis parked in a `run-log.md`.

   Every other register edit passes: adding a row, marking `- [/]` or `- [!]`, archiving history, fixing prose. Marking a row in progress is what you do *on the way* to landing what is owed, so blocking it would block the repair path. The gate fails **open** on any failure to answer — the opposite of `pipeline-state-guard`, deliberately: that guard protects a process, this one protects a file the template owns, and if the sync is broken there is no sync coming and nothing to protect it from. `ALLOW_TICK_WITH_CORE_OWED=1` is the override, for the case where the tick being made *is* the one that closes the spec landing the work; it announces itself rather than passing quietly. Reached through the shell as well, via the delegate list in `scripts/bash-write-guard-hook.sh` — with the coverage bound that on that route only the path is visible, so it answers about the file rather than about the tick.

4. **This rule file** — auto-loaded each session via `.claude/rules/`. Provides the procedural context the hooks reference.

The walk in these hooks stops at the `.git` boundary so a parent directory's stray language marker (e.g. a `~/package.json` left over from some other project) cannot cause a false positive in an unrelated repo. The template repo itself trips no enforcement because it has no language marker at its `.git` root.

## Bootstrapping the register (new projects)

**On a project that went through `/project-wizard`, the register already exists** — the wizard writes it in Phase 3D-3 from the inception interview, while it still holds the core modules, auth model, and risk surface in context. The steps below are the fallback for a project that never ran the wizard (or ran an older version of it). If you find yourself bootstrapping a register on a project whose wizard ran recently, that is a wizard bug worth reporting, not a routine step.

When a new project starts and `specs/INDEX.md` does not yet exist:

1. Interview the user with `AskUserQuestion` to identify the initial set of specs and their order.
2. Triage each one for pipeline track per `.claude/rules/specs.md`.
3. Write `specs/INDEX.md` with the initial register and a Register history entry dated today.
4. Commit and push it directly to `main`.
5. **Then** start spec 001.

Do not start coding without a register. If the user wants "just one quick feature" without a register, that is still spec 001 — write it down. The register is the audit trail for the project's evolution; skipping it loses that history.

## What this rule forbids

- Starting feature work without checking `specs/INDEX.md` first (if it exists).
- Working on a spec that is not the next unchecked row in the register.
- Chaining multiple specs in one execution without explicit user instruction.
- Stopping mid-spec to ask "should I continue with implementation?" — that is the `continuous-execution.md` anti-pattern; the answer is yes.
- Skipping the register tick + commit. The register being out of sync with reality is a worse failure than missing a test.
- Silently expanding scope during a spec. Scope creep → register rewrite proposal, not silent extension.
- Wrapping the per-spec stop in a question ("done, ready for 004?"). The status summary is the entire stop message; no follow-up question.

## How this rule interacts with the pipeline

- `feature-pipeline.md` defines **what** runs inside a spec (the pipeline phases).
- `continuous-execution.md` defines **how** the pipeline runs inside a spec (no stops between phases).
- This rule defines **when** the pipeline runs (which spec is next) and **where the project-level stops are** (after each spec's push).

If the user's prompt triggers the `feature-pipeline-detect.sh` hook and a register exists, Claude treats the prompt as "work on the next spec in the register" rather than spinning up a new ad-hoc spec — unless the prompt is explicitly outside the register's scope, in which case it becomes a register-rewrite candidate.
