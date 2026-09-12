#!/bin/bash
# register-similarity.sh — "are we about to build something we already have?"
#
# WHY THIS EXISTS. The question that opened the 2026-09-03 pipeline review was
# not about speed: "jag vill bara vara säker på att vi inte rör ihop projekten
# eller sitter och skriver om redan befintlig funktionallitet." Nothing measured
# that. The carve budget stops the register GROWING; this stops it growing the
# SAME ROW TWICE, across six projects that share a template and a developer.
#
# It is not a language model doing judgement. It is an embedding model doing
# similarity, which is the part a local model is actually reliable at: no
# reasoning, no formatting contract, no hallucination surface. The output is a
# ranked list of pairs for a human to read, never a decision.
#
# Measured on this project's own registers, it recovers the overlaps that were
# found by hand: consultpilot's three rows on one script, agentcrm's S8/S13
# archiver pair, the H7 mutation cluster.
#
# WHY LOCAL AND NOT llm-daol. llm-daol serves an `embed` alias and would do this
# perfectly well -- it is always online, so availability is not the argument.
# The argument is that this particular job needs nothing it offers: the corpus is
# a few hundred short rows, the models are already on the developer's box, and a
# six-project pass costs seconds with no network, no Cloudflare Access service
# token and no LiteLLM virtual key in the loop. Every credential a check needs is
# a way for it to start failing quietly.
#
# llm-daol is the right target for the jobs where that trade goes the other way:
# a bigger model than the box can hold, anything David's lane must run the same
# way, or anything that has to answer identically from two machines. Point this
# at it with OLLAMA_HOST if a project wants that -- the API shape is the same.
#
# Model: paraphrase-multilingual by default -- agentcrm's and consultpilot's
# registers are written in Swedish and rocky's in English, and a cross-project
# duplicate is exactly the case that crosses languages.
#
# Usage:
#   bash scripts/register-similarity.sh                       # every register found
#   bash scripts/register-similarity.sh --dir ~/repos/rocky   # one project
#   bash scripts/register-similarity.sh --text "a new row"    # would this be a duplicate?
#   bash scripts/register-similarity.sh --threshold 0.80 --top 30
#
# Thresholds differ by mode and are calibrated, not guessed -- see the block below.
#
# Exit: 0 nothing above threshold · 1 pairs found (a report, never a refusal) · 2 usage

set -uo pipefail
export LC_ALL=C

HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
MODEL="${REGISTER_SIMILARITY_MODEL:-paraphrase-multilingual}"
# Two thresholds, because the two modes are not on the same scale and pretending
# they are would make one of them useless. Measured on this box against a real
# 240-char register row:
#
#   row  vs row   -- agentcrm S8/S13, one defect written twice        0.870
#   query vs row  -- a 58-char query naming that same defect          0.543
#   query vs row  -- an unrelated query ("Stripe checkout flow")      0.201
#
# A short query under-scores because the row's embedding is dominated by its
# diagnosis text, which the query does not repeat. The separation is still wide
# (0.54 against 0.20), so the answer is a second calibrated number rather than a
# worse model: 0.45 sits between them with room on both sides.
THRESHOLD=""; QUERY_THRESHOLD="0.45"; CORPUS_THRESHOLD="0.82"
TOP="25"; DIRS=(); QUERY=""; OPEN_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIRS+=("${2:-}"); shift 2 ;;
    --text) QUERY="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;   # explicit always wins
    --top) TOP="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --open-only) OPEN_ONLY=1; shift ;;
    -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "register-similarity.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# An explicit --threshold wins; otherwise pick the one calibrated for the mode.
if [ -z "$THRESHOLD" ]; then
  if [ -n "$QUERY" ]; then THRESHOLD="$QUERY_THRESHOLD"; else THRESHOLD="$CORPUS_THRESHOLD"; fi
fi

if ! curl -s -o /dev/null -m 3 "$HOST/api/tags"; then
  echo "register-similarity: no Ollama at $HOST — start it, or set OLLAMA_HOST." >&2
  exit 2
fi
if ! curl -s -m 3 "$HOST/api/tags" | grep -q "\"$MODEL"; then
  echo "register-similarity: model '$MODEL' not pulled. Run: ollama pull $MODEL" >&2
  exit 2
fi

if [ "${#DIRS[@]}" -eq 0 ]; then
  for d in "$HOME"/repos/*/; do
    [ -f "$d/specs/INDEX.md" ] && DIRS+=("${d%/}")
  done
fi
[ "${#DIRS[@]}" -gt 0 ] || { echo "register-similarity: no register found." >&2; exit 2; }

REGISTER_SIMILARITY_HOST="$HOST" \
REGISTER_SIMILARITY_MODEL="$MODEL" \
REGISTER_SIMILARITY_THRESHOLD="$THRESHOLD" \
REGISTER_SIMILARITY_TOP="$TOP" \
REGISTER_SIMILARITY_QUERY="$QUERY" \
REGISTER_SIMILARITY_OPEN_ONLY="$OPEN_ONLY" \
python3 "$(dirname "${BASH_SOURCE[0]}")/register_similarity.py" "${DIRS[@]}"
