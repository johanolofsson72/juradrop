# Spec register rule (per-project register, one-stop-per-spec)

Every project maintains a **spec register** at `specs/INDEX.md` — a numbered, ordered list of the specs planned for the project. The register is the source of truth for what to build, in what order, and how far the project has progressed.

This rule defines how Claude reads, executes, and updates the register. It interacts with `.claude/rules/feature-pipeline.md` (which defines the per-spec pipeline) and `.claude/rules/continuous-execution.md` (which forbids stopping inside a spec). Together they form: **continuous within a spec, one stop between specs.**

## The contract (BLOCKING)

When `specs/INDEX.md` exists in a project:

1. **Read the register first.** Before doing any feature work, open `specs/INDEX.md` and identify the next unchecked spec.
2. **Run the full pipeline for that one spec, end-to-end.** Triage per `specs.md`, run `/speckit-specify`, `/speckit-clarify` (all tracks, auto-pick), `/allium:elicit` if applicable, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze` (auto-apply), `/speckit-implement`, browser tests (functional + destructive), `/tla` if applicable. No stops between phases — this is one task per `continuous-execution.md`.
3. **Commit and push to `main` directly.** Per `project_workflow` memory (solo, direct-push, no PRs), each spec finishes with `git add` + `git commit` + `git push origin main`. No feature branches, no merge step.
4. **Tick the register.** Mark the spec as `[x]` in `specs/INDEX.md` and commit + push the register update along with (or immediately after) the spec's final commit.
5. **Stop with a status summary.** This is the **only** legitimate stop between specs. The summary follows the template in this rule. The user resumes the next spec when ready.

Specs run **one at a time**. Claude does not chain multiple specs in a single execution unless the user explicitly says so ("run specs 003 and 004 back to back", "do the whole register in one go"). The default is one spec per run.

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

## Register history

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

## The status summary (the one stop per spec)

When a spec is complete, Claude's stop message uses this exact shape:

```
**Spec NNN — <slug> — DONE**

- Track: <full|light|spec-only>[ +hardened]
- Commits: <count> (last: <short-sha> — "<commit subject>")
- Push: origin/main <short-sha>
- Pipeline: spec → <clarify status> → <allium status> → impl → <N> functional + <M> destructive browser tests → <tla status>
- Hardening: <hardening status>
- Open findings: <count> (or "none")

**Next: NNN — <slug>** (or "register complete")

(Resume when ready.)
```

Fields:
- `<clarify status>` — `clarify auto-picked N answers` / `clarify clean (no questions raised)` / `clarify deferred N questions to user`
- `<allium status>` — `allium ok` / `allium skipped (spec-only track)` / `allium with N open questions surfaced`
- `<tla status>` — `tla clean` / `tla skipped (spec-only or trivial state)` / `tla with N gaps surfaced`
- `<hardening status>` — `n/a (not a hardened spec)` / `threat-model + stress + mutation-gate + adversarial-review all passed` / `hardened with N findings surfaced` (per `.claude/rules/spec-hardening.md`). For a checkpoint row, this line instead reads `integration checkpoint: regression + security sweep + scenario reconciliation + mutation spot-check — <result>`.
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

## Enforcement (three layers)

The register is enforced deterministically — Claude cannot silently skip it because the hooks fire regardless of conversation state.

1. **SessionStart orientation** (`scripts/spec-register-orientation-hook.sh`) — at every session start, this hook walks up from `$PWD` to the repo root, looks for `specs/INDEX.md`, and emits one of:
   - **Register exists** → a `systemMessage` with totals (done / in-progress / blocked / todo) and the next unchecked row. Claude knows immediately which spec is on deck.
   - **No register, but the project has a language marker** (`package.json`, `*.csproj`, `*.sln`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `composer.json`, `Gemfile`, `build.gradle*`, `pom.xml`, `pubspec.yaml`) → a bootstrap reminder.
   - **No register, no language marker** (template/scratch repo) → silent.

2. **PreToolUse guard** (`scripts/spec-register-guard-hook.sh`) — fires on `Edit`/`Write`/`MultiEdit`. Walks up from the file path to the `.git` boundary, checks for a language marker, and if there is one AND `specs/INDEX.md` is missing AND the file's extension is in the source-code allowlist, returns `permissionDecision: deny` with a bootstrap instruction. Allowed without register: anything under `specs/`, `.claude/**`, `scripts/**`, `README*`, `CHANGELOG*`, `LICENSE*`, `CLAUDE.md`, `.gitignore`, `.env*`, `.editorconfig`, `Dockerfile`, `docker-compose*`, and any non-source-code extension. Source-code extensions blocked: `.cs`, `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py`, `.go`, `.rs`, `.java`, `.rb`, `.php`, `.swift`, `.kt`, `.kts`, `.cpp`, `.cxx`, `.cc`, `.c`, `.h`, `.hpp`, `.hxx`, `.razor`, `.cshtml`, `.vbhtml`, `.vue`, `.svelte`, `.astro`, `.dart`, `.scala`, `.clj`, `.cljs`, `.ex`, `.exs`, `.erl`, `.hrl`, `.fs`, `.fsx`, `.fsi`, `.hs`, `.elm`, `.lua`, `.jl`, `.nim`, `.zig`, `.sh`, `.bash`, `.zsh`, `.pl`, `.pm`.

3. **This rule file** — auto-loaded each session via `.claude/rules/`. Provides the procedural context the hooks reference.

The walk in both hooks stops at the `.git` boundary so a parent directory's stray language marker (e.g. a `~/package.json` left over from some other project) cannot cause a false positive in an unrelated repo. The template repo itself trips no enforcement because it has no language marker at its `.git` root.

## Bootstrapping the register (new projects)

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
