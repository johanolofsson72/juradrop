# Skills

Skills give Claude specialized capabilities through SKILL.md files with instructions and frontmatter. Claude Code follows the Agent Skills standard (agentskills.io) — the ecosystem has grown to 349+ skills in 12 categories (March 2026). OpenAI has adopted the same format for Codex CLI.

## How skills work

### Progressive loading

1. **Metadata** (~100 tokens) — `name` + `description` loaded at session start for ALL skills
2. **Instructions** (<5000 tokens recommended) — full SKILL.md loaded on activation
3. **Resources** (on demand) — support files loaded when referenced

### Invocation methods

- **Manual:** User types `/skill-name` (slash command)
- **Automatic:** Claude loads the skill based on `description` matching
- **Blocking:** Skills with `disable-model-invocation: true` can only be invoked manually

## Project skills (`.claude/skills/`)

These skills ship with the template repo:

| Skill | Type | Description |
| --- | --- | --- |
| `/allium` | standard | Allium spec language — elicit formal specs, distill specs from code |
| `/code-review` | `context: fork` | Code review with isolated context |
| `/deploy-checklist` | `disable-model-invocation` | Pre-deploy verification with stress testing (manual only) |
| `/explore-codebase` | `context: fork` | Deep architecture analysis via Explore agent |
| `/sync-template` | `disable-model-invocation` | Syncs project configuration from template repo |
| `/tla` | standard | TLA+ formal verification — invariants, state machines, race conditions |
| `/update-template` | standard | Searches online for latest best practices and updates the template repo |

## SKILL.md structure

### Required fields (Agent Skills standard)

```yaml
---
name: my-skill          # Lowercase, digits, hyphens. Max 64 characters. Matches folder name.
description: >          # Max 1024 characters (but keep under 250 for best context efficiency).
  Reviews code for bugs and security issues.
  Use when asking for code review or after significant changes.
---
```

### Optional fields (Claude Code extensions)

```yaml
---
argument-hint: "[issue-number]"       # Hint at autocomplete
disable-model-invocation: true        # Only the user can invoke (deploy, commit)
user-invocable: false                 # Hide from / menu (background knowledge)
allowed-tools: Read, Grep, Glob       # Tools without permission prompt
model: sonnet                        # Override model (sonnet|opus|haiku)
effort: high                          # Override effort level (low|medium|high)
paths: "**/*.cs, **/*.csproj"         # Glob patterns — skill auto-activates only for matching files
shell: bash                           # Shell for !`command` blocks (bash|powershell)
context: fork                         # Run in isolated subagent context
agent: Explore                        # Subagent type (Explore, Plan, general-purpose, custom)
hooks:                                # Hooks scoped to skill lifecycle
  PostToolUse:
    - matcher: "Edit"
      hooks:
        - type: command
          command: "./scripts/lint.sh"
---
```

### Invocation control

| Frontmatter | User | Claude | Loading |
| --- | --- | --- | --- |
| (default) | Yes | Yes | Description always, full on invocation |
| `disable-model-invocation: true` | Yes | No | Description NOT in context |
| `user-invocable: false` | No | Yes | Description always in context |

## String substitutions

| Variable | Description |
| --- | --- |
| `$ARGUMENTS` | All arguments at invocation |
| `$ARGUMENTS[N]` / `$N` | Specific argument (0-based) |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_SKILL_DIR}` | Folder containing SKILL.md |

## Dynamic context injection

Run shell commands during preprocessing with `` !`command` ``:

```markdown
## PR context
- Diff: !`gh pr diff`
- Comments: !`gh pr view --comments`
```

## Directory structure for skills

```text
my-skill/
├── SKILL.md           # Required — main instructions
├── scripts/           # Executable helper scripts
│   └── helper.py
├── references/        # Reference material (loaded on demand)
│   └── REFERENCE.md
└── assets/            # Static resources (templates, schemas)
    └── template.html
```

## Placement and priority

| Location | Path | Applies to |
| --- | --- | --- |
| Enterprise | Managed settings | Everyone in the organization |
| Personal | `~/.claude/skills/<skill>/SKILL.md` | All your projects |
| Project | `.claude/skills/<skill>/SKILL.md` | Only this project |
| Plugin | `<plugin>/skills/<skill>/SKILL.md` | Where the plugin is enabled |

On name conflicts: enterprise > personal > project. Plugin skills use namespace (`plugin:skill`).

### Automatic discovery in subdirectories

In monorepo setups, Claude Code discovers skills from nested `.claude/skills/` directories automatically. If you edit files in `packages/frontend/`, skills from `packages/frontend/.claude/skills/` are also loaded.

### Skills from extra directories

Skills in `.claude/skills/` from directories added via `--add-dir` are loaded automatically with live change detection — you can edit them during a session without restarting.

### Size recommendation

Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files in the skill's directory and reference them from SKILL.md.

## Recommended external skills

Install to `~/.claude/skills/` to share across projects:

| Skill | Source | Description |
| --- | --- | --- |
| **anthropics/skills** | Anthropic (official) | Frontend-design (blocking req), PDF, PPTX, XLSX |
| **superpowers** | obra | Planning, TDD, code review |
| **trailofbits/skills** | Trail of Bits | Security research, vulnerability detection |
| **qa-test** | Community | Destructive browser testing (Jinx persona) |
| **dotnet/skills** | Microsoft (official) | ASP.NET Core, EF Core, Blazor patterns |
| **vercel-labs/skills** | Vercel (official) | React performance (45 rules), web design |
| **playwright-skill** | Community (2k+ stars) | Playwright POM, patterns, CI/CD |

### Installation

These are auto-installed by the sync prompt (`scripts/sync-prompt.md`). To install manually:

```bash
declare -A SKILL_REPOS=(
  [anthropics-skills]="anthropics/skills"
  [superpowers]="obra/superpowers"
  [trailofbits-skills]="trailofbits/skills"
  [qa-test]="adampaulwalker/qa-test"
  [dotnet-skills]="dotnet/skills"
  [vercel-skills]="vercel-labs/skills"
  [playwright-skill]="lackeyjb/playwright-skill"
)

for skill in "${!SKILL_REPOS[@]}"; do
  if [ ! -d "$HOME/.claude/skills/$skill" ]; then
    echo "Installing skill: $skill"
    git clone "https://github.com/${SKILL_REPOS[$skill]}.git" "$HOME/.claude/skills/$skill"
  fi
done
```

## Known limitations

- YAML multiline indicators (`>-`, `|`, `|-`) are not parsed correctly in the skills indexer — use single-line strings for `description`
- Context budget: skill descriptions capped at 250 characters in the tool list (~1% of context window, fallback: 8,000 characters)
- Override with `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable if needed
- `/clear` resets cached skills

## Recommended plugins

LSP plugins provide code navigation (~50ms instead of ~45s text search):

```bash
# .NET projects
dotnet tool install --global csharp-ls 2>/dev/null || true

# TypeScript/JavaScript
npm i -g typescript-language-server typescript 2>/dev/null || true

# GitHub integration
# /plugin install github@claude-plugins-official
```
