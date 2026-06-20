# CLAUDE.md

## Critical rules (READ FIRST)

Rules tagged **(BLOCKING)** are enforced — by hooks (some are hard PreToolUse denies, some are advisory reminders or interviews you MUST act on) and by the Definition of Done. They are requirements, not suggestions. The rest are strong defaults. (Markers are scarce on purpose: when everything is "ALWAYS", nothing is.)

- Read the code first — base conclusions on evidence, never assumptions. Read relevant files BEFORE answering about the codebase; never guess.
- Use the Edit tool for surgical changes — never copy whole files.
- Verify with `npm test` (vitest), `cd src-tauri && cargo test` (Rust), and the Playwright smoke suite before claiming anything is "done".
- Follow existing patterns — look at similar components first.
- **(BLOCKING)** Uphold Principle I (Privacy by Architecture) from `.specify/memory/constitution.md`: no cloud LLM calls, no telemetry of user content, no outbound traffic beyond the updater + initial Ollama model pull. A feature that would add a new outbound network call is REJECTED — do not implement it.
- **(BLOCKING)** Non-trivial feature/refactor/fix → run the full pipeline as **one task** (`specify → clarify → elicit → plan → tasks → analyze → implement → tests → tla`); no permission stops between phases. `clarify` runs on all tracks (auto-pick); `elicit` on full/light only. Trivial-fix bypass needs an explicit one-sentence classification. See `.claude/rules/feature-pipeline.md`.
- **(BLOCKING)** Before feature work, consult the spec register `specs/INDEX.md`; work the next unchecked spec end-to-end (pipeline → commit → push → tick), then stop with the status summary. See `.claude/rules/spec-register.md`.
- **(BLOCKING)** Hardening — a spec that crosses a risk threshold (auth / payments / PII / upload / new external surface, full-track state machine, new entity or ≥6 files, or tagged `[hardened]`) runs the **hardened tier**: the full pipeline **plus** threat-model pass, expanded destructive + stress, a hard mutation-kill gate, and an adversarial review. Every 5 completed specs, work an **integration-hardening checkpoint** (register row: full-system regression + security sweep). Full-track and hardened specs **start in a fresh session** — when the SessionStart banner says so, run `/clear` first (a hook cannot clear context for you). See `.claude/rules/spec-hardening.md`.
- **(BLOCKING)** Keep the scenario map `specs/SCENARIOS.md` current — a diagram-led, surveyable exploded view (Mermaid use-case diagram + per-feature user-flow flowchart + SC-id ledger). A gap or drift → **start a scenario interview**, never invent the missing cases silently. See `.claude/rules/scenarios.md`.
- **(BLOCKING)** Invoke the `frontend-design` skill BEFORE writing any UI code (HTML, CSS, React components, Tailwind classes, layout). Reference `design-system/MASTER.md` for color, typography, and motion rules.
- **(BLOCKING)** Run user-facing Swedish copy through the `humanizer` skill before shipping (drop zone labels, error messages, settings copy, README). The text must read like a Swedish person wrote it.
- **(BLOCKING)** Testing — every behaviour-changing feature gets **unit + integration + E2E** (integration is where AI code most often breaks), **PBT** for wide-input logic, **visual-regression** baselines for UI, and a functional test for **every** implemented function. The destructive suite is **sized per interactive function from its input domain** (toggle ~3 → multi-step/auth ~20-30+), NOT a flat quota. The **mutation kill rate** (Stryker, nightly/on-demand, ~80% on critical modules) is the gate — test count is not. See `.claude/docs/testing.md` + `.claude/rules/scenarios.md`.

## Execution mode

### Autonomous mode (NON-INTERACTIVE)

- Act immediately without waiting for confirmation.
- Missing information is not a blocker — make reasonable assumptions and continue.
- Errors should be handled and fixed independently.
- Questions are allowed ONLY for architecture decisions or requirement interpretations that cannot reasonably be assumed.
- **Max 3 attempts per problem** — if the same approach fails 3 times, run `/clear` and try a completely different strategy with a better prompt.

### Anti-stall rule

If no clear task is found — pick the most likely task and act. Stagnation is treated as failure.

### Hook recovery rule

When a hook stops continuation or provides feedback: acknowledge the feedback, handle it (fix the issue OR explain why it's not applicable), and **continue working autonomously**. Never stop and wait silently after hook feedback — that is treated as stalling.

### Interview pattern

For larger features: interview the developer with `AskUserQuestion` before implementation. Ask about technical implementation, edge cases, and tradeoffs. Then write a spec before coding begins.

## Priority order

1. **Privacy** — never compromise (Principle I of the constitution)
2. **Security** — input validation, sandboxing, sidecar process isolation
3. **Correctness** — the code must do the right thing
4. **Simplicity** — minimum necessary complexity
5. **Native feel** — macOS conventions, SF Pro, system appearance
6. **Performance** — optimize only when needed (model inference latency dominates anyway)

# PROJECT-SPECIFIC

## Project description

**JuraDrop** is a macOS desktop app that lets Swedish law students translate, summarize, anonymize, and rewrite confidential legal documents using a local Ollama instance — **without document content ever leaving the user's Mac**.
Core flow: **Drop document onto a themed zone → Ollama processes locally → sidecar result file appears next to original and opens automatically.**

**GitHub**: https://github.com/johanolofsson72/juradrop

### Why this exists

- Pasting confidential case material into ChatGPT, Claude.ai, or any cloud LLM breaches client confidentiality and may violate Swedish data protection law.
- Existing "use AI for studies" advice tells students to upload privileged communications to OpenAI. That advice is wrong.
- Cloud LLMs cost money, require accounts, and rate-limit. Local Ollama is free and unmetered.
- Law students need fast utility (translation, summary, bullets, anonymization, plain-language rewrites) without becoming Terminal users.
- Build for real-world use by 19-year-olds with no CLI experience.

### Design principles (non-negotiable)

1. **Privacy by architecture** — no user content ever leaves the Mac. No cloud LLM, no telemetry, no analytics that capture document text. The only outbound traffic is the updater and the initial Ollama model download.
2. **Zero-CLI install** — single signed + notarized DMG. No Terminal, ever, in the install or usage path.
3. **Local-only inference** — Ollama bundled as a Tauri sidecar; localhost:11434 only; no remote-host override.
4. **Single-user desktop app** — no backend, no accounts, no multi-tenancy, no daemon. Window IS the app.
5. **Swedish UI, English code** — user-facing copy in Swedish; code, comments, commits in English.
6. **Native macOS feel** — SF Pro, auto dark/light, native file picker, standard window chrome, subtle motion.
7. **Honest failure states** — Swedish error messages, no stack traces leaked to the UI.

## Language

- Communicate in **English** in conversations, commit messages, and documentation.
- Code, variable names, file names, and technical terms in **English**.
- Comments in code in **English**.
- User-facing UI strings in **Swedish (sv-SE)** — see Principle V of the constitution.

## Tech stack

- **Tauri 2.x** (Rust core + WKWebView) — desktop application framework
- **React 18+ with TypeScript** — frontend
- **Tailwind CSS + shadcn/ui** — styling and component library
- **TanStack Query** — sidecar communication
- **Zustand** — local UI state
- **Ollama** (bundled sidecar) — LLM runtime, default model `gemma3:4b` or `llama3.2:3b`
- **Hosting**: N/A — GitHub Releases hosts signed DMG + updater manifest

### Integrations

- **Ollama HTTP API** at `127.0.0.1:11434` — the only LLM integration
- **GitHub Releases** — distribution channel + updater manifest source
- **Apple notarytool** — release notarization via CI

Rust document-parser crates (`docx-rs`, `pdf-extract`, `rtf-parser`, …) and the full `.docx`/`.pdf`/`.rtf`/`.pages`/`.odt` support matrix live in `.claude/docs/deployment.md` and in `src-tauri/Cargo.toml`.

## CI/CD and deployment

GitHub Actions on `macos-latest` runners using `tauri-action`. On tag push (`v*.*.*`): build → sign with Developer ID Application cert → notarize via Apple's `notarytool` → upload signed DMG + Tauri updater manifest to GitHub Releases. See `.claude/docs/deployment.md` for required GitHub Secrets, certificate setup, and the full pipeline shape.

## Workflow

### Complexity assessment

- **Trivial** (one file, obvious fix) → execute immediately
- **Medium** (2-5 files, clear scope) → brief planning, then execute
- **Complex** (architecture impact, unclear requirements) → full exploration and plan first

### Plan → Implement → Verify

1. **Explore** — read existing code, understand patterns and dependencies.
2. **Plan** — for medium/complex: use Plan Mode (Shift+Tab) to write a plan before implementation.
3. **Implement** — switch to Normal Mode, write code according to the plan. Follow existing patterns.
4. **Verify** — run all tests, typecheck, confirm everything works.
5. **Commit** — commit in English: `<type>: <description>` (feat/fix/refactor/test/docs/style/chore). Details in `.claude/docs/git.md`.

## Verification and grounding

> Giving Claude ways to verify its own work is the single most important measure for quality. — Anthropic Best Practices

- **IMPORTANT:** ALWAYS read relevant files BEFORE answering about the codebase. NEVER guess.
- Run tests after every implementation.
- Run individual tests over the full suite for faster feedback.

### Definition of "implemented"

NEVER say something is "implemented" or "done" until:

1. This spec's scenarios are in `specs/SCENARIOS.md` AND marked `✓ validated` — each one observed *actually working at runtime* (real behaviour, not a stub), with all four states proven: success, a specific visible **error** message (never silent), empty, loading. Validate prerequisite scenarios first; a broken prerequisite is a hard stop. See `.claude/rules/scenarios.md`.
2. **Vitest unit + integration tests** pass (`npm test`) — both layers, not just one. Integration is where AI code most often fails (units pass, the seams don't). **PBT** added for wide-input logic (parsers, anonymizers, chunkers).
3. **Rust unit tests** pass (`cd src-tauri && cargo test`).
4. For UI features: **functional coverage** for EVERY implemented function (1 test each) in vitest, PLUS a **destructive suite per interactive function sized to its input domain** (toggle ~3 → multi-step/drop-zone ~20-30+, not a flat quota), PLUS **visual-regression** baselines for the key states, PLUS at least one Playwright smoke test that drives the actual built app.
5. **Mutation kill rate** on the changed critical module(s) meets target (Stryker / `cargo mutants`, ~80%, nightly/on-demand — NOT per-push CI). This is the gate that proves the tests bite; a green suite that kills no mutants is not done.
6. For state-machine features: **TLA+ formal verification** has been run (`/tla`) — race conditions, state-machine gaps, missing invariants (full/light tracks; auto-triggered after tests).
7. **Visually verified** in `npm run tauri dev` — drag a real file onto the zone and confirm output. The code is assessed as **fully functional**.

If tests cannot be run (missing infrastructure), clearly inform about this.

## Context management

- During compaction: ALWAYS preserve modified files, error messages verbatim, debugging steps, and test commands.
- Use subagents for exploration and research — keep the main context clean.
- Use `/clear` between unrelated tasks.
- Use `/compact <focus>` for controlled compaction.
- Break down large tasks into discrete subtasks.
- After 2 failed fixes of the same problem: `/clear` and write a better prompt from scratch.

## Commands

```bash
npm install                                      # Install JS dependencies (one-time)
npm run tauri dev                                # Run app in development mode
npm run tauri build                              # Build signed .app and .dmg (production)
npm test                                         # Vitest unit tests (React)
npm test -- --run path/to/test.test.tsx          # Single vitest file
cd src-tauri && cargo test                       # Rust unit tests
cd src-tauri && cargo test test_name             # Single Rust test
npm run test:e2e                                 # Playwright smoke tests against built app
npm run lint && npm run typecheck                # ESLint + tsc --noEmit
cd src-tauri && cargo clippy && cargo fmt --check  # Rust lint + format check
```

## Principles

- **YAGNI** — only build what is needed now. Three similar lines > premature abstraction.
- **Fail fast** — clear error messages with context. Never silent fallbacks.
- **DX** — code should be readable without comments. Good naming is usually enough.
- **Privacy first** — every line of code must respect Principle I of the constitution.

## Reference files (loaded on demand)

Read these files WHEN you need them — do not load everything upfront:

- **New project start** or architecture questions → `.claude/docs/project-template.md`
- **Code style, naming, forbidden patterns** → `.claude/docs/conventions.md`
- **Security questions** (input validation, sandbox, sidecar isolation) → `.claude/docs/security.md`
- **Git commit/branch/PR** → `.claude/docs/git.md`
- **Hooks, subagents, plugins, sessions** → `.claude/docs/workflows.md`
- **Creating new agents** → `.claude/docs/agents-templates.md`
- **Skills, SKILL.md format, Agent Skills standard** → `.claude/docs/skills.md`
- **Tests (vitest, Playwright)** → `.claude/docs/testing.md`
- **Spec testing checklist (functional + destructive)** → `.claude/docs/spec-testing-checklist.md`
- **Scenario map (living use-case map, validation gate)** → `.claude/rules/scenarios.md` + `specs/SCENARIOS.md`
- **Design references (decompile a brand/vibe into design-system primitives)** → `.claude/rules/design-references.md` + `.claude/docs/design-reference-library.md`
- **Feature pipeline (end-to-end execution)** → `.claude/rules/feature-pipeline.md`
- **Constitution (principles, hard constraints)** → `.specify/memory/constitution.md`
- **Design system (colors, typography, motion)** → `design-system/MASTER.md`
- **Deploy, signing, notarization, GitHub Actions** → `.claude/docs/deployment.md`

## File organization

- **`src/`** — React frontend (TypeScript + Tailwind + shadcn/ui)
- **`src-tauri/`** — Rust core (Tauri commands, Ollama sidecar mgmt, doc parsing)
- **`src-tauri/binaries/`** — bundled Ollama binary (sidecar)
- **`scripts/`** — Hook scripts and dev tooling
- **`.claude/skills/`** — Project skills with SKILL.md (code-review, explore-codebase, deploy-checklist, tla, allium) + speckit skills.
- **`.claude/agents/`** — Subagents.
- **`.claude/rules/`** — Rules auto-loaded every session. Path-scoped via YAML frontmatter.
- **`.claude/docs/`** — Reference material loaded on demand.
- **`design-system/`** — `MASTER.md` plus per-page design notes.
- **`CLAUDE.local.md`** — Personal project settings, not committed (auto-gitignored).

## Iterative improvement

- If the same mistake repeats: suggest a new rule for CLAUDE.md or a hook that prevents it.
- Every code review comment is a signal that the agent lacked context — update CLAUDE.md.
- Edit existing files over creating new ones.
- Keep this file focused — if an instruction can be removed without Claude making errors, remove it.

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:

- Active spec: `specs/037-native-window-smoke/spec.md`
- Allium spec: `specs/037-native-window-smoke/spec.allium`
- Implementation plan: `specs/037-native-window-smoke/plan.md`
- Research notes: `specs/037-native-window-smoke/research.md`
- Data model: `specs/037-native-window-smoke/data-model.md`
- Contracts: `specs/037-native-window-smoke/contracts/harness.md`
- Quickstart: `specs/037-native-window-smoke/quickstart.md`

Previous specs (completed): `specs/036-study-method-zones/`, `specs/038-chunked-summarization/`, `specs/039-anonymisera-hardening/`, `specs/040-kontakter-per-person/`, `specs/041-custom-instructions/`.

Previous specs (completed): `specs/001-tauri-bootstrap/`, `specs/002-ollama-sidecar-poc/`, `specs/003-first-zone-sammanfatta/`, `specs/004-all-six-zones/`, `specs/005-additional-input-formats/`, `specs/006-signing-and-ci/`, `specs/007-auto-updater/`, `specs/008-first-run-wizard/`, `specs/009-long-tail-formats/`, `specs/010-settings-panel/`, `specs/011-error-recovery/`, `specs/012-polish-and-public-beta/`
<!-- SPECKIT END -->

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
