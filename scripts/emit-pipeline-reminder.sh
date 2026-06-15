#!/bin/bash
# Emits the "MANDATORY PIPELINE" orientation reminder as UserPromptSubmit
# additionalContext JSON. Invoked when the user types a clean invocation of
# /specify, /clarify, /plan, /tasks, or /implement (matched by
# scripts/pipeline-trigger-match.sh pipeline).

read -r -d '' MSG <<'EOM'
MANDATORY PIPELINE — execute each step automatically, never ask: (1) Write spec with destructive browser tests (min 8 scenarios, 6 attack categories). Read .claude/docs/spec-testing-checklist.md FIRST. (2) IMMEDIATELY after spec is written: run /speckit-clarify on EVERY track. The auto-pick hook accepts the (Recommended) answer for every clarification silently; only the rare gap with no defensible default falls back to AskUserQuestion. Skipping /speckit-clarify is the canonical pipeline failure mode and is forbidden. (3) After /speckit-clarify, on full/light tracks ONLY: run /allium:elicit to produce a .allium file. Skip on spec-only track (refactor, doc, config, cosmetic, i18n, logging, simple fix with no new entities). Do NOT ask the user — just run it. Asking is a bug. (4) /speckit-plan then /speckit-tasks — derive functional inventory and implementation tasks. (5) /speckit-analyze — MANDATORY immediately after /speckit-tasks and immediately before /implement. Read-only consistency check across spec/plan/tasks; the analyze hook auto-applies all suggested remediations and auto-chains to /speckit-implement without prompting. Do NOT skip analyze. Do NOT run /speckit-implement before /speckit-analyze. (6) /speckit-implement — execute tasks. (7) AFTER implementation + browser tests: run /tla (auto-runs /allium:distill for drift detection). Again, do NOT ask — just run it.
EOM

jq -n --arg msg "$MSG" '{additionalContext: $msg}'
