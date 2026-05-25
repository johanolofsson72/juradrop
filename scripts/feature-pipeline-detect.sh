#!/bin/bash
# UserPromptSubmit hook: detects feature-build prompts and injects a mandatory
# pipeline reminder per .claude/rules/feature-pipeline.md.
#
# Trigger:    non-trivial feature/refactor/fix verbs (build, implement, add,
#             create, refactor, fix, bygg, lägg till, skapa, ändra, ny, etc.)
# Skip:       prompt already invokes the pipeline (/specify, /plan, /tasks,
#             /implement, /allium, /tla, speckit:*), or is a read-only/Q&A
#             prompt, or carries an explicit-trivial marker.
#
# Output:     additionalContext injection — non-blocking. False positives are
#             harmless (extra reminder). False negatives are the failure mode
#             this hook exists to prevent.

set -u

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

LP=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# 1) Already on the pipeline — let the existing hook handle it
if echo "$LP" | grep -qE '(/specify|/clarify\b|/plan\b|/tasks\b|/implement\b|/allium|/tla\b|speckit[.:_-])'; then
  exit 0
fi

# 2) Read-only / Q&A / status / exploration prompts
if echo "$LP" | grep -qE '(\bexplain\b|\bförklara\b|\breview\b|\bgranska\b|what (does|is|are)|hur fungerar|how does|where (is|are)|var (finns|ligger)|find me|hitta|git (status|log|diff|show|blame)|\bvisa\b|\bshow me\b|list (the |all )?|\blista\b)'; then
  exit 0
fi

# 3) Explicit-trivial markers — bypass the pipeline
if echo "$LP" | grep -qE '(trivial fix|one-?line|typo|just (a )?(typo|format|whitespace)|format only|whitespace only|rename (a |the )?(single |local )?variable|revert (the )?last commit)'; then
  exit 0
fi

# 4) Feature-build trigger words (English + Swedish)
TRIGGER='(\bbuild\b|\bbygg(a|er)?\b|\bimplement(era|ation|s)?\b|\badd (a |the |new )?(feature|module|endpoint|page|api|component|screen|view|flow|integration|model|table|column|field|button|form|route|test|hook|skill|rule|agent)|\blägg till\b|\bskapa\b|\bcreate (a |the |new )?(feature|module|endpoint|page|api|component|screen|view|flow|model|table|column|field|button|form|route|integration)|\bnew (feature|module|endpoint|page|api|component|screen|view|flow|integration|model|table|column|field|button|form|route)\b|\bny[a-z]* (feature|modul|endpoint|sida|api|komponent|skärm|vy|flöde|modell|tabell|kolumn|fält|knapp|formulär|rutt|integration)\b|\brefactor\b|\brefaktor\b|\bändra\b|\brestructure\b|\brestrukturer\b|\bmigrate\b|\bmigrera\b|\bfix(a)?\b|\bbugfix\b|\bdoesn'\''t work\b|\bbroken\b|\bgår sönder\b|\bfungerar inte\b)'

if echo "$LP" | grep -qE "$TRIGGER"; then
  MESSAGE='MANDATORY FEATURE PIPELINE — this prompt looks like non-trivial feature/refactor/fix work. Per .claude/rules/feature-pipeline.md you MUST run the full pipeline end-to-end as ONE task, without asking permission between phases:

0. If specs/INDEX.md exists (spec register), READ IT FIRST. Pick the next unchecked row and work that spec instead of spinning up a new ad-hoc spec. If the prompt is genuinely outside the register, treat it as a register-rewrite proposal per .claude/rules/spec-register.md, not as silent scope expansion.
1. /specify — write the spec (with destructive browser tests if interactive UI). Triage the spec shape per .claude/rules/specs.md.
2. /clarify — MANDATORY on EVERY track immediately after /specify. The settings.json auto-pick hook accepts the "(Recommended)" answer for every clarification question silently and only falls back to AskUserQuestion for the rare question with no defensible recommendation. Skipping /clarify is the canonical pipeline failure mode and is forbidden — running /specify → /plan directly is the bug this step exists to prevent.
3. /allium:elicit — full and light tracks only. Skip for spec-only track (refactor, doc, config, cosmetic, i18n, logging, simple fix with no new entities). Runs AFTER /clarify so the .allium file is built from the clarified spec.
4. /plan and /tasks — derive the functional inventory and implementation tasks from the clarified spec.
4b. /speckit.analyze — MANDATORY immediately after /tasks. Read-only consistency check; auto-applies ALL suggested remediations to spec/plan/tasks without prompting (user standing instruction), then auto-chains to /implement. No stop between tasks → analyze → implement.
5. /implement — execute tasks. Follow existing patterns in the codebase.
6. Browser tests — functional coverage (one test per implemented function, no exceptions) PLUS destructive tests (8+ scenarios across the 6 attack categories).
7. /tla — runs /allium:distill, drift detection, invariants. Full track only; light track only if state machine is non-trivial.
8. Commit + push to main directly (solo/direct-push workflow). Tick the register row. Stop with the status summary defined in .claude/rules/spec-register.md — that stop IS the question; do NOT add "ready for the next spec?" after it.

Do NOT skip to implementation. Do NOT skip /clarify. Do NOT ask "should I run /specify first?" — the answer is yes for any non-trivial work; just run it.

Legitimate stops during the pipeline: (a) genuine ambiguity the spec/triage cannot resolve — use AskUserQuestion; (b) hard blocker outside your control; (c) Allium/TLA+ findings — per validation-followup.md, surface each finding individually for explicit user decision; (d) end of a spec with status summary, when specs/INDEX.md exists; (e) register-rewrite proposal mid-spec, when the register itself turns out to be wrong.

If this request is truly a trivial one-file fix (typo, format, single-line bug, single-variable rename), state that classification explicitly in your first sentence and skip the pipeline. Otherwise: start with /specify now (or the next register row).'

  jq -n --arg msg "$MESSAGE" '{additionalContext: $msg}'
fi

exit 0
