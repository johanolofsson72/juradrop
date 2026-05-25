# Local LLM offload (Ollama)

Auto-detected hook layer that pushes low-stakes work to a local model when one is reachable. When Ollama is offline or disabled, every hook becomes a silent no-op and Claude works as before.

## Default-wired hooks (token-savers only)

The template ships with **only the hooks that demonstrably reduce Anthropic token consumption** wired into `settings.json`. They follow the artifact pattern: produce a digest or scaffold to a file Claude rereads cheaply on follow-up turns instead of regenerating or re-ingesting the underlying tool output.

**Routing and orientation:**

| Hook | Saves tokens by |
|------|----------------|
| `local-llm-classify-hook.sh` | Tagging the prompt so Claude can skip heavy skills (Allium / TLA+) on simple work |
| `local-llm-orientation-hook.sh` | Replacing the SessionStart `git log` / `status` / `diff` discovery roundtrip |

**Git workflow drafts:**

| Hook | Saves tokens by |
|------|----------------|
| `local-llm-commit-draft-hook.sh` | Pre-drafting the commit message to a file so Claude refines instead of regenerating |
| `local-llm-pr-draft-hook.sh` | Pre-drafting the PR title + Summary + Test plan to a file |
| `local-llm-changelog-hook.sh` | Pre-drafting `CHANGELOG.md` entries grouped by Conventional type |

**GitHub context digests** (cached per call, reread on follow-up turns):

| Hook | Saves tokens by |
|------|----------------|
| `local-llm-gh-run-view-hook.sh` | Digesting `gh run view` CI output (typically 5000+ lines) into a per-job failure summary |
| `local-llm-gh-pr-view-hook.sh` | Digesting `gh pr view` into PR meta + decisions + open threads |
| `local-llm-gh-issue-view-hook.sh` | Digesting `gh issue view` into problem + discussion + decisions + next |

**Speckit feature pipeline:**

| Hook | Saves tokens by |
|------|----------------|
| `local-llm-tasks-draft-hook.sh` | Drafting initial `tasks.md` from a written `spec.md` so `/tasks` refines instead of generating |
| `local-llm-plan-draft-hook.sh` | Drafting initial `plan.md` from a written `spec.md` so `/plan` refines instead of generating |

**Project-init scaffolds:**

| Hook | Saves tokens by |
|------|----------------|
| `local-llm-readme-skeleton-hook.sh` | Scaffolding a brand-new `README.md` from detected repo signals |
| `local-llm-gitignore-skeleton-hook.sh` | Scaffolding a brand-new `.gitignore` from detected repo stacks |
| `local-llm-dotenv-example-hook.sh` | Scaffolding `.env.example` from env-var references grepped out of the codebase |

The remaining hook scripts in `scripts/local-llm-*-hook.sh` are **quality gates** — they catch bugs by injecting advisory context. They cost tokens, they don't save them. Wire them into `settings.json` per project when the bug-catching value is worth the per-fire context overhead, but do not enable them by default.

## What can be offloaded (full catalog)

| Hook | Trigger | What the local LLM does |
|------|---------|------------------------|
| `local-llm-classify-hook.sh` | `UserPromptSubmit` | Tags the prompt as TRIVIAL / MEDIUM / COMPLEX. Inject as routing hint so Claude can skip heavy skills (Allium, TLA+) on quick questions. |
| `local-llm-bash-tldr-hook.sh` | `PostToolUse` on `Bash`, output > 4000 chars | Three-line TLDR (WHAT / KEY / VERDICT) appended as additional context. |
| `local-llm-commit-draft-hook.sh` | `PostToolUse` on `Bash` matching `git add` | Generates a Conventional Commit draft from staged diff. Saved to `.claude/.local-llm-commit-draft.md`. |
| `local-llm-humanize-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.md`, `README*`, `CHANGELOG*`, `CONTRIBUTING*` | Scans for AI-tells (em-dash overuse, inflated vocab, rule of three, hollow openers). Reports issues; does not modify the file. |
| `local-llm-stacktrace-hook.sh` | `PostToolUse` on `Bash`, output > 2000 chars and contains error/exception keywords | Extracts ERROR / LOCATION / CAUSE from stack traces — three lines giving the error type, first user-code frame, and likely root cause. |
| `local-llm-pr-draft-hook.sh` | `PostToolUse` on `Bash` matching `git push -u origin <branch>` | Reads the diff between branch and main, drafts PR title + Summary + Test plan. Saved to `.claude/.local-llm-pr-draft.md`. |
| `local-llm-spec-criteria-hook.sh` | `PostToolUse` on `Edit`/`Write` for `specs/<id>/spec.md` and `.specify/specs/<id>/spec.md` | Scans Acceptance Criteria for vague/untestable language ("works well", "is fast"), suggests measurable replacements. |
| `local-llm-changelog-hook.sh` | `PostToolUse` on `Edit`/`Write` for `CHANGELOG.md` | Reads commits since last tag, groups by Conventional type, drafts entries in keep-a-changelog format to `.claude/.local-llm-changelog-draft.md`. |
| `local-llm-orientation-hook.sh` | `SessionStart` (every session) | "Where you left off" — reads recent git log, status, diff, active specs and produces 5-8 line orientation injected as additionalContext. Disable per-session with `LOCAL_LLM_ORIENTATION_DISABLE=1`. |
| `local-llm-tlc-translate-hook.sh` | `PostToolUse` on `Bash` matching TLC commands, output contains counterexample/invariant/deadlock | Translates TLA+ TLC counterexample traces from TLA+ syntax to plain-English step-by-step (VIOLATION / STEP N / ROOT CAUSE / NEXT ACTION). |
| `local-llm-migration-safety-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.sql`, `*Migrations/*.cs`, `*/migrations/*.sql`, `*/db/migrate/*.rb` | Scans DB migrations for production-unsafe patterns (NOT NULL without default, DROP COLUMN without rename, missing FK index, non-online ALTER on big tables). |
| `local-llm-test-gap-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.cs`/`*.tsx`/`*.ts` (skip test/generated/migrations) | Finds matching test file, lists public methods without tests. Backs CLAUDE.md's "every implemented function needs a test" rule. |
| `local-llm-async-audit-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.cs` (skip tests/generated/migrations) | Scans for sync-over-async (`.Result`/`.Wait()`), missing `await`, blocking I/O in async, `async void` on non-events, missing `ConfigureAwait(false)` in libs. |
| `local-llm-auth-check-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*Controller.cs` or files in `Controllers/` | Verifies each HTTP action method has explicit `[Authorize]` or `[AllowAnonymous]`. Surfaces silent inheritance. |
| `local-llm-linq-perf-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.cs` | Catches LINQ inefficiencies (multi-enum of same `IEnumerable`, `ToList()` in loops, `.Where().Count()` vs `.Count(predicate)`, sync EF queries). |
| `local-llm-test-name-hook.sh` | `PostToolUse` on `Edit`/`Write` for test files | Vague test names (`Test1`, `Foo`, `MethodTest`) → descriptive `Method_Scenario_Expected` suggestions. |
| `local-llm-test-assertion-hook.sh` | `PostToolUse` on `Edit`/`Write` for test files | Tests with no assertion call (no `Assert.*`, `.Should()`, `expect()`, `Verify()`) — flagged as coverage placebos. |
| `local-llm-test-realism-hook.sh` | `PostToolUse` on `Edit`/`Write` for test files | Mocks/stubs with `""`, `null`, `0`, `"test"`, `"x"` → suggests realistic values. Lenient about explicit boundary tests. |
| `local-llm-task-traceability-hook.sh` | `PostToolUse` on `Edit`/`Write` for `tasks.md` in speckit specs | Maps tasks ↔ acceptance criteria; reports orphan tasks and orphan criteria. |
| `local-llm-allium-drift-rank-hook.sh` | `PostToolUse` on `Bash` matching `allium distill` | Ranks each drift finding HIGH/MEDIUM/LOW for release-blocking severity, ends with `RELEASE_GATE: BLOCKED|PROCEED-WITH-FOLLOWUPS`. |
| `local-llm-allium-openq-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.allium` | Extracts `open question`, `-- AMBIGUITY:`, `deferred` markers as actionable items requiring decision. |
| `local-llm-dockerfile-review-hook.sh` | `PostToolUse` on `Edit`/`Write` for `Dockerfile`/`Dockerfile.*` | Missing HEALTHCHECK, root user, `:latest` tag, secrets in ENV, missing `.dockerignore`, layer-bloat patterns. |
| `local-llm-branch-name-hook.sh` | `PostToolUse` on `Bash` matching `git checkout -b` / `git switch -c` | When new branch has lazy name (`fix`, `wip`, `temp`), suggests 3 descriptive alternatives + `git branch -m` rename command. |
| `local-llm-pr-splitter-hook.sh` | `PostToolUse` on `Bash` matching `git push -u origin` if diff > 500 lines | Suggests 2-4 natural splits by file groupings + merge order, or marks as `COHESIVE` if single coherent change. |
| `local-llm-react-deps-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.tsx`/`*.ts`/`*.jsx`/`*.js` (skip tests/vendored), only if file uses `useEffect`/`useCallback`/`useMemo`/etc. | Detects missing dependencies in React hook arrays (the canonical stale-closure bug source) plus empty/missing deps arrays and conditional hooks. |
| `local-llm-n1-query-hook.sh` | `PostToolUse` on `Edit`/`Write` for `*.cs` (skip tests/migrations), only if file has both an enumeration and an awaited db/repo call | Catches the N+1 anti-pattern: `foreach (var x in collection) await _db.LoadAsync(x.Id)`. |
| `local-llm-secret-scan-hook.sh` | `PostToolUse` on `Edit`/`Write` for source/config files (skip vendored, lock files, binaries) | Regex pre-filter catches likely secret patterns; llama3 distinguishes real leaks from false positives (variable names, type annotations, env-var lookups, test placeholders). |
| `local-llm-todo-catalog-hook.sh` | `PostToolUse` on `Edit`/`Write` when file accumulates ≥3 TODO/FIXME/HACK/XXX/TBD markers | Catalogs each marker by category and priority so accumulating debt becomes visible. |
| `local-llm-spec-scope-hook.sh` | `PostToolUse` on `Edit`/`Write` for `specs/<id>/spec.md` with both Scope and Acceptance Criteria sections | Detects acceptance criteria that fall outside the declared scope — undeclared scope creep. |
| `local-llm-plan-feasibility-hook.sh` | `PostToolUse` on `Edit`/`Write` for `specs/<id>/plan.md` | Flags unrealistic estimates, missing critical phases (testing, deploy, rollback), tech-stack conflicts (cross-references CLAUDE.md), and hand-wavy steps. |

The humanize hook excludes Claude-internal markdown (`CLAUDE.md`, `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/docs/`, `.specify/`) so it only fires on human-facing copy.

## Detection

`scripts/local-llm-detect.sh` is sourced by every hook script. It pings `${OLLAMA_HOST}/api/tags` with a 1-second timeout. On success it sets `LOCAL_LLM_AVAILABLE=1`; on failure it sets `0` and the hook exits without touching the network again.

Detection is cheap. The expensive call is the `/api/generate` request inside each hook, which uses `LOCAL_LLM_TIMEOUT` (default 15s).

## Built-in token-saving optimizations

Three mechanisms inside `local-llm-call.sh` and a few hooks cut prompt volume. They do not change what gets caught, only how cheaply.

### Response cache

Every call through `local-llm-call.sh` keys on `sha256(model || system || user_prompt || num_predict)`. A hit inside the TTL window returns the previous response without touching Ollama. Identical input bytes produce the same key, so the cache is correct by construction. A file edit changes the content hash and forces a miss.

Storage lives at `<repo>/.claude/.local-llm-cache/<sha>.txt` per project. The `.claude/.local-llm-*` gitignore pattern already covers it.

TTL is enforced via file mtime on read. Stale entries get removed lazily on first miss.

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOCAL_LLM_CACHE_TTL` | `600` | Cache lifetime in seconds. Bump to `1800` for long sessions on the same files. |
| `LOCAL_LLM_CACHE_DISABLE` | unset | Set to `1` to bypass the cache (telemetry still records). |
| `LOCAL_LLM_CACHE_DIR` | `<repo>/.claude/.local-llm-cache` | Override storage location. |

Telemetry now writes a 7th column `cache_hit` (0|1) per row. `local-llm-stats.sh` exposes a `cache%` column and reports the per-window total of prompt bytes the cache spared.

### Per-hook content gates

A hook should grep for its minimum input shape before calling the model. The grep runs in microseconds; the savings compound across every fire.

Concrete examples currently shipping:

- `local-llm-async-audit-hook.sh` requires one of `async`, `await`, `Task<.>`, `.Result`, `.Wait()`, `Thread.Sleep`, `ConfigureAwait`, or `ValueTask` in the file. A sample of 200 `.cs` files in a real .NET project showed 74% gated out — POCOs, config classes, mappers, entity types, enums.
- `local-llm-n1-query-hook.sh` requires both a loop construct (`foreach`, `.Select`, `for`) and an awaited DB/repo call (`await _db.*Async`, `LoadAsync`, `ToListAsync`).
- `local-llm-stacktrace-hook.sh` greps for error/exception keywords in the captured Bash output first.

When you add a new hook, decide its minimum input shape, then grep for it before invoking the model. A gate that skips half the fires saves more than any prompt tuning.

### Spec section extraction

`local-llm-plan-draft-hook.sh` and `local-llm-tasks-draft-hook.sh` no longer feed the whole `spec.md` to the model. An awk pass extracts the load-bearing sections (Feature, Overview, User Story, Acceptance, Goals, Requirements, Constraints, Scope, Out of scope, Functional, Background, Context, Problem, Solution; plus Test/Coverage for tasks-draft). History, references, changelogs, and free-form prose get dropped.

A 24631-byte production spec extracts to 6375 bytes (74% reduction). That fits under the 12000-char cap and far below the segmentation ceiling that used to make both hooks time out at 15s.

If extraction returns under 500 bytes (a spec with non-standard headings), the hook falls back to a 12000-byte head capture so it still produces a draft instead of nothing.

## Configuration

All env vars are optional. Set them in your shell profile or a project-local `.env` you source manually.

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Ollama base URL. Defaults to IPv4 loopback explicitly to avoid Happy-Eyeballs routing to a different ollama instance when both IPv4 and IPv6 listeners exist on port 11434. |
| `LOCAL_LLM_MODEL` | `llama3` | Model tag for `ollama pull`. Untagged resolves to whatever `llama3:latest` points to on the host (8B by default). |
| `LOCAL_LLM_TIMEOUT` | `15` | Generation timeout in seconds. |
| `LOCAL_LLM_DETECT_TIMEOUT` | `1` | Reachability ping timeout. |
| `LOCAL_LLM_DISABLE` | unset | Set to `1` to force-disable every offload hook. |
| `LOCAL_LLM_CLASSIFY_TIMEOUT` | `4` | Tighter timeout for the `UserPromptSubmit` classifier so the prompt path stays snappy. |
| `LOCAL_LLM_TLDR_MIN_CHARS` | `4000` | Minimum Bash output size before the TLDR hook fires. |
| `LOCAL_LLM_STACKTRACE_MIN_CHARS` | `2000` | Minimum Bash output size before the stack-trace distiller fires. |
| `LOCAL_LLM_ORIENTATION_DISABLE` | unset | Set to `1` to skip the SessionStart "where you left off" orientation. Useful for ephemeral sessions where the orientation overhead outweighs the value. |
| `LOCAL_LLM_PR_SPLIT_MIN_LINES` | `500` | Minimum changed-line count before the PR splitter offers split suggestions on `git push -u origin`. |
| `LOCAL_LLM_TODO_MIN_COUNT` | `3` | Minimum TODO/FIXME/HACK marker count in a single file before the TODO catalog fires. |
| `LOCAL_LLM_TELEMETRY_LOG` | `<repo>/.claude/local-llm-fire.log` (per-project; falls back to `~/.claude/` outside a repo) | Tab-separated per-fire log. Schema v3: `timestamp \t hook \t exit_code \t duration_ms \t prompt_bytes \t response_bytes \t cache_hit`. |
| `LOCAL_LLM_TELEMETRY_DISABLE` | unset | Set to `1` to skip writing the telemetry row. |
| Cache settings | see [Built-in token-saving optimizations](#response-cache) | `LOCAL_LLM_CACHE_TTL`, `LOCAL_LLM_CACHE_DISABLE`, `LOCAL_LLM_CACHE_DIR` |

## Telemetry and ROI

Every offload funnels through `local-llm-call.sh`, which appends one tab-separated row per attempt to `${LOCAL_LLM_TELEMETRY_LOG}`. The hook name is auto-derived from the parent process, so individual hooks need no changes.

Run `scripts/local-llm-stats.sh` to see fires / success-rate / avg latency / wasted-on-timeouts time per hook. Use `--since 1d` (or `1h`, or an ISO date) to narrow the window. Hooks that fire often but rarely return useful output are candidates for tighter triggers or removal.

## Setup

1. Install Ollama: `brew install ollama` (or your platform equivalent).
2. Pull the model: `ollama pull llama3` (or set `LOCAL_LLM_MODEL` to whatever you have, e.g. `qwen2.5:7b`).
3. Start the daemon: `ollama serve` (or just run it once; it stays warm in the background).
4. Verify: `curl -s http://127.0.0.1:11434/api/tags | jq '.models[].name'`.

That is the entire setup. Hooks pick up Ollama on the next prompt.

## Disabling

- Prefix a single command with `LOCAL_LLM_DISABLE=1` to skip the offload for that one invocation.
- Run `export LOCAL_LLM_DISABLE=1` to kill it for the whole shell session.
- Drop the four `local-llm-*-hook.sh` entries from `.claude/settings.json` to disable project-wide.

You can also stop Ollama (`pkill ollama` / quit the menubar app); detection fails silently and Claude reverts to its native behaviour.

## Cost model

The offload trades Anthropic tokens for local CPU/GPU time and a small amount of latency on every hook fire. The classifier adds ~1-3s to each user prompt; the TLDR fires only on big outputs; the commit-draft fires only on `git add`; the humanize hook fires only on documentation files.

If latency on the prompt path bothers you, set `LOCAL_LLM_CLASSIFY_TIMEOUT=2` or remove the classify hook entry from `settings.json`.

## Failure modes

Every hook is built to fail open: any error (offline, timeout, missing model, malformed JSON) results in an empty stdout and exit 0/1, which Claude Code treats as no additional context. The hooks never block tool execution and never produce errors that surface to the user.

If you want to confirm a hook is firing, run with `CLAUDE_LOG_HOOKS=1` (Claude Code's own debug flag) or invoke the script directly with synthetic input.
