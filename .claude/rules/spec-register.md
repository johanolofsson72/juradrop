# Spec register rule (per-project register, one-stop-per-spec)

Every project keeps a **spec register** at `specs/INDEX.md` — the numbered, ordered source of truth for what to build and how far the project has got. With `feature-pipeline.md` (what runs inside a spec) and `continuous-execution.md` (no stops inside a spec): **continuous within a spec, one stop between specs.** Long form (measurements, incidents, calibration of the byte budgets, enforcement internals): `.claude/docs/spec-register-rationale.md`.

## The contract (BLOCKING)

When `specs/INDEX.md` exists:

1. **Read the register first — targeted, not whole.** The SessionStart orientation hook usually prints the next row already. If you must open it, read only `## Specs` — never `## Register history` or `INDEX.history.md`. On a large register: `grep -nE '^- \[[ /!]\]' specs/INDEX.md | head`.
2. **Run the full pipeline for that one spec, end-to-end** — triage per `specs.md`, then specify → interview → clarify → elicit (if applicable) → plan → tasks → analyze → implement → converge → simplify → browser tests (functional + destructive) → `/tla` if applicable. No stops between phases.
3. **Commit and push to `main` directly** (solo, direct-push, no PRs, no feature branches).
4. **Tick the register** — `[x]` on the row, committed + pushed with or right after the spec's final commit.
5. **Stop with the status summary** — the **only** legitimate stop between specs.

One spec per run, one lane at a time. Chain specs only when the user explicitly says so.

## Two lanes (owner tags — only when a project runs more than one developer)

Default is one lane and nothing here applies. With two developers a row may end with an owner tag `— @name`; each machine sets `SPEC_OWNER` in `.claude/settings.local.json`, and the second lane sets `CLAUDE_TEMPLATE_AUTOSYNC=0` (template sync belongs to one machine). `spec-register-orientation`, `pipeline-state-guard` and `spec-interview-guard` resolve the active spec identically — **my in-progress row → my next row → an unowned in-progress row → the next unowned row** — change one, change all three. With `SPEC_OWNER` unset everything behaves as single-lane. Ordering still rules inside a lane; working a tail row early is a recorded exception. The other lane's row is not yours to tick, start or renumber. **A held row (`- [!]`) is never offered as the active row.** Details: `.claude/rules/lane-handoff.md` and the long-form doc.

## The register format

```markdown
# Spec register

Order of execution. Tick when done. Append new specs to the end unless renumbering is justified.

## Specs

- [x] 001 — user-auth — full track [hardened] — short one-line goal
- [ ] 002 — search — full track — short one-line goal
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after spec 005

## Register history (newest first)

- 2026-05-14 — initial register, 5 specs identified during project kickoff
```

Each row: **order number** (3-digit padded), **slug** (kebab-case, matches the spec folder), **pipeline track** (`full` / `light` / `spec-only`, plus **`[hardened]`** when a risk threshold is crossed — load-bearing, per `.claude/rules/spec-hardening.md`), **one-line goal**. **Checkpoint rows** (`H1`, `H2`, …) are inserted after every 5th completed spec and worked, ticked, committed, pushed like a spec.

Status markers:
- `- [ ]` — not started
- `- [/]` — in progress (only one spec carries this at a time)
- `- [x]` — done, committed, pushed
- `- [!]` — blocked or needs register rewrite

## Keep the register lean (BLOCKING — context-cost hygiene)

- **History entries are ONE line each** (`- YYYY-MM-DD — <one sentence>`), measured at **300 bytes** by `scripts/archive-spec-history.sh` (`--max-bytes N`, `0` disables; over-budget → exit 4 after archiving). Archived entries are exempt.
- **Cap inline history at ~5 entries**; archive the rest to `specs/INDEX.history.md` with `scripts/archive-spec-history.sh` (`--keep 5`, `--dry-run`).
- **Declare which end is newest** in the heading: `## Register history (newest first)` or `(newest last)`. Undeclared and ambiguous → the archiver moves nothing and exits 5.
- **Never load the history section as pipeline input.**
- **A row is 300 bytes** — `scripts/archive-completed-rows.sh` reports rows over `--max-bytes` (default 300).
- **Prose lives outside the register** — explainers, dependency tables and rule commentary go in `specs/INDEX.notes.md` with a one-line pointer. The 25 KB canary splits the file with `scripts/register-bytes.sh` (rows / history / prose) and names only the moves that exist; a register where every part complies gets one info line, not a warning.
- **A row is a pointer; the diagnosis lives in one of two archives** — ticked rows verbatim in `specs/INDEX.completed.md`, not-started diagnoses in `specs/INDEX.pending.md` (moved to completed on tick). Neither is pipeline input. A row must still be a self-sufficient pointer: what is wrong, where, which archive holds the rest — never "fix the thing".
- **Preserve first, shorten second** — shorten a row only once its long form is archived; `archive-completed-rows.sh` labels rows `shortenable` or `archive first`. Run it when you tick a row.
- **Never pick a row id by eye** — `bash scripts/next-register-id.sh` (`--count N`, `--alpha S`, `--checkpoint`, `--suffix NNN` for a carved row); `scripts/validate-register-ids.sh` catches collisions.
- **Ticking a row is an Edit, not a rewrite** — surgical `Edit` of `- [ ]` → `- [x]`.
- **A tick is refused while the project owes the template CORE work** (`scripts/core-owed-tick-guard-hook.sh`). Fix by landing the change in the template and syncing back — not by the override.

## Failure memory across `/clear` (`<spec-dir>/run-log.md`)

`scripts/spec-run-log-hook.sh` appends a line to `<spec-dir>/run-log.md` when a pipeline artifact is written; add notes manually for what a fresh session would otherwise rediscover (failed gates, escalated answers, deferred findings, redone phases):

```bash
bash scripts/spec-run-log-hook.sh --note "mutation gate FAILED — 41% on AuthService, tests are theatre"
```

One line per entry. Not pipeline input; SessionStart shows the last 5 lines while the row is `- [/]`. Without `--spec` the note goes to the row you would work next, which skips held and ticked rows. When you hold or tick a row, name it: `--spec 049` works at any status.

## The status summary (the one stop per spec)

```
**Spec NNN — <slug> — DONE**

- Track: <full|light|spec-only>[ +hardened]
- Commits: <count> (last: <short-sha> — "<commit subject>")
- Push: origin/main <short-sha>
- Pipeline: spec → interview (<I> answers, <interview mode>) → <clarify status> → <allium status> → impl → <N> functional + <M> destructive browser tests → <tla status>
- Hardening: <hardening status>
- Open findings: <count> (or "none")
- Row proposals: <count from this spec, each with its review verdict> (or "none")
- Maintenance due: <what ticking this row just made stale, or "nothing">

**Next: NNN — <slug>** (or "register complete")

→ Before starting the next spec, run `/clear`. A spec is one self-contained unit of work; carrying this spec's transcript into the next one is the single biggest per-spec token cost (a long unbroken session re-bills the whole growing transcript every turn, and cache expires after ~5 min idle). Fresh context per spec is the cheap default — the register + orientation hook restore all the state the next spec needs.

(Resume when ready.)
```

Fields: `<I> answers, <interview mode>` — count in `interview.md` (≥15), mode `auto` / `auto +N overflow` / `manual`. `<clarify status>` — `clarify auto-picked N answers` / `clarify clean (no questions raised)` / `clarify deferred N questions to user`. `<allium status>` — `allium ok` / `allium skipped (spec-only track)` / `allium with N open questions surfaced`. `<tla status>` — `tla clean` / `tla skipped (spec-only or trivial state)` / `tla with N gaps surfaced`. `<hardening status>` — `n/a (not a hardened spec)` / `threat-model + stress + mutation-gate + adversarial-review all passed` / `hardened with N findings surfaced`; a checkpoint row reads `integration checkpoint: regression + security sweep + scenario reconciliation + mutation spot-check — <result>`. `Maintenance due` — from `bash scripts/maintenance-due.sh --brief`, never composed by hand. Non-zero open findings must already have been surfaced individually (`validation-followup.md`).

After the summary, stop. No follow-up question — the stop **is** the question. One exception: when this spec recorded row proposals, put them in the same stop with one `AskUserQuestion`. Ask one question per proposal with **Approve** and **Decline** as the options, and state the proposal's need and its `finding.sh --review --proposals` verdict (duplicate, missing citation). Apply the answers with `finding.sh --approve / --decline`.

## Register rewrite exception (the legitimate mid-spec stop)

When spec N reveals the register itself is wrong (N+1 depends on something N never specified; a hidden assumption invalidates a later spec; scope creep needs a new row; the project goal shifted):

1. Pause the spec; mark it `- [!]`.
2. Surface it with `AskUserQuestion`: the conflict in one sentence, the source, concrete options (renumber, split, merge, add, remove, reorder).
3. Wait — a register rewrite is a user-only call.
4. Apply the agreed changes, append a one-line Register history entry, resume.

Typos, small refinements and missing test cases are not rewrites — handle them inside the pipeline.

## Enforcement (four layers)

1. **SessionStart orientation** (`scripts/spec-register-orientation-hook.sh`) — totals + next row, or a bootstrap reminder when a language marker exists but no register.
2. **PreToolUse guard** (`scripts/spec-register-guard-hook.sh`) — denies source-code edits in a project with a language marker and no `specs/INDEX.md`. `specs/`, `.claude/**`, `scripts/**`, docs, config and non-source extensions stay editable.
3. **PreToolUse tick gate** (`scripts/core-owed-tick-guard-hook.sh`) — on a write introducing `- [x]` to `specs/INDEX.md`, asks `scripts/template-autosync.sh --owed` / `--unlisted` and denies the tick if either answers. Other register edits pass; fails open; override `ALLOW_TICK_WITH_CORE_OWED=1` (announces itself); also reached via `scripts/bash-write-guard-hook.sh`.
4. **This rule file.**

Hooks stop their walk at the `.git` boundary; the template repo trips none (no language marker). See also `scripts/template-autosync-hook.sh`, `scripts/core-machinery-guard-hook.sh`, `scripts/spec_active.py`, `scripts/feature-pipeline-detect.sh`, `scripts/project-maintenance.sh` in the long-form doc.

## Bootstrapping the register (new projects)

`/project-wizard` writes the register (Phase 3D-3); a project without one after a recent wizard run is a wizard bug. Fallback: interview the user (`AskUserQuestion`) for the initial specs and order → triage each track → write `specs/INDEX.md` with a dated history entry → commit + push to `main` → **then** start spec 001. "Just one quick feature" is still spec 001.

## What this rule forbids

- Feature work without checking `specs/INDEX.md` first (if it exists).
- Working a spec that is not the next unchecked row.
- Chaining specs without explicit user instruction.
- Stopping mid-spec to ask "should I continue with implementation?".
- Skipping the register tick + commit.
- Silently expanding scope — scope creep is a register-rewrite proposal.
- Wrapping the per-spec stop in a question ("done, ready for 004?").

If a prompt triggers `feature-pipeline-detect.sh` and a register exists, treat it as "work the next spec" — unless it is explicitly outside the register's scope, which makes it a register-rewrite candidate.
