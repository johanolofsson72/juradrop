# Sync-prompt for other projects

Copy everything between the `---` markers below and paste it into a Claude Code session
in the project you want to update.

---

## Update project with the latest Claude Code configuration

The Claude template repo lives on the developer's local machine. **The exact path varies per developer** — Johan's macOS box has it at `/Users/jool/repos/Claude`, David's Linux box at `/home/david/repos/Claude`, others elsewhere. Resolve it once at the top of the run; never hardcode.

### Step -1: Resolve $TEMPLATE (MANDATORY — first thing to do)

Run this probe before reading any template files. It walks the developer's common project roots and stops at the first directory that contains the two files that together unambiguously identify the Claude template:

```bash
for CAND in "$HOME/repos/Claude" "$HOME/Projects/Claude" "$HOME/Code/Claude" "$HOME/code/Claude" "$HOME/src/Claude" "$HOME/dev/Claude" "/Users/jool/repos/Claude"; do
  if [ -f "$CAND/CLAUDE.md" ] && [ -f "$CAND/.claude/skills/sync-template/SKILL.md" ]; then
    TEMPLATE="$CAND"
    break
  fi
done

if [ -z "${TEMPLATE:-}" ]; then
  echo "[ERROR] Could not locate the Claude template repo on this machine."
  echo "        Clone it first:"
  echo "        git clone https://github.com/johanolofsson72/Claude.git \$HOME/repos/Claude"
  exit 1
fi
echo "[OK] Template at: $TEMPLATE"
```

After this point, **every reference to `/Users/jool/repos/Claude` in this document is an example only** — substitute `$TEMPLATE` when you execute. If you see a literal `/Users/jool/...` path in any command below, treat it as `$TEMPLATE/...` (the same suffix after the `/Claude` segment).

### Step 0: Version check (MANDATORY — saves tokens)

Before reading anything, check if this project is already up to date.

```bash
TEMPLATE_SHA=$(curl -sL https://api.github.com/repos/johanolofsson72/Claude/commits/main | jq -r '.sha // empty')
LAST_SHA=$(cat .claude/.sync-version 2>/dev/null)

if [ -z "$TEMPLATE_SHA" ]; then
  echo "[WARN] Could not fetch template SHA — falling back to full sync"
elif [ "$TEMPLATE_SHA" = "$LAST_SHA" ]; then
  echo "[UP TO DATE] Already synced with template @ $TEMPLATE_SHA"
  # Nothing changed since last sync — skip Steps 1-8, but STILL run Step 9 (CLAUDE.md slim check).
  # (If the user says "force resync" or "full resync", ignore this and continue with a full sync.)
elif [ -n "$LAST_SHA" ]; then
  echo "[INCREMENTAL SYNC] $LAST_SHA → $TEMPLATE_SHA"
  CHANGED=$(curl -sL "https://api.github.com/repos/johanolofsson72/Claude/compare/${LAST_SHA}...${TEMPLATE_SHA}" | jq -r '.files[]?.filename // empty')
  echo "Changed files since last sync:"
  echo "$CHANGED"
else
  echo "[FIRST SYNC] No .sync-version found — performing full sync"
fi
```

**Decision logic:**

- **SHAs equal** → project is up to date. Report "already current", skip Steps 1-8, then **jump to Step 9** (CLAUDE.md slim check always runs). Do NOT read template files.
- **LAST_SHA exists, SHAs differ** → **incremental mode**. Read ONLY files in `$CHANGED`, skip steps that involve files not in that list. Still run Step 7 (tech stack confirmation), Step 8 (verify), and Step 9 (slim check) unconditionally.
- **No LAST_SHA** → **full sync**. Read all template files per Step 1 below.
- **Force override** → if the user prompt contains "force", "full resync", or "--force", ignore `.sync-version` and do a full sync regardless.

**CRITICAL:** Only read files from the template that you actually need. In incremental mode, skipping 28 unchanged files saves ~80-90% of the tokens.

### Step 1: Read the template repo

Read the following files from `$TEMPLATE` (resolved in Step -1; all are important — do not skip any):

**Configuration:**
- `CLAUDE.md` — main configuration with critical rules and workflow
- `.claude/settings.json` — hooks, permissions, hook types (command, prompt, http, agent)

**Rules (auto-loaded, path-scoped via YAML frontmatter):**
- `.claude/rules/dotnet.md` — .NET code rules (paths: `**/*.cs`, `**/*.csproj`)
- `.claude/rules/frontend.md` — frontend rules
- `.claude/rules/security.md` — security rules for C#
- `.claude/rules/specs.md` — spec/task rules with destructive test requirements (paths: `**/spec*.md`, `**/tasks*.md`, etc.)
- `.claude/rules/tests.md` — browser test rules requiring functional coverage inventory (paths: `**/*Test*.cs`, `**/*test*.ts`, etc.)
- `.claude/rules/wordpress.md` — WordPress rules
- `.claude/rules/allium.md` — Allium spec language rules (paths: `**/*.allium`)
- `.claude/rules/continuous-execution.md` — forbids phase-splitting stalls ("should I continue with phase 2?"); execute multi-phase plans in one uninterrupted run
- `.claude/rules/project-workflow.md` — gates PR suggestions behind a one-time `AskUserQuestion` (solo vs team + PRs yes/no/sometimes); answer is saved to project memory and silently suppresses PR nagging on solo projects
- `.claude/rules/sqlite.md` — SQLite-on-NFS pragmas (rollback journal, no `mmap`, `synchronous=FULL`, 30 s `busy_timeout`), single-writer enforcement (`replicas: 1` + `stop-first` + 30 s grace), NFS mount options (`noac`, `actimeo=0`), retry strategy (paths: `**/appsettings*.json`, `**/docker-compose*.yml`, `**/Program.cs`, `**/*Db*.cs`, `**/*Sqlite*.cs`)
- `.claude/rules/spot-resilience.md` — required components for services on Azure spot workers: eviction watcher (IMDS scheduled events), graceful drain, idempotent writes, outbox pattern, healthcheck split (paths: `**/Program.cs`, `**/docker-compose*.yml`, controllers/endpoints/services/workers)

**Docs (loaded on demand, referenced from CLAUDE.md):**
- `.claude/docs/testing.md` — test conventions, functional coverage + destructive browser tests (6+1 attack categories)
- `.claude/docs/spec-testing-checklist.md` — mandatory checklist: functional coverage inventory + destructive tests in specs
- `.claude/docs/conventions.md` — code style and naming
- `.claude/docs/security.md` — security reference
- `.claude/docs/git.md` — commit/branch/PR conventions
- `.claude/docs/workflows.md` — hooks (27 events), skills, subagents, plugins, agent teams
- `.claude/docs/skills.md` — SKILL.md format, frontmatter fields, recommended skills
- `.claude/docs/agents-templates.md` — copy-paste agent templates
- `.claude/docs/deployment.md` — Docker Swarm, CI/CD, NFS export and mount setup (DBs live on `/mnt/nfs/<project>/db/`, manager exports the Azure managed disk to all spot workers)
- `.claude/docs/spot-architecture.md` — three reference architectures for stateful services on an all-spot worker fleet (SQLite on NFS share, LiteFS replicas, managed Postgres) with full compose templates, volume matrix, healthcheck split, and migration path
- `.claude/docs/stress-testing.md` — mandatory pre-deploy stress testing (k6, Lighthouse)
- `.claude/docs/project-template.md` — template for project start
- `.claude/docs/graphify.md` — optional codebase knowledge graph (opt-in per project, install instructions + when/when-not to use)

**Agents (subagents with YAML frontmatter):**
- `.claude/agents/dotnet-reviewer.md` — code review (isolation: worktree)
- `.claude/agents/security-scanner.md` — security scanning (isolation: worktree)
- `.claude/agents/test-runner.md` — test execution (background: true)
- `.claude/agents/db-agent.md` — EF Core/SQLite

**Skills (SKILL.md with frontmatter):**
- `.claude/skills/code-review/SKILL.md`
- `.claude/skills/explore-codebase/SKILL.md`
- `.claude/skills/deploy-checklist/SKILL.md`
- `.claude/skills/tla/SKILL.md` — TLA+ formal verification (auto-triggered after browser tests)
- `.claude/skills/allium/SKILL.md` — Allium spec language skill (/allium:elicit, /allium:distill)

**Scripts:**

- `scripts/tla-hook.sh` — PostToolUse hook script for TLA+ auto-trigger
- `scripts/allium-hook.sh` — PostToolUse hook that blocks if spec lacks .allium companion
- `scripts/tlc-cleanup.sh` — TLC process cleanup (kills orphaned Java/TLC processes after execution)
- `scripts/test-coverage-hook.sh` — Deterministic functional test coverage enforcement (blocks if tests < inventory items)
- `scripts/spec-md-coverage-reminder-hook.sh` — Deterministic replacement for the legacy `type:"prompt"` spec-completeness hook. Never blocks (only emits `systemMessage`), detects carve-out phrases ("carved to", "out-of-scope", "deferred to", "tracked in", etc.) and suppresses the destructive-test reminder when tests are explicitly deferred to another slice. Fixes the false-positive blocks observed in projects when slicing specs.
- `scripts/continuous-execution-hook.sh` — Stop hook backstop: inspects the last assistant message for phase-continuation question patterns ("should I continue with...", "want me to proceed...") and refuses the stop when one is detected. Sentence-aware (only blocks `?` sentences). Requires `python3` and `jq`.
- `scripts/local-llm-detect.sh` — Sourced helper. Pings Ollama at `${OLLAMA_HOST:-http://127.0.0.1:11434}/api/tags` with a 1s timeout and exports `LOCAL_LLM_AVAILABLE` (0/1). Honors `LOCAL_LLM_DISABLE=1` to force-disable. Other local-llm hooks bail out silently when AVAILABLE=0, so the stack is safe to ship to machines without Ollama. Default uses 127.0.0.1 explicitly to avoid Happy-Eyeballs routing to the wrong ollama instance when both IPv4 and IPv6 listeners exist on port 11434.
- `scripts/local-llm-call.sh` — Generic non-streaming `/api/generate` caller. Reads system prompt as `$1`, user prompt from stdin, num_predict as optional `$2`. Prints model output or exits non-zero on offline/timeout/missing-model.
- `scripts/local-llm-classify-hook.sh` — UserPromptSubmit hook. Tags the incoming prompt as TRIVIAL / MEDIUM / COMPLEX via local LLM and injects the hint as `additionalContext`. Skips prompts ≤20 chars. Honors `LOCAL_LLM_CLASSIFY_TIMEOUT` (default 4s) so the prompt path stays snappy.
- `scripts/local-llm-bash-tldr-hook.sh` — PostToolUse hook on `Bash`. When stdout+stderr exceeds `LOCAL_LLM_TLDR_MIN_CHARS` (default 4000), generates a 3-line WHAT/KEY/VERDICT summary and injects it as `additionalContext` alongside the raw output.
- `scripts/local-llm-commit-draft-hook.sh` — PostToolUse hook on `Bash` matching `git add`. Reads the staged diff, drafts a Conventional Commit message via local LLM, writes it to `.claude/.local-llm-commit-draft.md`, and surfaces the path as `additionalContext`. The draft path is gitignored.
- `scripts/local-llm-humanize-hook.sh` — PostToolUse hook on `Edit`/`Write` for `*.md` / `README*` / `CHANGELOG*` / `CONTRIBUTING*`. Excludes Claude-internal docs (`CLAUDE.md`, `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/docs/`, `.specify/`). Reports AI-tells (em-dash overuse, inflated vocab, rule of three, hollow openers) as `additionalContext`. Read-only: never modifies the file.
- `scripts/local-llm-stacktrace-hook.sh` — PostToolUse hook on `Bash`. When output >2000 chars contains error/exception/traceback keywords, extracts three lines: ERROR (type and message), LOCATION (first user-code frame), CAUSE (one-line hypothesis). Complementary to bash-tldr.
- `scripts/local-llm-pr-draft-hook.sh` — PostToolUse hook on `Bash` matching `git push -u origin <branch>`. Reads the branch diff against main/master, drafts PR title + Summary + Test plan to `.claude/.local-llm-pr-draft.md`. Used when the assistant subsequently calls `gh pr create`.
- `scripts/local-llm-spec-criteria-hook.sh` — PostToolUse hook on `Edit`/`Write` for speckit spec files (`specs/<id>/spec.md` and `.specify/specs/<id>/spec.md`). Scans Acceptance Criteria for vague language ("works well", "is fast"), suggests measurable replacements. Catches loose criteria immediately after `/specify`, before `/clarify` and `/allium:elicit` run.
- `scripts/local-llm-changelog-hook.sh` — PostToolUse hook on `Edit`/`Write` for `CHANGELOG.md`. Reads `git log` since the last tag, groups by Conventional Commit type, drafts keep-a-changelog format entries to `.claude/.local-llm-changelog-draft.md`.
- `scripts/local-llm-orientation-hook.sh` — SessionStart hook. Reads recent git log, status, diff, and active specs (modified last 7 days), generates a 5-8 line "where you left off" orientation as `additionalContext`. Honors `LOCAL_LLM_ORIENTATION_DISABLE=1`.
- `scripts/local-llm-tlc-translate-hook.sh` — PostToolUse hook on `Bash` matching TLC commands (`tlc2.TLC`, `tla2tools`). When output contains counterexample/invariant/deadlock markers, translates the TLA+-syntax state trace into plain-English step-by-step.
- `scripts/local-llm-migration-safety-hook.sh` — PostToolUse hook on `Edit`/`Write` for migration files (`*.sql`, `*Migrations/*.cs`, etc.). Scans for production-unsafe patterns (NOT NULL without default, DROP COLUMN without rename, missing FK index, non-online ALTER, etc.) and reports each as `RISK: ... | FIX: ...`.
- `scripts/local-llm-test-gap-hook.sh` — PostToolUse hook on `Edit`/`Write` for `*.cs`/`*.tsx`/`*.ts` source files (skips test files, generated files, migrations). Finds matching test files via filename convention, lists public methods/functions without tests as `GAP: ... | reason ...`.
- `scripts/local-llm-async-audit-hook.sh` — PostToolUse Edit/Write on `*.cs`. Scans for sync-over-async (`.Result`/`.Wait()`), missing `await`, blocking I/O in async methods, `async void` on non-events, missing `ConfigureAwait(false)` in libraries. Outputs `ISSUE: ... | FIX: ...` lines or `CLEAN`.
- `scripts/local-llm-auth-check-hook.sh` — PostToolUse Edit/Write on `*Controller.cs` or files in `Controllers/`. Verifies every HTTP action method has explicit `[Authorize]` or `[AllowAnonymous]`. Outputs `UNGUARDED: ... | FIX: ...` or `GUARDED`.
- `scripts/local-llm-linq-perf-hook.sh` — PostToolUse Edit/Write on `*.cs`. Detects multi-enumeration of same `IEnumerable`, `ToList()` in loops, `.Where(...).Count()` instead of `.Count(predicate)`, sync EF queries. Outputs `PERF: ... | FIX: ...` or `CLEAN`.
- `scripts/local-llm-test-name-hook.sh` — PostToolUse Edit/Write on test files. Flags vague names (`Test1`, `MethodTest`, `Foo`) and suggests `Method_Scenario_Expected` replacements based on test body.
- `scripts/local-llm-test-assertion-hook.sh` — PostToolUse Edit/Write on test files. Verifies each test contains at least one assertion call (`Assert.*`, `.Should()`, `expect()`, `Verify`). Catches placebo tests.
- `scripts/local-llm-test-realism-hook.sh` — PostToolUse Edit/Write on test files. Flags placeholder mock data (`""`, `null`, `0`, `"test"`, `"x"`) and suggests realistic values. Lenient about explicit boundary tests.
- `scripts/local-llm-task-traceability-hook.sh` — PostToolUse Edit/Write on speckit `tasks.md`. Maps tasks ↔ acceptance criteria from sibling `spec.md`; reports orphan tasks (scope creep) and orphan criteria (missing impl).
- `scripts/local-llm-allium-drift-rank-hook.sh` — PostToolUse Bash matching `allium distill`. Ranks each drift finding HIGH/MEDIUM/LOW for release-blocking severity; ends with `RELEASE_GATE: BLOCKED|PROCEED-WITH-FOLLOWUPS`.
- `scripts/local-llm-allium-openq-hook.sh` — PostToolUse Edit/Write on `*.allium`. Extracts `open question`, `-- AMBIGUITY:`, `deferred` markers as actionable items requiring decision per validation-followup rule.
- `scripts/local-llm-dockerfile-review-hook.sh` — PostToolUse Edit/Write on `Dockerfile`/`Dockerfile.*`. Scans for missing HEALTHCHECK, root user, `:latest` base tag, secrets in ENV, missing `.dockerignore`, layer-bloat patterns.
- `scripts/local-llm-branch-name-hook.sh` — PostToolUse Bash matching `git checkout -b <name>` or `git switch -c <name>`. When name is lazy (`fix`, `wip`, `temp`), suggests 3 descriptive alternatives based on diff and recent commits, plus a `git branch -m` rename command.
- `scripts/local-llm-pr-splitter-hook.sh` — PostToolUse Bash matching `git push -u origin <branch>`. If diff against base > 500 lines, suggests 2-4 natural splits by file groupings + merge order, or marks `COHESIVE` if single coherent change.
- `scripts/local-llm-react-deps-hook.sh` — PostToolUse Edit/Write on `*.tsx`/`*.ts`/`*.jsx`/`*.js`. Detects missing deps in `useEffect`/`useCallback`/`useMemo` arrays (stale-closure bug source) plus empty/missing deps arrays and conditional hook calls.
- `scripts/local-llm-n1-query-hook.sh` — PostToolUse Edit/Write on `*.cs`. Catches the N+1 anti-pattern (foreach over collection with awaited db call inside).
- `scripts/local-llm-secret-scan-hook.sh` — PostToolUse Edit/Write on source/config files. Regex pre-filter for likely secrets, llama3 filters false positives (variable names, type annotations, env-var lookups, test placeholders).
- `scripts/local-llm-todo-catalog-hook.sh` — PostToolUse Edit/Write when file accumulates ≥3 TODO/FIXME/HACK/XXX/TBD markers. Catalogs each by category (bug/feature/refactor/etc.) and priority (high/medium/low).
- `scripts/local-llm-spec-scope-hook.sh` — PostToolUse Edit/Write on speckit `spec.md` with both Scope and Acceptance Criteria sections. Detects criteria that fall outside declared scope (scope creep).
- `scripts/local-llm-plan-feasibility-hook.sh` — PostToolUse Edit/Write on speckit `plan.md`. Flags unrealistic estimates, missing critical phases (testing/deploy/rollback), tech-stack conflicts (cross-references CLAUDE.md), and hand-wavy steps.

### Step 2: Read this project's files

Read existing `CLAUDE.md`, `.claude/settings.json`, and all files under `.claude/` in THIS project. Note what is project-specific.

### Step 3: Language migration (CRITICAL)

The template has been migrated from Swedish to English. If THIS project still has Swedish content in its Claude Code configuration files:

1. **CLAUDE.md** — Translate all Swedish sections to English. Update the Language section to specify English.
2. **All .claude/docs/*.md** — Translate any Swedish content to English.
3. **All .claude/rules/*.md** — Translate any Swedish content to English.
4. **.claude/settings.json** — Change `"language": "swedish"` to `"language": "english"` (or remove the field entirely).
5. **Commit messages and PR descriptions** — Should now be written in English.

Preserve all project-specific technical content during translation — only the human language changes, not the meaning.

### Step 4: Analyze and update

For each file in the template:

| Situation | Action |
|-----------|--------|
| File does NOT exist in this project | Copy from template |
| File exists and matches template | Skip |
| File exists but is older | Update to template version, preserve `# PROJECT-SPECIFIC` blocks |
| File exists with project-specific content | Merge — template structure + project customizations |

**CLAUDE.md merge:**
- Update: critical rules, execution mode, workflow, verification, context management, reference files
- Preserve: project description, tech stack, commands, project-specific principles

**settings.json merge:**
- UNION of hooks — add template hooks without removing project's own
- UNION of permissions.deny — combine both lists
- Preserve project-specific hooks and permissions
- NOTE: the template uses hook types that may not exist in the project:
  - `type: "prompt"` — LLM evaluation (for spec validation)
  - `type: "agent"` — multi-turn verification with tool access
  - `type: "http"` — webhook integration
  - `if` field (v2.1.85) — filtering with permission rule syntax
  - `"defer"` permission decision (v2.1.89) — for headless sessions

### Step 5: Verify spec testing (CRITICAL)

These three components work together to ensure destructive browser tests are included at spec-writing time — not as an afterthought:

1. **`.claude/rules/specs.md`** — path-scoped rule triggered on spec/task/plan files. Requires testing.md and the checklist to be read BEFORE the spec is written.

2. **`.claude/docs/spec-testing-checklist.md`** — concrete template with task structure per attack category. Defines minimum requirements per feature type (8-15 tests). Target: 99% E2E coverage.

3. **PostToolUse command-hook in settings.json** — triggers on Edit/Write of `.md` files whose path contains spec/tasks/plan/feature; emits an advisory `systemMessage` when an interactive-UI spec is missing FUNCTIONAL COVERAGE or destructive tests. NEVER blocks. Verify this hook exists in this exact form:
   ```json
   {
     "matcher": "Edit|Write",
     "hooks": [{
       "type": "command",
       "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/spec-md-coverage-reminder-hook.sh\"",
       "statusMessage": "Validating spec completeness..."
     }]
   }
   ```

   **Legacy form to OVERWRITE if found:** earlier versions of the template used a `type:"prompt"` hook with a long prompt containing the phrases `INTERACTIVE UI` and `always approve and use systemMessage for the reminder`. The session LLM was observed overriding the "do not block" instruction and issuing `permissionDecision: deny` on specs that legitimately carved destructive tests to a later slice. If the project's `settings.json` still has that `type:"prompt"` hook, replace the entire hook object with the `type:"command"` form above. The new script (`spec-md-coverage-reminder-hook.sh`) is deterministic, only ever emits `systemMessage`, and detects carve-out phrases ("carved to", "out-of-scope", "deferred to", "tracked in", "see slice N") to suppress false-positive reminders.

If ANY of these three are missing — copy from the template.

### Step 5b: Verify Allium + TLA+ verification pipeline

The template includes a full spec-to-verification pipeline:

```text
Spec (markdown) → /allium:elicit → .allium → Implementation →
Browser tests (destructive) → /tla (distill + drift + invariants) → Done
```

**Files to sync:**

1. **`.claude/skills/tla/SKILL.md`** — formal verification skill with Allium drift detection
2. **`.claude/rules/allium.md`** — prescriptive Allium rules (triggers on spec AND .allium files)
3. **`.claude/rules/specs.md`** — updated with Allium pre-implementation + TLA+ post-implementation steps
4. **`scripts/tla-hook.sh`** — PostToolUse hook that detects browser/E2E test files
5. **PostToolUse hook in settings.json** — triggers `scripts/tla-hook.sh` on Edit/Write of test files
6. **UserPromptSubmit hook in settings.json** — updated to include Allium + TLA+ instructions on speckit keywords

If any are missing — copy from template.

**Optional: Install Allium CLI** for automatic `.allium` file validation:

```bash
# Homebrew
brew tap juxt/allium && brew install allium
# Or Cargo
cargo install allium-cli
```

### Step 5c: Verify local-LLM offload stack

The template auto-detects a local Ollama daemon and offloads work that genuinely reduces Anthropic token consumption (artifact drafts, routing hints, GitHub-context digests). When Ollama is not running on the developer's machine, every hook becomes a silent no-op — the stack is safe to ship to projects regardless of whether each developer runs Ollama locally.

**Policy:** the template ships ~38 local-LLM hook scripts on disk but only 13 are wired by default — the ones that demonstrably save tokens (artifact producers + routing hints + GitHub-context digests). The remaining ~25 scripts are quality gates that ADD context for bug-catching; they cost tokens, they do not save them. Wire them per-project only when the bug-catching value justifies the per-fire context cost.

**Files to sync** (use `Glob` against the template root for the hook scripts so this list does not need hand-editing as new hooks land):

1. **`scripts/local-llm-detect.sh`** — sourced helper, pings Ollama and exports `LOCAL_LLM_AVAILABLE`
2. **`scripts/local-llm-call.sh`** — generic `/api/generate` caller. Auto-detects project root for per-project telemetry logs, writes a tracer line on every entry, captures write errors to a sibling `.errors` file
3. **`scripts/local-llm-stats.sh`** — per-hook ROI reporter. `--all` aggregates across `~/repos/*` and `~/Projects/*`
4. **`scripts/sync-local-llm-hooks.py`** — deterministic settings.json hook-merge helper invoked below
5. **`scripts/verify-local-llm-hooks.sh`** — cross-check that the project's wired set matches the template after the merge
6. **Glob: every `scripts/local-llm-*-hook.sh`** — copy each matching file from the template. Files in the project but no longer in the template should be removed (template owns the script set)
6. **`.claude/docs/local-llm.md`** — env var reference, setup, telemetry, failure modes
7. **`.gitignore`** — see "Gitignore additions" below

After copying scripts, run `chmod +x scripts/local-llm-*.sh scripts/sync-local-llm-hooks.py scripts/verify-local-llm-hooks.sh`.

**Wire the hooks deterministically** (this is what previously failed under prose-only "merge" rules):

```bash
python3 scripts/sync-local-llm-hooks.py "$TEMPLATE/.claude/settings.json"
```

The script strips every `bash scripts/local-llm-*-hook.sh` entry from the project's `.claude/settings.json` and reinstalls the template's exact set. Non-local-LLM hook entries (project-specific or other template hooks like `tla-hook.sh`, `ui-design-hook.sh`) are preserved verbatim. Idempotent. Capture its stdout for the Step 10 report.

**Do NOT additively merge local-LLM hook entries by hand.** Prose merge rules conflict with "preserve project-specific customizations" and the result is stale wiring that the project keeps forever. The script is the deterministic source of truth; let it do the work.

**Cross-check the trim** (catches the trim's own bugs — e.g. a regex that does not match digits letting `n1-query` slip through):

```bash
bash scripts/verify-local-llm-hooks.sh "$TEMPLATE/.claude/settings.json"
```

Three checks run: (1) the wired set matches the template's exactly, (2) every wired hook has its script file on disk, (3) the count matches the template. Exit non-zero on any failure. **If this fails, the sync is broken — fix it before reporting success in Step 10.** Capture the stdout for the Step 10 report.

**Currently wired by default (13 token-saver hooks):**

| Event | Hook | Why it saves tokens |
|-------|------|---------------------|
| UserPromptSubmit | `classify` | Routing hint lets Claude skip heavy skills (Allium / TLA+) on simple work |
| SessionStart | `orientation` | Replaces the SessionStart `git log` / `status` / `diff` discovery roundtrip |
| PostToolUse Bash (`git add`) | `commit-draft` | Pre-drafts commit message to a file; Claude refines instead of regenerating |
| PostToolUse Bash (`git push -u`) | `pr-draft` | Pre-drafts PR title + Summary + Test plan |
| PostToolUse Bash (`gh run view`) | `gh-run-view` | Digests CI run output (often 5000+ lines) into per-job failure summary |
| PostToolUse Bash (`gh pr view`) | `gh-pr-view` | Digests PR description + decisions + open threads |
| PostToolUse Bash (`gh issue view`) | `gh-issue-view` | Digests issue body + comment thread |
| PostToolUse Edit/Write `CHANGELOG.md` | `changelog` | Pre-drafts keep-a-changelog entries from `git log` |
| PostToolUse Edit/Write `specs/*/spec.md` | `tasks-draft` | Pre-drafts initial `tasks.md` so `/tasks` refines instead of generates |
| PostToolUse Edit/Write `specs/*/spec.md` | `plan-draft` | Pre-drafts initial `plan.md` so `/plan` refines instead of generates |
| PostToolUse Edit/Write fresh `README.md` | `readme-skeleton` | Drafts standard sections from repo signals |
| PostToolUse Edit/Write fresh `.gitignore` | `gitignore-skeleton` | Drafts language-appropriate ignores from detected stacks |
| PostToolUse Edit/Write `.env*` | `dotenv-example` | Drafts `.env.example` from env-var references grepped out of code |

**Per-developer setup** (each developer who wants the offload to actually fire):

```bash
brew install ollama          # or platform equivalent (apt/dnf/pacman)
ollama pull llama3           # 8B by default; resolves to llama3:latest
ollama serve &               # daemon stays warm in background
```

If a developer skips this, every local-llm-* hook detects the missing daemon in 1s and exits silently. Nothing breaks; they simply do not get the offload benefit.

**Per-project tuning** (optional, in shell profile or `.envrc`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Ollama base URL (IPv4 loopback by default to avoid Happy-Eyeballs surprises) |
| `LOCAL_LLM_MODEL` | `llama3` | Model tag — Ollama auto-resolves untagged to `:latest` |
| `LOCAL_LLM_TIMEOUT` | `15` | Generation timeout (seconds) |
| `LOCAL_LLM_CLASSIFY_TIMEOUT` | `4` | Tighter timeout for the prompt-path classifier |
| `LOCAL_LLM_COMMIT_DIFF_BYTES` | `10000` | Diff cap for commit-draft (raise if you commit huge diffs) |
| `LOCAL_LLM_COMMIT_DRAFT_TIMEOUT` | `20` | Per-hook timeout for commit-draft (overrides the global) |
| `LOCAL_LLM_TASKS_DRAFT_TIMEOUT` | `60` | Per-hook timeout for tasks-draft — 1536 num_predict on the spec-aware extraction model regularly exceeds the global 15s. Lower if your local model is fast; raise if you see exit-28 timeouts in `local-llm-fire.log`. |
| `LOCAL_LLM_PLAN_DRAFT_TIMEOUT` | `60` | Per-hook timeout for plan-draft — same rationale as tasks-draft. |
| `LOCAL_LLM_ALLIUM_DRIFT_RANK_TIMEOUT` | `45` | Per-hook timeout for allium-drift-rank — ranks drift reports (up to 12KB) with `num_predict=768`. 32b-class models regularly exceed 15s on this. |
| `LOCAL_LLM_TELEMETRY_LOG` | `<repo>/.claude/local-llm-fire.log` | Per-project log path; auto-detected from `git rev-parse --show-toplevel` |
| `LOCAL_LLM_TRACE_LOG` | `<repo>/.claude/local-llm-trace.log` | Per-project entry-tracer log |
| `LOCAL_LLM_TELEMETRY_DISABLE` | unset | Set to `1` to skip telemetry rows |
| `LOCAL_LLM_DISABLE` | unset | Set to `1` to force-disable every offload hook |

**Gitignore additions** (ensure all of these are present):

```
.claude/.local-llm-*
.claude/local-llm-*.log
.claude/local-llm-*.log.errors
```

The first pattern hides the draft artifacts that hooks write (`.local-llm-commit-draft.md`, `.local-llm-pr-context.md`, etc.). The second hides per-project telemetry logs. The third hides telemetry write-error logs.

**Verification** (run in the project root after sync):

```bash
# Should be 13 (the wired token-saver set)
grep -c 'local-llm-.*-hook.sh' .claude/settings.json

# Should produce no output (no stale quality gates wired)
grep -E 'bash-tldr|stacktrace|allium-drift|test-(name|assertion|realism|gap)|async-audit|auth-check|linq-perf|n1-query|react-deps|secret-scan|todo-catalog|dockerfile-review|migration-safety|spec-(criteria|scope)|plan-feasibility|task-traceability|allium-openq|branch-name|pr-splitter|tlc-translate|humanize' .claude/settings.json
```

If either check fails: re-run `python3 scripts/sync-local-llm-hooks.py "$TEMPLATE/.claude/settings.json"` from the project root.

### Step 5d: Bootstrap Graphify (codebase knowledge graph) — cross-platform

Graphify (`safishamsi/graphify`, MIT) builds a queryable AST graph of the codebase via tree-sitter — no LLM API key required for extraction. Claude Code queries the graph instead of grepping raw files for structural questions ("where is X defined", "who calls Y", "what connects auth to the database"). The token-savings hook (`scripts/graphify-fire-hook.sh`) logs every `graphify query|path|explain|update` invocation to `.claude/graphify-fire.log` so we can measure ROI per project.

This step is **opt-in by source-file count**, not opt-in by developer decision. The bootstrap script counts eligible source files and skips projects with fewer than 30 — for prototypes the install overhead exceeds the savings.

**Files to sync** (these three plus the install logic below):

1. **`scripts/graphify-fire-hook.sh`** — PostToolUse Bash hook. Matches `graphify (query|path|explain|update)` invocations and appends a TSV line to `.claude/graphify-fire.log` with timestamp, subcommand, exit, arg bytes, response bytes, graph node count, graph edge count. Disable per-developer with `GRAPHIFY_TELEMETRY_DISABLE=1`.
2. **`scripts/graphify-stats.sh`** — ROI reporter. Reads the fire log and prints per-subcommand fire counts, ok%, avg argument and response sizes. `--all` aggregates across `~/repos/*` and `~/Projects/*`.
3. **`scripts/graphify-bootstrap.sh`** — Cross-platform self-installer. Idempotent. Detects platform package manager (`brew` → `apt-get` → `dnf` → `pacman` → `zypper` → `choco`/`scoop` on Windows → fallback to `python3 -m pip --user`), installs pipx if missing, installs graphifyy, runs `graphify install --project`, `graphify update .` (AST-only, no API key), `graphify hook install`, and adds `graphify-out/` to `.gitignore`. Pass `--eligibility-check` to dry-run the source-file count without installing. Pass `--force` to override the 30-file threshold.

After copying these scripts, `chmod +x scripts/graphify-*.sh`.

**Wire the telemetry hook in `.claude/settings.json`:**

The hook is non-local-LLM, so `sync-local-llm-hooks.py` does NOT touch it — preserve it verbatim. Add (or verify the presence of) this PostToolUse entry in the `Bash` matcher block:

```json
{
  "type": "command",
  "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/graphify-fire-hook.sh\"",
  "statusMessage": "Logging graphify invocation telemetry..."
}
```

The path **must** use `$CLAUDE_PROJECT_DIR` — relative `bash scripts/...` breaks the moment Claude Code is launched from a subdirectory, and that has burned 14 repos before. Run `python3 scripts/fix-hook-paths.py .claude/settings.json` in Step 8 to catch any drift.

**Run the bootstrap (cross-platform):**

```bash
bash scripts/graphify-bootstrap.sh
```

The script does its own platform detection. Expected behavior per OS:

| OS / Shell | Package manager preferred | Bootstrap result |
|---|---|---|
| **macOS (zsh/bash)** | `brew` → `pip --user` | Installs pipx via brew, then graphifyy via pipx |
| **Linux Debian/Ubuntu (bash)** | `apt-get` → `pip --user` | Installs pipx via apt, then graphifyy via pipx. `sudo` prompt expected. |
| **Linux Fedora/RHEL (bash)** | `dnf` → `pip --user` | Installs pipx via dnf, then graphifyy via pipx. `sudo` prompt expected. |
| **Linux Arch (bash)** | `pacman` → `pip --user` | Installs `python-pipx` via pacman, then graphifyy via pipx. `sudo` prompt expected. |
| **Linux openSUSE (bash)** | `zypper` → `pip --user` | Installs `python3-pipx`, then graphifyy via pipx. |
| **Windows Git Bash** | `scoop` → `winget` → `choco` → `pip --user` | Installs pipx via scoop (preferred — no UAC) or winget/choco, then graphifyy via pipx. Add `$HOME/.local/bin` to PATH if not present. |
| **Windows WSL2** | Same as Linux variant of the WSL distro | Same as native Linux. |
| **Windows PowerShell (native)** | NOT supported by `graphify-bootstrap.sh` directly | Run the script via Git Bash (recommended) or WSL. A native PowerShell sibling (`scripts/graphify-bootstrap.ps1`) is on the template TODO list. |

**If the bootstrap fails:**

Don't silently proceed. The script exits 1 with a specific message naming what's missing (no package manager, pipx install failed, graphify install failed). Capture the error in the Step 10 report and tell the developer to install pipx manually:

- macOS: `brew install pipx && pipx ensurepath`
- Debian/Ubuntu: `sudo apt install pipx && pipx ensurepath`
- Fedora/RHEL: `sudo dnf install pipx && pipx ensurepath`
- Arch: `sudo pacman -S python-pipx && pipx ensurepath`
- Windows Git Bash: `scoop install pipx` or `winget install pipx`

Then re-run `bash scripts/graphify-bootstrap.sh`.

**Tuning** (optional, in shell profile or `.envrc`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `GRAPHIFY_TELEMETRY_DISABLE` | unset | Set to `1` to skip writing rows to `graphify-fire.log` (script still runs, exits silently) |
| `GRAPHIFY_TELEMETRY_LOG` | `<repo>/.claude/graphify-fire.log` | Per-project log path |
| `GRAPHIFY_VIZ_NODE_LIMIT` | `5000` | Skip `graph.html` viz above this node count (graphify's own var) |

**Gitignore additions** (the bootstrap script adds these automatically, but verify):

```
graphify-out/
.claude/graphify-*.log
```

**Verification:**

```bash
# graphify CLI on PATH
command -v graphify && graphify --version

# Initial graph exists
test -f graphify-out/graph.json && echo "[OK] graph.json present"

# Fire-hook script on disk and executable
test -x scripts/graphify-fire-hook.sh && echo "[OK] graphify-fire-hook.sh executable"

# Hook wired in settings.json
grep -q 'graphify-fire-hook.sh' .claude/settings.json && echo "[OK] telemetry hook wired"
```

If any of these fail: re-run `bash scripts/graphify-bootstrap.sh`. The script is idempotent and will skip steps that are already complete.

### Step 6: Install required skills

Install the following external skills to `~/.claude/skills/` if not already present. These are shared across all projects.

```bash
# anthropics/skills — Official Anthropic collection (includes frontend-design, PDF, PPTX, XLSX)
# CRITICAL: frontend-design is a BLOCKING REQUIREMENT in CLAUDE.md
if [ ! -d "$HOME/.claude/skills/anthropics-skills" ]; then
  git clone https://github.com/anthropics/skills.git "$HOME/.claude/skills/anthropics-skills"
  echo "[INSTALLED] anthropics/skills — official collection (frontend-design, PDF, PPTX, XLSX)"
else
  echo "[SKIPPED] anthropics/skills — already installed"
fi

# obra/superpowers — Planning, TDD, code review
if [ ! -d "$HOME/.claude/skills/superpowers" ]; then
  git clone https://github.com/obra/superpowers.git "$HOME/.claude/skills/superpowers"
  echo "[INSTALLED] obra/superpowers — planning, TDD, code review"
else
  echo "[SKIPPED] obra/superpowers — already installed"
fi

# trailofbits/skills — Security research skills from Trail of Bits
if [ ! -d "$HOME/.claude/skills/trailofbits-skills" ]; then
  git clone https://github.com/trailofbits/skills.git "$HOME/.claude/skills/trailofbits-skills"
  echo "[INSTALLED] trailofbits/skills — security research"
else
  echo "[SKIPPED] trailofbits/skills — already installed"
fi

# adampaulwalker/qa-test — Destructive/adversarial browser testing with Playwright
if [ ! -d "$HOME/.claude/skills/qa-test" ]; then
  git clone https://github.com/adampaulwalker/qa-test.git "$HOME/.claude/skills/qa-test"
  echo "[INSTALLED] qa-test — destructive browser testing (Jinx persona)"
else
  echo "[SKIPPED] qa-test — already installed"
fi

# dotnet/skills — Official Microsoft .NET skills (ASP.NET Core, EF Core, Blazor)
if [ ! -d "$HOME/.claude/skills/dotnet-skills" ]; then
  git clone https://github.com/dotnet/skills.git "$HOME/.claude/skills/dotnet-skills"
  echo "[INSTALLED] dotnet/skills — official .NET patterns and best practices"
else
  echo "[SKIPPED] dotnet/skills — already installed"
fi

# vercel-labs/skills — React performance rules and web design guidelines
if [ ! -d "$HOME/.claude/skills/vercel-skills" ]; then
  git clone https://github.com/vercel-labs/skills.git "$HOME/.claude/skills/vercel-skills"
  echo "[INSTALLED] vercel-labs/skills — React performance (45 rules), web design"
else
  echo "[SKIPPED] vercel-labs/skills — already installed"
fi

# lackeyjb/playwright-skill — Deep Playwright knowledge (POM, patterns, CI/CD)
if [ ! -d "$HOME/.claude/skills/playwright-skill" ]; then
  git clone https://github.com/lackeyjb/playwright-skill.git "$HOME/.claude/skills/playwright-skill"
  echo "[INSTALLED] playwright-skill — Playwright patterns, POM, test generation"
else
  echo "[SKIPPED] playwright-skill — already installed"
fi
```

**npm-based skills (installed via CLI):**

```bash
# ui-ux-pro-max — Design intelligence (67 styles, 96 palettes, 57 font pairings, 25 charts, 13 stacks)
if ! uipro --version &>/dev/null 2>&1; then
  npm install -g uipro-cli
  echo "[INSTALLED] uipro-cli — UI/UX Pro Max CLI"
else
  echo "[SKIPPED] uipro-cli — already installed"
fi

# Initialize in the project if not already present
if [ ! -d ".claude/skills/ui-ux-pro-max" ]; then
  uipro init --ai claude
  echo "[INSTALLED] ui-ux-pro-max skill — design intelligence for Claude Code"
else
  echo "[SKIPPED] ui-ux-pro-max — already initialized in project"
fi
```

**What each skill provides:**

| Skill | Source | Key capabilities |
|---|---|---|
| **anthropics/skills** | Anthropic (official) | `frontend-design` (blocking requirement), PDF/PPTX/XLSX generation |
| **superpowers** | obra | TDD workflow, implementation planning, thorough code review |
| **trailofbits/skills** | Trail of Bits | OWASP security analysis, vulnerability research, secure code patterns |
| **qa-test** | Community | Destructive browser testing — Quinn (systematic QA) + Jinx (chaos tester) |
| **dotnet/skills** | Microsoft (official) | ASP.NET Core, EF Core, Blazor patterns, project scaffolding |
| **vercel-labs/skills** | Vercel (official) | React performance rules (45 rules ranked by impact), web design |
| **playwright-skill** | Community (2k+ stars) | Deep Playwright knowledge, Page Object Model, CI/CD patterns |
| **ui-ux-pro-max** | Community (npm: uipro-cli) | 67 UI styles, 96 palettes, 57 font pairings, 25 chart types, 13 stacks |

The qa-test and playwright-skill require the Playwright MCP server. If the project has UI components, verify Playwright MCP is configured.

### Step 6b: Install TLC model checker (required for /tla)

The TLA+ skill auto-installs TLC if missing, but verify it's available on the machine:

```bash
# Check if TLC is already available
if command -v tlc &>/dev/null; then
  echo "[SKIPPED] TLC model checker — already installed ($(which tlc))"
elif command -v brew &>/dev/null; then
  echo "[INSTALLING] TLC model checker via Homebrew..."
  brew install --quiet tlaplus
  echo "[INSTALLED] TLC model checker (tlaplus)"
else
  echo "[INSTALLING] TLC model checker via JAR download..."
  curl -fsSL -o /usr/local/lib/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
  echo "[INSTALLED] TLC model checker (JAR at /usr/local/lib/tla2tools.jar)"
fi
```

Without TLC, the /tla skill falls back to reasoning-based verification (LLM-only, no mathematical proof). With TLC, it runs actual model checking.

### Step 7: Ask about tech stack, then remove irrelevant files

**IMPORTANT: Do NOT guess the tech stack from files alone.** A new project may not have any source files yet. ALWAYS ask the developer before removing anything.

Use `AskUserQuestion` to confirm:

> Which of the following does this project use (or will use)?
>
> - .NET (C#, ASP.NET Core, Blazor, EF Core)
> - WordPress (PHP, themes, plugins)
> - React / frontend with UI
> - SQLite / database
>
> List all that apply, or say "all" to keep everything.

Then, based on the developer's answer:

- Developer says NO to WordPress → remove `.claude/rules/wordpress.md`
- Developer says NO to .NET → remove `.claude/rules/dotnet.md`, `.claude/rules/security.md`, `.claude/agents/dotnet-reviewer.md`, `.claude/agents/db-agent.md`
- Developer says NO to UI → remove `.claude/rules/specs.md`, `.claude/docs/spec-testing-checklist.md`, `.claude/skills/tla/SKILL.md`, `.claude/rules/allium.md`, `scripts/tla-hook.sh`, spec hook, TLA+ hook
- Developer says NO to SQLite → remove `.claude/rules/sqlite.md`
- Developer says NO to live4 cluster deployment / Azure spot → remove `.claude/rules/spot-resilience.md` and `.claude/docs/spot-architecture.md`
- ALWAYS keep regardless of answer: `testing.md`, `conventions.md`, `workflows.md`, `skills.md`, `git.md`, `continuous-execution.md`, `project-workflow.md`, `continuous-execution-hook.sh`
- When in doubt, **keep the file** — extra rules cost nothing, missing rules cost bugs

### Step 7b: Audit for unsafe SQLite-on-NFS patterns (if .NET + SQLite project)

The supported live4 architecture is SQLite-on-NFS (the manager exports the Azure managed disk; the spot workers mount it). NFS+SQLite works only when the project follows the strict rules in `.claude/rules/sqlite.md`. Scan for the patterns that break it:

```bash
# Stateful services with replicas > 1 — guaranteed corruption on NFS+SQLite
grep -RIn --include='docker-compose*.yml' -E 'replicas:\s*[2-9]' . 2>/dev/null

# update_config.order: start-first — old container still holds the DB when new one opens it
grep -RIn --include='docker-compose*.yml' 'order:\s*start-first' . 2>/dev/null

# stop_grace_period < 30s — not enough time to release NFS handles
grep -RIn --include='docker-compose*.yml' -E 'stop_grace_period:\s*([0-9]|1[0-9]|2[0-9])s' . 2>/dev/null

# WAL or non-zero mmap on a connection that touches the NFS-backed DB
grep -RIn -E 'journal_mode\s*=\s*WAL|PRAGMA\s+journal_mode\s*=\s*WAL' . 2>/dev/null
grep -RIn -E 'mmap_size\s*=\s*[1-9]' . 2>/dev/null

# Connection strings pointing at a worker's local disk instead of NFS
grep -RIn --include='appsettings*.json' -E '/var/lib/|/home/|/opt/.*\.db' . 2>/dev/null

# Stale "tier=stateful" / "spot=false" placement constraints from the previous (deprecated) architecture
grep -RIn --include='docker-compose*.yml' -E 'tier\s*==\s*stateful|spot\s*==\s*false' . 2>/dev/null
```

If matches are found, **flag for manual review** in Step 10. The fix:

- `replicas > 1` on a SQLite service → drop to `replicas: 1`. Multiple writers on NFS+SQLite corrupt the file.
- `order: start-first` → switch to `stop-first` so the old container fully exits before the new one opens the DB.
- `stop_grace_period < 30s` → raise to `30s` so connection pools clear and NFS handles release cleanly.
- `journal_mode=WAL` or `mmap_size > 0` → switch to `journal_mode=DELETE` and `mmap_size=0`. WAL needs cross-host mmap consistency that NFS does not provide.
- DB path on local disk → migrate to `/mnt/nfs/<project>/db/`. See `.claude/docs/spot-architecture.md` "Migration path for existing projects".
- Stale `tier=stateful` / `spot=false` constraints → remove them and replace with `node.role == worker`. The cluster no longer has a reserved-node tier; all workers are spot.

Do NOT auto-rewrite compose files or pragmas — the migration involves SSH'ing to the cluster, copying the DB to the NFS path, and verifying the export is configured with `noac`. That is a developer decision, not a sync action.

### Step 8: Verify

After syncing:
- Run `dotnet build` if the project is .NET
- Normalize hook script paths so they survive a cwd change (`python3 scripts/fix-hook-paths.py .claude/settings.json`). Hook commands must reference scripts as `bash "$CLAUDE_PROJECT_DIR/scripts/foo.sh"`, never `bash scripts/foo.sh` — the relative form silently breaks when `claude` is started from a subdirectory. The patcher is idempotent and exits non-zero on JSON parse failure.
- Verify that `settings.json` is valid JSON (`python3 -m json.tool .claude/settings.json`)
- Verify that the reference files section in CLAUDE.md points to files that actually exist

### Step 8b: Record sync version (MANDATORY)

Write the template SHA fetched in Step 0 to `.claude/.sync-version`, ensure it's not gitignored, and stage it so the developer's next commit includes it. Without this, team members re-sync from scratch on every fresh clone.

```bash
mkdir -p .claude
echo "$TEMPLATE_SHA" > .claude/.sync-version
echo "[VERSIONED] Recorded template SHA: $TEMPLATE_SHA"

# Ensure .claude/.sync-version is NOT gitignored. Strip any matching patterns.
if [ -f .gitignore ]; then
  # Match exact paths and common accidental catches
  for PATTERN in '.claude/.sync-version' '.sync-version' '.claude/\.sync-version'; do
    if grep -qxF "$PATTERN" .gitignore 2>/dev/null; then
      grep -vxF "$PATTERN" .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
      echo "[UNIGNORED] Removed '$PATTERN' from .gitignore"
    fi
  done
  # Warn if .claude/ itself is ignored — that's a bigger problem the developer must resolve
  if git check-ignore -q .claude/.sync-version 2>/dev/null; then
    echo "[WARN] .claude/.sync-version is still ignored (likely via '.claude/' rule). Add '!.claude/.sync-version' as a negation to .gitignore, OR commit the file with 'git add -f'."
  fi
fi

# Stage the sync-version file so the developer's review commit includes it
git add -f .claude/.sync-version 2>/dev/null && echo "[STAGED] .claude/.sync-version ready to commit"
```

**Why this matters:** `.sync-version` is per-project cache state. If it's gitignored or left unstaged, a teammate who clones the repo fresh has no record of the last sync SHA, and their next `/project-update` will do a full 100% sync instead of the incremental path. Committing it is the only way the cache survives across machines.

### Step 9: Slim CLAUDE.md (ALWAYS RUNS — regardless of sync mode)

**This step runs unconditionally — even when Step 0 reports "[UP TO DATE]" and even when the user forces a full resync.** The goal is to keep `CLAUDE.md` as lean as possible on every run, since drift accumulates over time.

```bash
LINES=$(wc -l < CLAUDE.md | tr -d ' ')
echo "[SLIM CHECK] CLAUDE.md is $LINES lines (Anthropic recommends <= 200)"
```

If `CLAUDE.md` exceeds **200 lines**:

1. Identify the sections that can be moved out without losing critical in-session context. Good candidates:
   - Detailed conventions → `.claude/docs/conventions.md`
   - Security rules → `.claude/docs/security.md`
   - Git workflows → `.claude/docs/git.md`
   - Testing details → `.claude/docs/testing.md`
   - Deployment / CI/CD → `.claude/docs/deployment.md`
   - Project-specific long sections → a new file under `.claude/docs/`
2. Replace the moved section in `CLAUDE.md` with a one-line pointer in the "Reference files (loaded on demand)" section (no `@`-prefix — those auto-expand and defeat the purpose).
3. Verify `CLAUDE.md` is now ≤ 200 lines with `wc -l`.
4. Report what was moved where in the Step 10 summary.

**Keep in `CLAUDE.md` regardless of length:** Critical rules, execution mode, priority order, workflow overview, and the reference-files pointer section. These must stay in-session because they govern every action.

If `CLAUDE.md` is already ≤ 200 lines, report `[SLIM CHECK] OK` and move on.

### Step 10: Report

Write a summary:

```
Synced from template repo (YYYY-MM-DD):
- [CREATED] filename — reason
- [UPDATED] filename — what changed
- [SKIPPED] filename — why (already current / not relevant)
- [REMOVED] filename — not relevant for project tech stack
- [TRANSLATED] filename — migrated from Swedish to English

Project-specific preserved:
- filename — what was preserved

Manual review recommended:
- filename — why
```

### Rules

- Communicate in English
- Code is written in English
- NEVER change the project's core logic or application code
- ALWAYS preserve project-specific customizations (marked with `# PROJECT-SPECIFIC` or clearly unique to the project)
- If unsure: report and ask instead of changing
- Do NOT commit automatically — let the developer review first
- **Step 9 (slim CLAUDE.md check) runs ALWAYS** — including when the project is reported as up-to-date in Step 0

---
