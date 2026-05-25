#!/usr/bin/env bash
# update-template.sh — Analyzes latest Claude Code best practices online
# and updates the template repo structure (.claude/, CLAUDE.md, etc.)
#
# Usage:
#   ./scripts/update-template.sh              # Full update
#   ./scripts/update-template.sh --dry-run    # Report only, no changes
#   ./scripts/update-template.sh --focus hooks # Focus on a specific area
#
# Requires: claude CLI (Claude Code) installed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=false
FOCUS=""
DATE=$(date +%Y-%m-%d)

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --focus)   FOCUS="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--focus <area>]"
      echo ""
      echo "Areas: hooks, skills, agents, rules, docs, settings, claude-md"
      echo ""
      echo "Examples:"
      echo "  $0                    # Full update"
      echo "  $0 --dry-run          # Report only"
      echo "  $0 --focus skills     # Skills-related only"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# Validate that claude CLI exists
if ! command -v claude &>/dev/null; then
  echo "Error: 'claude' CLI not found. Install Claude Code first."
  echo "  curl -fsSL https://claude.ai/install.sh | bash"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Claude Code Template Updater                       ║"
echo "║  Date: $DATE                                   ║"
echo "║  Mode: $([ "$DRY_RUN" = true ] && echo 'DRY RUN (no changes)       ' || echo 'LIVE (updating files)       ')║"
[ -n "$FOCUS" ] && \
echo "║  Focus: $(printf '%-44s' "$FOCUS")║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Build focus filter
FOCUS_INSTRUCTION=""
if [ -n "$FOCUS" ]; then
  FOCUS_INSTRUCTION="Focus ONLY on the area: $FOCUS. Ignore other areas."
fi

# Build dry-run instruction
MODE_INSTRUCTION=""
if [ "$DRY_RUN" = true ]; then
  MODE_INSTRUCTION="IMPORTANT: This is a DRY RUN. Do NOT change any files. ONLY write a report with recommendations."
else
  MODE_INSTRUCTION="Apply all recommended changes directly to the files. Create a git commit afterwards with the message 'chore: Update template repo with latest Claude Code best practices ($DATE)'."
fi

# Main prompt sent to Claude
PROMPT=$(cat <<'PROMPT_EOF'
You are an expert on Claude Code configuration. Your task is to analyze the latest news, guidelines, and best practices for Claude Code and then update this template repo.

## Step 1: Research (MANDATORY)

Search online for ALL of the following. Use the WebSearch tool for each search:

1. **Claude Code changelog & release notes** — Search: "Claude Code changelog 2026", "Claude Code release notes latest"
2. **CLAUDE.md best practices** — Search: "CLAUDE.md best practices 2026", "claude code configuration guide"
3. **Agent Skills standard** — Search: "agentskills.io", "claude code skills SKILL.md"
4. **Claude Code hooks** — Search: "claude code hooks PostToolUse PreToolUse 2026"
5. **Claude Code new features** — Search: "claude code new features 2026", "anthropic claude code update"
6. **Context engineering** — Search: "context engineering claude code", "claude code context management best practices"
7. **Claude Code settings.json schema** — Search: "claude code settings.json schema permissions"
8. **Community best practices** — Search: "claude code CLAUDE.md examples github", "claude code configuration template"

Collect ALL relevant information before proceeding.

## Step 2: Analyze current structure

Read the following files in this repo:
- CLAUDE.md
- .claude/settings.json
- .claude/docs/skills.md
- .claude/docs/workflows.md
- .claude/docs/conventions.md
- .claude/rules/*.md
- .claude/agents/*.md
- .claude/skills/*/SKILL.md

## Step 3: Identify gaps

Compare what you found online (step 1) with the current structure (step 2). Identify:

1. **New features** that should be used but are missing
2. **Deprecated patterns** that should be removed or replaced
3. **Improved patterns** that should be updated
4. **New hooks/settings** that should be added
5. **New skill types** that should be created
6. **Security improvements** that are missing
7. **Performance/context optimizations** that can be made

## Step 4: Report and actions

Write a clear report in the following format:

```
## Update report ($DATE)

### New features found
- [feature]: [description] → [action]

### Deprecated/changed patterns
- [pattern]: [what changed] → [action]

### Recommended updates
1. [file]: [change]
2. [file]: [change]

### No changes needed
- [area]: [reason]
```

$MODE_INSTRUCTION

$FOCUS_INSTRUCTION

## Rules

- Write ALL communication in English
- Keep the size of CLAUDE.md as small as possible
- Code and technical terms in English
- Preserve ALL project-specific customizations (marked with # PROJECT-SPECIFIC)
- NEVER change the fundamental structure without strong reasons
- Priority: Security > Correctness > Simplicity
- If unsure, report instead of changing
- Run the humanizer skill on ALL generated text aimed at humans
PROMPT_EOF
)

# Replace variables in the prompt
PROMPT="${PROMPT//\$MODE_INSTRUCTION/$MODE_INSTRUCTION}"
PROMPT="${PROMPT//\$FOCUS_INSTRUCTION/$FOCUS_INSTRUCTION}"
PROMPT="${PROMPT//\$DATE/$DATE}"

echo "Starting Claude Code analysis..."
echo ""

# Run Claude Code with the prompt
cd "$REPO_ROOT"
claude -p "$PROMPT" --allowedTools "WebSearch,WebFetch,Read,Glob,Grep,Edit,Write,Bash,Skill,Agent" 2>&1 | tee "/tmp/claude-template-update-${DATE}.log"

EXIT_CODE=${PIPESTATUS[0]}

echo ""
echo "════════════════════════════════════════════════════════"
if [ $EXIT_CODE -eq 0 ]; then
  echo "Done! Log saved: /tmp/claude-template-update-${DATE}.log"
  if [ "$DRY_RUN" = false ]; then
    echo ""
    echo "Review the changes:"
    echo "  cd $REPO_ROOT && git diff"
  fi
else
  echo "Error occurred (exit code: $EXIT_CODE)"
  echo "See log: /tmp/claude-template-update-${DATE}.log"
fi
