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
1. Spec written (markdown)           → what the developer wants
2. /clarify                          → fills gaps in the markdown spec via structured questions
                                       (auto-pick recommended via settings.json hook; all tracks)
3. /allium:elicit                    → sharpens clarified spec into .allium (refuses vague requirements)
4. Implementation                    → code written
5. Destructive browser tests         → 8+ scenarios, 6 attack categories
6. /tla (runs /allium:distill first) → drift detection + formal verification
```

`/clarify` runs BEFORE `/allium:elicit` so the `.allium` file is built from the clarified spec, not the original underspecified one. Running them the other way around causes the `.allium` to drift from `spec.md` the moment `/clarify` amends it.

## When writing specs (AUTOMATIC for behavior-changing specs)

When the spec is on the **full** or **light** pipeline track (see `specs.md` → Spec triage), run `/clarify` IMMEDIATELY after the spec is written, THEN `/allium:elicit`. The PostToolUse `allium-hook.sh` enforces the `.allium` step for speckit paths. Do NOT proceed to implementation without the `.allium` file.

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

If the Allium CLI is installed (`allium` command available), `.allium` files are validated automatically after every write or edit. Install via:
- Homebrew: `brew tap juxt/allium && brew install allium`
- Cargo: `cargo install allium-cli`
