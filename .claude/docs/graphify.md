# Graphify — optional codebase knowledge graph

Graphify (`safishamsi/graphify`, MIT) is an external tool that parses a codebase locally with tree-sitter and writes a queryable graph of symbols, files, and call/import edges. Claude Code can then query the graph instead of re-reading source files when answering structural questions ("where is `X` defined", "who calls `Y`", "what connects auth to the database").

This doc is **opt-in per project**. The template repo does not install Graphify by default. Decide per project whether the payoff justifies the extra tool.

## When to install

| Situation | Install? |
| --- | --- |
| Project has < ~30 source files | No — overhead exceeds savings |
| Project has 50+ source files in a supported language | Yes |
| Project is short-lived (prototype, spike, demo) | No |
| Project is long-lived and Claude frequently does cross-file lookups | Yes |
| Project lives in a private repo with no outbound network | Yes — AST mode is fully offline |

If unsure: skip it. The template's existing flow (spec register, `/explore-codebase` skill, `Grep`/`Glob`) is sufficient for most work.

## Supported languages

`.cs .ts .tsx .js .jsx .mjs .py .go .rs .java .c .cpp .h .hpp .rb .kt .scala .php .swift .lua .zig .ps1 .ex .exs .m .mm .jl .vue .svelte .astro .groovy .gradle .dart .sql .sh .bash .json`

Covers the template's stack (.NET, React/TypeScript, Python). WordPress (`.php`) is covered. Razor (`.razor`, `.cshtml`) is not — Razor-heavy projects gain less.

## Install (project-scoped) — cross-platform

The template ships `scripts/graphify-bootstrap.sh` which handles macOS, Linux (Debian/Ubuntu/Fedora/RHEL/Arch/openSUSE), and Windows Git Bash uniformly. Run from the project root:

```bash
bash scripts/graphify-bootstrap.sh
```

The script counts source files first and skips projects with fewer than 30 eligible files (install overhead exceeds savings). Pass `--force` to override or `--eligibility-check` to dry-run the count.

If you need to run the steps manually, the cross-platform equivalents are:

**macOS:**
```bash
brew install pipx && pipx ensurepath
pipx install graphifyy
graphify install --project
graphify update .                # AST-only, no LLM key required
graphify hook install
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt install -y pipx && pipx ensurepath
pipx install graphifyy
graphify install --project
graphify update .
graphify hook install
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install -y pipx && pipx ensurepath
pipx install graphifyy
graphify install --project
graphify update .
graphify hook install
```

**Linux (Arch):**
```bash
sudo pacman -S --noconfirm python-pipx && pipx ensurepath
pipx install graphifyy
graphify install --project
graphify update .
graphify hook install
```

**Windows Git Bash** (recommended over native PowerShell):
```bash
scoop install pipx              # or: winget install pipx
pipx ensurepath
pipx install graphifyy
graphify install --project
graphify update .
graphify hook install
```

**Note on the extraction command:** earlier versions of this doc said `graphify .`, but as of `graphifyy 0.8.x` the bare command requires an LLM API key (Gemini/Claude/OpenAI/etc.) for the semantic clustering pass. Use `graphify update .` instead — same AST extraction, no API key, fully offline. The template's `graphify-bootstrap.sh` uses `update .` for exactly this reason.

`graphify install --project` writes its own skill at `.claude/skills/graphify/SKILL.md` and adds a `PreToolUse` hook entry to the project's `.claude/settings.json` (or `settings.local.json`). Do not hand-write a wrapper skill in the template repo — Graphify ships its own and a parallel skill would conflict.

## Token-savings telemetry

The template ships two scripts that measure Graphify's ROI per project:

- **`scripts/graphify-fire-hook.sh`** — PostToolUse Bash hook. Fires on `graphify (query|path|explain|update)` invocations and appends a TSV row to `.claude/graphify-fire.log`: `timestamp, subcommand, exit, arg_bytes, response_bytes, graph_nodes, graph_edges`. Wire it via the entry in `.claude/settings.json`'s PostToolUse Bash matcher block (see sync-prompt.md Step 5d).
- **`scripts/graphify-stats.sh`** — Reads the fire log and prints per-subcommand fire counts, ok%, average argument and response sizes. Pass `--all` to aggregate across `~/repos/*` and `~/Projects/*`.

Disable telemetry per-developer with `GRAPHIFY_TELEMETRY_DISABLE=1` in the shell profile. The hook becomes a silent no-op. The graphify-fire.log file is gitignored — telemetry never leaves the developer's machine.

## What gets written

| Path | Purpose |
| --- | --- |
| `.claude/skills/graphify/SKILL.md` | The Graphify skill — Claude reads this when asked structural questions |
| `.claude/settings.json` (modified) | PreToolUse hook entry nudging Claude toward graph queries before file-search tool calls |
| `graphify-out/graph.json` | The graph itself (nodes, edges, communities) |
| `graphify-out/wiki/` | Human-readable index files |
| `.git/hooks/post-commit`, `.git/hooks/post-checkout` | Auto-rebuild on commit/checkout |

Add to `.gitignore` (the graph is a derived artifact and rebuilds on commit):

```
graphify-out/
```

Commit `.claude/skills/graphify/` and the settings.json hook entry so the team shares the integration; do not commit `graphify-out/`.

## Daily use

Once installed, Claude calls these via the skill without prompting. They also work directly in a terminal:

```bash
graphify query "what connects the auth service to the database?"
graphify path "UserService" "DatabasePool"     # shortest path between two symbols
graphify explain "RateLimiter"                  # neighborhood of one symbol
graphify update .                               # re-extract changed files only (AST-only)
graphify export callflow-html                   # render a callflow diagram
```

Every one of these commands (except `export`) fires the telemetry hook, so the fire log accumulates an audit trail you can inspect with `bash scripts/graphify-stats.sh`.

## Privacy and cost

- **AST extraction is fully offline** — tree-sitter only, no LLM API key required, no code leaves the machine.
- **The `/graphify` skill** uses the active Claude Code session's model — no extra API key.
- **Headless `graphify extract --backend gemini|claude-cli`** requires the corresponding API key; only use when you explicitly want LLM-driven semantic enrichment.

## Integration with template conventions

- **Spec register (`specs/INDEX.md`)** — unchanged. Graphify is for navigation, not planning. Specs remain the source of truth for what to build.
- **Feature pipeline** — unchanged. `/specify → /clarify → ... → /implement` still runs in full. The graph helps `/implement` find existing call sites faster, nothing else.
- **Project workflow (solo vs team)** — unchanged. The git hooks rebuild the graph for whoever pushes; PR ceremony is unaffected.
- **`/explore-codebase` skill** — complementary, not a replacement. Use Graphify for symbol-level lookups, `/explore-codebase` for architecture-level orientation.

## Uninstall

```bash
graphify hook uninstall
rm -rf .claude/skills/graphify graphify-out
```

Then remove the Graphify entry from `.claude/settings.json` `hooks` block and the `graphify-out/` line from `.gitignore`.

## Source

- Repo: https://github.com/safishamsi/graphify
- Docs: https://graphify.net/
- License: MIT
