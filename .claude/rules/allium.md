---
paths:
  - "**/*.allium"
  - "**/allium/**"
  - "**/spec*.md"
  - "**/tasks*.md"
  - "**/plan*.md"
  - "**/feature*.md"
---

# Allium specification rules

Allium is the preferred specification language for this project. It sits between natural language and TLA+ — more formal than markdown specs, more readable than formal methods.

## The pipeline

```
0. Scenario map (SCENARIOS.md)       → every use case, exploded (gap/drift → interview)
1. Spec written (markdown)           → what the developer wants
1b. Spec interview (interview.md)    → 15–25 questions, EVERY spec (anti-drift gate)
                                       base AUTO-answered w/ recommended; human overflow if
                                       flagged large/advanced (.claude/rules/spec-interview.md)
2. /speckit-clarify                          → fills gaps in the markdown spec via structured questions
                                       (auto-pick recommended via settings.json hook; all tracks)
3. /allium:elicit                    → sharpens clarified spec into .allium (refuses vague requirements)
4. Implementation                    → code written
4b. /speckit-converge + /simplify    → unbuilt work back to tasks.md; then a quality-only pass
5. Tests                             → unit + integration + PBT (wide input); E2E functional +
                                       risk-tiered destructive (sized per UI function) + visual regression;
                                       mutation kill rate is the gate, not the count
6. /tla (runs /allium:distill first) → drift detection + formal verification
```

`/speckit-clarify` runs BEFORE `/allium:elicit` so the `.allium` file is built from the clarified spec, not the original underspecified one. Running them the other way around causes the `.allium` to drift from `spec.md` the moment `/speckit-clarify` amends it.

## When writing specs (AUTOMATIC for behavior-changing specs)

When the spec is on the **full** or **light** pipeline track (see `specs.md` → Spec triage), run `/speckit-clarify` IMMEDIATELY after the spec is written, THEN `/allium:elicit`. The PostToolUse `allium-hook.sh` enforces the `.allium` step for speckit paths. Do NOT proceed to implementation without the `.allium` file.

The `.allium` file MUST be saved in the same directory as the spec file.

**Skip `/allium:elicit` for the spec-only track:** pure refactors, doc changes, dependency bumps, cosmetic UI changes, i18n, and fix/hardening specs that introduce no new entities or state transitions. Forcing elicitation on these produces fabricated `.allium` files that later surface as false drift during `/tla`. If the spec is on the full/light track, do not ask whether to run `/allium:elicit` — just run it.

When unsure which track a spec belongs to, classify first (one `AskUserQuestion`), then act. Do not default to "full pipeline" — over-application is the failure mode this rule exists to prevent.

This step:
- Forces precision on entities, rules, and invariants
- Refuses vague or ambiguous requirements
- Creates the baseline that `/tla` will compare against after implementation

## When reviewing implementations

After browser tests are written, `/tla` automatically runs `/allium:distill` to extract what was actually built and compares it against the pre-implementation `.allium`. Differences are **spec drift**.

## Allium commands

| Command | When | Purpose |
|---|---|---|
| `/allium:elicit` | Before implementation | Build formal spec through conversation |
| `/allium:distill` | After implementation | Extract spec from code (used by `/tla`) |
| `/allium` | Any time | Examine project, offer elicit or distill |

## Validation

`scripts/allium-check-hook.sh` (PostToolUse) runs `allium check` on every `.allium` file that is
written or edited:

- **Any diagnostic with `severity: error` blocks.** The errors come back as `line:col message`, so
  the file gets fixed in the turn that wrote it.
- **Warnings and info never block.** The CLI exits 1 on a warning, and the deferred location-hint
  lint warns on nearly every spec, so the hook reads severities, never the exit code.
- **A report it cannot read blocks** (crash, non-JSON, a 30 s timeout). An unreadable report is not
  a clean file.
- **No CLI installed → pass, with one notice per session** saying nothing was validated.

`bash scripts/allium-census.sh` lists every `specs/*/spec.allium` that still has errors (exit 0
clean, 1 debt, 2 cannot tell). `project-maintenance.sh` prints its summary as a note and never fails
on it.

Until 2026-09-26 this section said validation was automatic, and nothing ran it. Rocky had 136 of
592 baselines with errors, 107 of them declaring the current `-- allium: 3`. The cause was not
grammar drift: the skill's own reference example did not parse, and elicits copied it.

Install the CLI via:
- Homebrew: `brew tap juxt/allium && brew install allium`
- Cargo: `cargo install allium-cli`
