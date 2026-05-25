# Workflows and tools

## Spec-driven workflow

If the project uses a spec kit or similar:

- Prioritize the spec kit's workflow first.
- All implementations start from the specification.
- Deviations require explicit approval.
- Default task: [E.g., "Find the highest numbered incomplete spec and implement it."]

## Frontend design skill — details

**Trigger words requiring frontend-design skill:**

- Design, appearance, layout, styling, CSS, color, font, typography
- Button, form, navbar, footer, header, sidebar, modal, card
- Responsive, mobile, dark mode, theme, animation
- "Nicer", "prettier", "more modern", "more professional", "better looking"

**Correct order:**

1. User asks about something UI-related
2. **FIRST:** Invoke the `Skill` tool with `skill: "frontend-design"`
3. **THEN:** Follow the instructions from the skill for implementation

## Humanizer skill — details

**CRITICAL — BLOCKING REQUIREMENT:** 100% of all generated text aimed at humans MUST be run through the `humanizer` skill before delivery.

**Applies to:**

- Commit messages and PR descriptions
- Documentation, README files, CHANGELOG
- Emails, articles, blog posts
- Comments on issues/PRs
- All prose text delivered to the user

**Does NOT apply to:**

- Code (variables, functions, classes)
- Technical logs and error messages
- JSON, YAML, configuration files
- Inline comments in code (English, technical)

**Correct order:**

1. Generate the text
2. **FIRST:** Invoke the `Skill` tool with `skill: "humanizer"`
3. **THEN:** Deliver the humanized text

## Skills

Skills are instruction files (SKILL.md) with YAML frontmatter that give Claude specialized capabilities. Claude Code follows the Agent Skills standard (agentskills.io).

### Key concepts

- **`context: fork`** — run the skill in an isolated subagent, keep the main context clean
- **`disable-model-invocation: true`** — only the user can invoke (for deploy, commit, dangerous operations)
- **`user-invocable: false`** — background knowledge, hidden from the / menu
- **`allowed-tools`** — tools without permission prompt within the skill
- **`${CLAUDE_SKILL_DIR}`** — reference files relative to the skill's folder
- **`hooks`** — hooks scoped to the skill's lifecycle (instead of global settings.json)

### Difference: Skills vs Commands

Slash commands (`.claude/commands/`) and skills (`.claude/skills/`) have been merged since v2.1.3. Both create `/slash-commands` and function identically. Skills are recommended as they support more features.

### Built-in skills (shipped with Claude Code)

| Skill | Description |
| --- | --- |
| `/simplify` | Reviews changed files with 3 parallel agents (reuse, quality, efficiency) |
| `/batch <instruction>` | Orchestrates large-scale changes in parallel in isolated git worktrees |
| `/loop [interval] <prompt>` | Runs a prompt repeatedly on an interval |
| `/debug [description]` | Debug the current session |
| `/claude-api` | Loads Claude API reference for your project language |

See `.claude/docs/skills.md` for full skills reference.

## Plugins

Plugins bundle skills, agents, hooks, MCP servers, and LSP servers in a distributable package. Installed with `/plugin install`.

**Difference from skills:**

- **Skill** = a SKILL.md file with instructions (runs in main context or forked)
- **Plugin** = a package that can contain skills + agents + hooks + MCP + LSP

### LSP plugins and installation

See `.claude/docs/skills.md` for LSP plugins (C#, TypeScript, PHP) and installation commands.

### Common plugins

```bash
# Project management
/plugin install github@claude-plugins-official

# Other useful plugins
/plugin install sentry@claude-plugins-official     # Error tracking
/plugin install slack@claude-plugins-official       # Communication
```

### Plugin scopes

| Scope | File | Applies to |
| --- | --- | --- |
| `user` (default) | `~/.claude/settings.json` | All your projects |
| `project` | `.claude/settings.json` | Everyone on the team (via git) |
| `local` | `.claude/settings.local.json` | Only you, in this repo |

```bash
/plugin install <name>@<marketplace> --scope project  # Shared with team
/plugin disable <name>@<marketplace>                   # Disable
/plugin update <name>@<marketplace>                    # Update
```

## Hooks (deterministic rules)

Consider Claude Code hooks (`.claude/settings.json`) for rules that MUST be followed without exception. Unlike CLAUDE.md instructions which are advisory, hooks are deterministic and guaranteed.

### Hook events (27)

| Hook event | When triggered |
| --- | --- |
| `SessionStart` | Session starts or resumes. Matcher: `compact`, `resume`, `new` |
| `SessionEnd` | Session ends. Matcher: `clear`, `logout`, `prompt_input_exit`, `other` |
| `Setup` | One-time run on first session — good for installation scripts |
| `UserPromptSubmit` | User submits a prompt — can block or inject context |
| `PreToolUse` | Before a tool call — can block or modify input |
| `PermissionRequest` | Permission dialog shown — can auto-approve or deny |
| `PermissionDenied` | After auto mode classifier denials — return `{retry: true}` to retry |
| `PostToolUse` | After a successful tool call |
| `PostToolUseFailure` | After a failed tool call — can provide corrective feedback |
| `Notification` | Notifications (`permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`) |
| `SubagentStart` | A subagent starts |
| `SubagentStop` | A subagent stops |
| `Stop` | Claude stops responding — can force continuation |
| `StopFailure` | Session ends due to API error — can provide corrective feedback |
| `TeammateIdle` | Agent team member about to go idle — can force continuation |
| `TaskCreated` | A task is created (agent teams) — can validate or inject context |
| `TaskCompleted` | A task is marked done — can block if quality conditions not met |
| `PreCompact` | Before context compaction — good for preserving critical context |
| `PostCompact` | After context compaction — can inject context that was lost |
| `Elicitation` | MCP server requests structured input — can auto-answer |
| `ElicitationResult` | User answers MCP elicitation |
| `ConfigChange` | Configuration file changes during session — can block the change |
| `InstructionsLoaded` | Instructions (CLAUDE.md, skills) loaded — can inject extra context |
| `CwdChanged` | Working directory changes — reactive environment management (e.g., direnv) |
| `FileChanged` | A file changes on disk — reactive monitoring |
| `WorktreeCreate` | Git worktree created |
| `WorktreeRemove` | Git worktree removed |

### Four types of hooks

- `command` — runs a shell command. Receives JSON via stdin, returns JSON via stdout. Supports `"async": true` and `"asyncRewake": true` (background that wakes the model on exit code 2)
- `http` — sends JSON as HTTP POST to a URL. Configured with `url`, `headers`, `allowedEnvVars`
- `prompt` — single-turn evaluation with Claude (Haiku), returns `{ "ok": true/false, "reason": "..." }`
- `agent` — multi-turn verification with tool access (Read, Grep, Glob), up to 50 turns

### Filter hooks with `if` field (v2.1.85)

Use `if` to restrict WHEN a hook triggers, with permission rule syntax:

```json
{
  "matcher": "Bash",
  "hooks": [{
    "type": "command",
    "if": "Bash(git *)",
    "command": "./scripts/check-git-policy.sh"
  }]
}
```

`if` matches on the tool's arguments — the hook above only triggers for `Bash` calls starting with `git`. Without `if`, it triggers for ALL Bash calls.

### Defer permission decision (v2.1.89)

For headless sessions (`claude -p`), PreToolUse hooks can return `permissionDecision: "defer"` to pause the session. Resume later with `-p --resume` to have the hook re-evaluate.

### Hooks in skills and agents

Since v2.1.0, hooks can be defined directly in SKILL.md and agent frontmatter, scoped to the component's lifecycle:

```yaml
---
name: my-skill
hooks:
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---
```

Benefit: hooks follow the skill/agent instead of being centralized in settings.json.

### Blocking and control

Hooks block via:

- **Command:** exit code `2` = block (NOTE: `exit 1` does NOT block, it's just an error)
- **Command (PreToolUse):** JSON output with `hookSpecificOutput.permissionDecision: "deny"` = block. NOTE: top-level `decision`/`reason` fields are **deprecated** for PreToolUse — use `hookSpecificOutput` instead
- **Command (other events):** top-level `decision`/`reason` still works
- **Prompt/Agent:** `{ "ok": false, "reason": "..." }` = block
- **Permissions.deny** in settings.json = deterministic blocking, but has known bugs — see `.claude/docs/security.md`

### Async hooks (background execution)

Set `"async": true` on command hooks to run them in the background without blocking Claude. The result is delivered on the next conversation turn via `systemMessage`.

```json
{
  "matcher": "Edit|Write",
  "hooks": [{
    "type": "command",
    "command": "dotnet build 2>&1 | tail -5",
    "async": true,
    "timeout": 60
  }]
}
```

**Limitations:** Async hooks cannot block, only `type: "command"` is supported, and output is delivered on the next turn.

### JSON output from hooks

| Field | Description |
| --- | --- |
| `systemMessage` | Warning message to the user |
| `additionalContext` | Extra context for Claude |
| `continue` | `false` = stop Claude entirely |
| `stopReason` | Message when `continue: false` |
| `suppressOutput` | Hide stdout from verbose mode |
| `updatedInput` | Modify the tool's input (PreToolUse, PermissionRequest) |
| `updatedMCPToolOutput` | Replace MCP tool output (PostToolUse) |

### Environment variables in hooks

| Variable | Description |
| --- | --- |
| `$CLAUDE_PROJECT_DIR` | Project root directory |
| `$CLAUDE_ENV_FILE` | Path where SessionStart hooks can write `export` statements |
| `$CLAUDE_CODE_REMOTE` | `"true"` in remote/web environments |
| `$CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | Set to `1` to strip Anthropic/cloud credentials from subprocess environments |
| `${CLAUDE_PLUGIN_ROOT}` | Plugin root directory |

### Common automations

- Post-edit hook: run linter after every file change
- Pre-commit hook: run `dotnet build` before commit
- Blocking hook: `permissions.deny` in settings.json (prefer this over hooks)
- Stop hook (agent): verify tests pass before Claude stops
- Async post-edit: run tests in the background while Claude continues working
- PreCompact hook: preserve critical context during compaction

## Subagents

Create dedicated subagents in `.claude/agents/` for isolated tasks that should not fill the main context. Subagents run in their own context windows and report back summaries.

Create via the `/agents` command or manually as markdown files.

### YAML frontmatter — complete reference

```yaml
---
name: agent-name              # Required. Lowercase and hyphens
description: When to use      # Required. Claude uses this for delegation
tools: Read, Grep, Glob       # Optional. Allowlist for tools
disallowedTools: Write, Edit  # Optional. Denylist
model: sonnet                 # Optional. sonnet|opus|haiku (default: inherit)
permissionMode: default       # Optional. default|acceptEdits|dontAsk|plan|bypassPermissions
maxTurns: 20                  # Optional. Max number of agent turns
memory: project               # Optional. user|project|local (persistent memory)
isolation: worktree            # Optional. Run in isolated git worktree
background: false              # Optional. true = run in background (MCP not available)
initialPrompt: "start here"   # Optional. Auto-submitted as first user turn
skills:                        # Optional. Skills to load (NOT inherited from parent)
  - api-conventions
mcpServers:                    # Optional. MCP servers available to the agent
  - server-name
hooks:                         # Optional. Hooks scoped to this agent
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---

System prompt starts here. The agent receives ONLY this prompt.
```

### Field descriptions

| Field | Description |
| --- | --- |
| `name` | Unique ID, lowercase and hyphens |
| `description` | **Critical** — Claude delegates based on this. Include "Use proactively" for automatic use |
| `tools` | Allowlist. Omitted = inherits all tools |
| `disallowedTools` | Denylist. Removed from inherited tools |
| `model` | `opus` (most capable), `sonnet` (balance), `haiku` (fastest/cheapest) |
| `permissionMode` | `acceptEdits` auto-approves file changes, `plan` = read-only, `bypassPermissions` = skip all |
| `memory` | `user` = all projects, `project` = shareable via git, `local` = only you |
| `isolation` | `worktree` = isolated git copy, cleaned up automatically if no changes |
| `background` | Run while you continue working. MCP tools not available |
| `initialPrompt` | Auto-submitted as first user turn when running as main session agent via `--agent` |
| `skills` | Full skill content injected at start. NOT inherited from parent |
| `mcpServers` | MCP servers available to the agent. Server name or inline definition |
| `hooks` | Hooks scoped to the agent's lifecycle |

### Placement

| Location | Scope |
| --- | --- |
| `.claude/agents/` | Project-specific (shared via git) |
| `~/.claude/agents/` | Personal (all projects) |

### Copy-paste agent templates

See `.claude/docs/agents-templates.md` for ready-made agents for .NET/fullstack projects:

- **dotnet-reviewer** — code review with worktree isolation
- **security-scanner** — security scanning in isolated worktree
- **test-runner** — run tests in the background
- **db-agent** — EF Core migrations, schema, queries

## Agent Teams (experimental)

Multiple Claude Code instances working together with direct communication and a shared task list. One session is team leader, the rest are members.

**Enable:**

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

**Difference from subagents:**

- Subagents only report back results
- Team members communicate directly with each other and coordinate independently

**Best for:** Complex tasks with multiple parallel tracks (frontend + backend + tests).

## Parallel sessions

- **Writer/Reviewer**: One session implements, another reviews
- **Fan-out**: `for file in $(cat files.txt); do claude -p "Migrate $file" --allowedTools "Edit"; done`

## Thinking triggers

- `think` → ~4,000 tokens thinking budget
- `think hard` → ~10,000 tokens
- `ultrathink` → ~32,000 tokens (recommended for architecture decisions and difficult debugging)

## Model and output

- Default model: Opus 4.6 with 1M token context window (Max/Team/Enterprise)
- Default max output: 64k tokens, upper limit 128k tokens (Opus 4.6 and Sonnet 4.6)
- Fast mode (`/fast`) uses the same Opus 4.6 with faster output — does NOT switch model

## Session management

- `claude --continue` — resume the latest session
- `claude --resume` — choose from previous sessions
- `claude -p "..." --bare` — scripted calls without hooks, LSP, plugin sync, or skill walks
- `/rewind` or `Esc+Esc` — go back to an earlier checkpoint
- `/rename` — give the session a descriptive name for easy retrieval
- `/compact <instructions>` — controlled compaction with focus area, e.g., `/compact Focus on the API changes`
- `/context` — show current context usage and loaded skills
- `/voice` — push-to-talk voice mode (hold spacebar to talk)
- `/hooks` — read-only view of all configured hooks
- `/btw` — side questions in a dismissible overlay without entering conversation history
- `--channels` — permission relay that can forward approval prompts to your phone

## Auto memory (MEMORY.md)

Claude automatically saves useful insights to `~/.claude/projects/<project>/memory/MEMORY.md`. The first 200 lines are loaded in every session.

- Say "remember that we use X" to save specific information
- Use `/memory` to open and edit memory files in the editor
- Create topic files (e.g., `debugging.md`, `api-conventions.md`) for details and link from MEMORY.md
- Only save verified patterns — not speculation or session-specific context

## Status line (context monitoring)

Show context usage in real-time with a custom status line in settings.json:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Anthropic recommends monitoring context usage continuously — performance degrades as the context window fills up.

## Sandbox (OS-level isolation)

Claude Code supports built-in sandbox with filesystem and network isolation via settings.json:

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "failIfUnavailable": true,
    "filesystem": {
      "allowWrite": ["//tmp/build"],
      "denyRead": ["~/.aws/credentials"]
    },
    "network": {
      "allowedDomains": ["github.com", "*.npmjs.org"]
    }
  }
}
```

- `failIfUnavailable: true` — abort with error if sandbox cannot start, instead of running unsandboxed (new March 2026)
- Alternatively: `/sandbox` in session to activate. Provides similar autonomy to `--dangerously-skip-permissions` but with safer boundaries.

## Managed settings (organizational policies)

Use `managed-settings.d/` drop-in directory for separate teams to deploy independent policy fragments that merge alphabetically. Each team can maintain their own settings file without conflicts.

## Iterative improvement

If the same mistake repeats, suggest a new rule for CLAUDE.md or a hook that prevents it.
