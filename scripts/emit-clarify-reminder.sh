#!/bin/bash
# Emits the SPECKIT CLARIFY auto-pick reminder as UserPromptSubmit
# additionalContext JSON. Invoked when the user types a clean invocation of
# /speckit.clarify (matched by scripts/pipeline-trigger-match.sh clarify).

read -r -d '' MSG <<'EOM'
SPECKIT CLARIFY — AUTO-PICK MODE. The user has standing instructions to always accept the recommended option for clarify questions. Do NOT use AskUserQuestion during this /speckit.clarify run. For every clarification raised, pick the option labeled "(Recommended)" or — if none is explicitly labeled — pick the option that best matches spec-kit conventions (the most conservative, standard, or spec-conforming interpretation). Proceed silently through all clarifications and apply each chosen answer to the spec. FALLBACK: if a specific clarification has no defensible recommended answer (all options are genuinely equivalent OR all options conflict with the spec), that ONE question may use AskUserQuestion — but note it in the audit list below with reason "no recommended answer". This fallback should be rare. At the very end of the /speckit.clarify run, emit a final block in this exact shape on its own paragraph:

**Auto-picked clarifications:**
- Q1 — <one-line topic>: <chosen option> — <one-line reason>
- Q2 — <one-line topic>: <chosen option> — <one-line reason>
- ...

If any clarification was deferred to the user via the fallback, mark it with reason "no recommended answer — asked user" and include the user's answer.
EOM

jq -n --arg msg "$MSG" '{additionalContext: $msg}'
