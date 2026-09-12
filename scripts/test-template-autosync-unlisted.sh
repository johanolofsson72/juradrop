#!/bin/bash
# Tests the [unlisted] predicate in scripts/template-autosync.sh — unlisted_core_shaped (row H7bk).
#
# WHY THIS EXISTS
# ---------------
# The predicate shipped with spec 007ca calibrated (13 unmanaged / 1 flagged / 0 false positives on
# one tree, 18 / 4 / 0 replayed against the event it was built for) and with NO harness at all. It
# then fed scripts/core-owed-tick-guard-hook.sh, which denies a register tick on any finding — so a
# false positive is not a noisy line, it is a project that cannot tick a row.
#
# That is what happened. Two CORE scripts name consultpilots run-gates.sh in four WHOLE-LINE
# COMMENTS, and .claude/settings.json named its Stop hook. Neither is a dependency: a comment
# survives the sync as a comment, and settings.json is merged by sync-core-hooks.py rather than
# overwritten, with project-specific hooks preserved verbatim. The tick guard was therefore
# permanently red on that project, every row was ticked through ALLOW_TICK_WITH_CORE_OWED, and an
# override taken every time announces nothing.
#
# WHAT IS UNDER TEST, AND WHY IT IS FIVE OWNERSHIP CASES AND NOT ONE
# ------------------------------------------------------------------
# The predicate is "unmanaged, and named by a file whose bytes the next sync replaces". Getting it
# right means DISCRIMINATING, in one run, between five ways a script can be named. A harness that
# only proved the two silences would pass just as well against a predicate that reports nothing,
# which is the failure mode a detector fails into most quietly.
#
#   AC-01  real code dependency in a CORE .sh          -> FLAG
#   AC-02  whole-line comment in a CORE .sh            -> silent   (the H7bk defect)
#   AC-03  instructional prose in a CORE .md rule      -> FLAG     (# is a heading in markdown)
#   AC-04  hook command in .claude/settings.json       -> silent   (merged, not overwritten)
#   AC-05  named by nobody                             -> silent
#   AC-06  code with a trailing `# … scripts/x.sh`     -> FLAG     (the rule is exact, not clever)
#   AC-07  whole-line comment in a CORE .py            -> silent
#   AC-10  code dependency the SAME CORE file declares optional      -> silent
#   AC-11  declared optional by one CORE file, called bare by another -> FLAG, naming only the second
#
# AC-10/AC-11 are the opt-out declaration (rocky F042). The predicate rule -- a CORE file names it,
# so either the template ships it or the sync deletes the reference -- is sound for an UNGUARDED
# call and false for a guarded one, and project-maintenance.sh has three guarded ones. That held
# rocky register tick permanently red for a design this repository documents as correct. The
# declaration is scoped to the PAIR, so AC-11 is the arm that matters: an exemption that leaked to
# every referrer would hide the real dependency next door, which is the failure a blanket exemption
# fails into and the reason AC-11 asserts the referrer LIST and not merely the finding.
#
# AC-08 replays the 007ca calibration corpus so the comment rule cannot silently cost recall, and
# AC-09 is the sabotage arm: with the rule removed, the arm that demands silence must redden. A
# gate nobody has watched fail is a report.
#
# AC-nn, not SC-nnnn, and that is not a style choice. This file is template CORE, so a project
# scenario id written into it is eaten by the next sync — and until then it is a real row of ONE
# projects map spelled inside a file shipped to every other one, where it names nothing. The
# consuming project records the SC coverage in its own registry line instead, which is where
# scripts/test-sync-count-honesty.sh already keeps its six for the same reason (rows H7bd, H7bh).
#
# Run: bash scripts/test-template-autosync-unlisted.sh
# Exit: 0 all arms passed · 1 an arm failed

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP %s — %s\n' "$1" "$2"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3' in: $(printf '%s' "$2" | tr '\n' '|'))" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The referring files must be genuinely CORE. unlisted_core_shaped filters on the same
# $CORE_SCRIPTS / $CORE_RULES the rest of the script reads, so an invented `demo-hook.sh` would be
# invisible to it and every assertion below would pass against a broken predicate.
CORE_SH="scripts/bash-write-detect-hook.sh"
CORE_PY="scripts/sync-core-hooks.py"
CORE_RULE=".claude/rules/scenarios.md"

# ---------------------------------------------------------------------------------------------
# The five-way tree. One project, one run, every ownership case present at once — because the
# property under test is discrimination, and a per-case tree cannot show it.
# ---------------------------------------------------------------------------------------------
build_five_way() {
  R="$TMP/fiveway"; rm -rf "$R"
  mkdir -p "$R/.git" "$R/.claude/rules" "$R/scripts"

  # A manifest must exist: project mode treats "no manifest" as no evidence and returns nothing, so
  # without this the tree is silent for the wrong reason and every silence arm passes vacuously.
  printf 'sha=deadbeef\nsynced=2026-01-01T00:00:00Z\nsource=/dev/null\n# manifest\n' \
    > "$R/.claude/.template-sync"

  cat > "$R/$CORE_SH" <<'EOF'
#!/usr/bin/env bash
# Same idiom as EXCLUDED in scripts/prose-only-helper.sh: a reason is written down, never implied.
  # An indented comment is still a comment, and this one names scripts/indented-prose-helper.sh.
. "$(dirname "$0")/real-dep-helper.sh"
bash scripts/real-dep-helper.sh --check
bash scripts/trailing-comment-helper.sh   # see scripts/trailing-comment-helper.sh for why
# template-autosync: optional-project-script scripts/declared-optional-helper.sh
# template-autosync: optional-project-script scripts/declared-elsewhere-helper.sh
[ -f scripts/declared-optional-helper.sh ] && bash scripts/declared-optional-helper.sh
[ -f scripts/declared-elsewhere-helper.sh ] && bash scripts/declared-elsewhere-helper.sh
EOF

  cat > "$R/$CORE_PY" <<'EOF'
#!/usr/bin/env python3
# Ported from scripts/py-prose-helper.sh; the shell version is gone.
import subprocess, sys
subprocess.run(["bash", "scripts/declared-elsewhere-helper.sh"], check=False)
sys.exit(0)
EOF

  # Markdown: `#` is a heading, and the sentence below is an instruction. Every finding in the
  # calibration corpus has this shape, which is why the comment rule must not touch .md.
  cat > "$R/$CORE_RULE" <<'EOF'
# Scenario map rule

Prove it mechanically: `scripts/rule-named-helper.sh` is that gate. Eyeballing a diff is not a check.
EOF

  cat > "$R/.claude/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/scripts/settings-named-helper.sh\""}]}]}}
EOF

  for f in real-dep-helper prose-only-helper indented-prose-helper py-prose-helper \
           rule-named-helper settings-named-helper trailing-comment-helper nobody-names-me \
           declared-optional-helper declared-elsewhere-helper; do
    : > "$R/scripts/$f.sh"
  done
  printf '%s' "$R"
}

echo "== unlisted_core_shaped — five ownership cases in one run"
R=$(build_five_way)
OUT=$(CLAUDE_PROJECT_DIR="$R" bash "$SCRIPT" --unlisted 2>/dev/null); RC=$?

has   "AC-01 real code dependency in a CORE .sh is flagged"        "$OUT" "scripts/real-dep-helper.sh"
hasnt "AC-02 whole-line comment in a CORE .sh is not a dependency" "$OUT" "scripts/prose-only-helper.sh"
hasnt "AC-02 an INDENTED whole-line comment is a comment too"      "$OUT" "scripts/indented-prose-helper.sh"
has   "AC-03 instructional prose in a CORE .md rule is flagged"    "$OUT" "scripts/rule-named-helper.sh"
hasnt "AC-04 a hook command in settings.json is not a referrer"    "$OUT" "scripts/settings-named-helper.sh"
hasnt "AC-05 a script nobody names is silent"                      "$OUT" "scripts/nobody-names-me.sh"
has   "AC-06 a trailing mid-line # does not excuse the code line"  "$OUT" "scripts/trailing-comment-helper.sh"
hasnt "AC-07 whole-line comment in a CORE .py is not a dependency" "$OUT" "scripts/py-prose-helper.sh"
same  "AC-01 findings exit 0"                                      "$RC"  "0"
has   "AC-01 the referrer is named, not just the finding"          "$OUT" "bash-write-detect-hook.sh"
hasnt "AC-10 a declared-optional dependency is silent"             "$OUT" "scripts/declared-optional-helper.sh"
has   "AC-11 declared by one file, called bare by another: flagged" "$OUT" "scripts/declared-elsewhere-helper.sh"

# The pair-scoping assertion, and the only one that can tell a scoped exemption from a global one.
# Read the finding row for that path and require the declaring file to be ABSENT from its referrer
# list while the undeclared caller is present. Asserting the path alone would pass against a
# predicate whose exemption did nothing at all.
AC11_ROW=$(printf '%s\n' "$OUT" | grep -F 'scripts/declared-elsewhere-helper.sh')
has   "AC-11 the undeclared .py caller is named as referrer"       "$AC11_ROW" "sync-core-hooks.py"
hasnt "AC-11 the declaring .sh is NOT named as referrer"           "$AC11_ROW" "bash-write-detect-hook.sh"

# The empty half of the contract. core-owed-tick-guard-hook.sh branches on the exit code, so "no
# findings" has to be 1 and not 0-with-empty-stdout.
echo
echo "== the empty answer is exit 1, not exit 0"
R2="$TMP/quiet"; rm -rf "$R2"; mkdir -p "$R2/.git" "$R2/.claude/rules" "$R2/scripts"
printf 'sha=deadbeef\nsynced=2026-01-01T00:00:00Z\nsource=/dev/null\n# manifest\n' > "$R2/.claude/.template-sync"
: > "$R2/scripts/nobody-names-me.sh"
OUT2=$(CLAUDE_PROJECT_DIR="$R2" bash "$SCRIPT" --unlisted 2>/dev/null); RC2=$?
same "AC-05 no findings exits 1" "$RC2" "1"
same "AC-05 no findings print nothing" "$OUT2" ""

# ---------------------------------------------------------------------------------------------
# AC-08 — the calibration corpus. 007ca measured the predicate against msroute at 3e1d386, the
# commit of the event it was built for: 4 findings, 0 false positives. The comment rule must not
# move that number.
#
# The corpus needs its era: those four scripts were PROMOTED to CORE_SCRIPTS afterwards — which is
# the fix having worked — so with today's list the tree is correctly silent and proves nothing. The
# arm rebuilds the era by removing that one family from CORE_SCRIPTS in a copy of the sync.
#
# SKIP, never a silent pass. A harness whose only regression arm vanishes with the tree and still
# prints clean is reporting about nothing.
# ---------------------------------------------------------------------------------------------
echo
echo "== AC-08 — 007ca calibration corpus, recall unchanged"
CORPUS_REPO="${UNLISTED_CORPUS_REPO:-$HOME/repos/msroute}"
CORPUS_REF="${UNLISTED_CORPUS_REF:-3e1d386}"
if [ ! -d "$CORPUS_REPO/.git" ]; then
  skip "AC-08 corpus replay" "no repository at $CORPUS_REPO (set UNLISTED_CORPUS_REPO)"
elif ! git -C "$CORPUS_REPO" rev-parse --verify -q "$CORPUS_REF^{commit}" >/dev/null 2>&1; then
  skip "AC-08 corpus replay" "$CORPUS_REPO has no commit $CORPUS_REF"
else
  C="$TMP/corpus"; mkdir -p "$C"
  git -C "$CORPUS_REPO" archive "$CORPUS_REF" | tar -x -C "$C"
  mkdir -p "$C/.git"
  git -C "$CORPUS_REPO" show "$CORPUS_REF:.claude/.template-sync" > "$C/.claude/.template-sync" 2>/dev/null

  # Era-correct membership: the scenario-map family out of CORE_SCRIPTS, nothing else touched.
  ERA="$TMP/era-autosync.sh"
  python3 - "$SCRIPT" "$ERA" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
m = re.search(r'^CORE_SCRIPTS="(.*?)"$', s, re.S | re.M)
names = [n for n in m.group(1).split()
         if 'scenario-map' not in n]
open(dst, 'w', encoding='utf-8').write(s[:m.start(1)] + '\n'.join(names) + s[m.end(1):])
PYEOF
  COUT=$(CLAUDE_PROJECT_DIR="$C" bash "$ERA" --unlisted 2>/dev/null)
  CN=$(printf '%s\n' "$COUT" | grep -c 'scripts/')
  same "AC-08 corpus still yields four findings" "$CN" "4"
  has  "AC-08 scenario-map-layout.sh"      "$COUT" "scripts/scenario-map-layout.sh"
  has  "AC-08 scenario-map-rows.sh"        "$COUT" "scripts/scenario-map-rows.sh"
  has  "AC-08 test-scenario-map-index.py"  "$COUT" "scripts/test-scenario-map-index.py"
  has  "AC-08 test-scenario-map-split.sh"  "$COUT" "scripts/test-scenario-map-split.sh"
  has  "AC-08 the .md referrer survives the comment rule" "$COUT" "scenarios.md"
fi

# ---------------------------------------------------------------------------------------------
# AC-09 — sabotage. Delete the comment rule in a copy and the tree from the five-way arm must
# start reporting prose again. Without this arm every silence above is equally consistent with a
# predicate that reports nothing at all.
# ---------------------------------------------------------------------------------------------
echo
echo "== AC-09 — the comment rule has teeth"
SAB="$TMP/sabotaged-autosync.sh"
python3 - "$SCRIPT" "$SAB" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
needle = '            if (f ~ /\\.(sh|py)$/ && body ~ /^[ \\t]*#/) next\n'
if needle not in s:
    sys.stderr.write('SABOTAGE-ANCHOR-MISSING\n')
    sys.exit(3)
open(dst, 'w', encoding='utf-8').write(s.replace(needle, '', 1))
PYEOF
if [ $? -ne 0 ]; then
  bad "AC-09 sabotage anchor not found — the rule was reworded and this arm can no longer aim"
else
  SOUT=$(CLAUDE_PROJECT_DIR="$R" bash "$SAB" --unlisted 2>/dev/null)
  has "AC-09 without the rule, .sh prose is reported again"     "$SOUT" "scripts/prose-only-helper.sh"
  has "AC-09 without the rule, .py prose is reported again"     "$SOUT" "scripts/py-prose-helper.sh"
  has "AC-09 the real dependency is unaffected by the sabotage" "$SOUT" "scripts/real-dep-helper.sh"
fi

# ---------------------------------------------------------------------------------------------
# AC-12 — sabotage the opt-out. Delete the pair lookup in a copy and AC-10 silence must turn back
# into a finding. Without this arm AC-10 passes equally against a declaration that is parsed,
# stored, and never consulted -- which is what a silent exemption looks like from the outside.
# ---------------------------------------------------------------------------------------------
echo
echo "== AC-12 — the opt-out declaration has teeth"
SAB2="$TMP/sabotaged-optout.sh"
python3 - "$SCRIPT" "$SAB2" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
needle = '              if ((f SUBSEP c) in optout) continue\n'
if needle not in s:
    sys.stderr.write('SABOTAGE-ANCHOR-MISSING\n')
    sys.exit(3)
open(dst, 'w', encoding='utf-8').write(s.replace(needle, '', 1))
PYEOF
if [ $? -ne 0 ]; then
  bad "AC-12 sabotage anchor not found — the lookup was reworded and this arm can no longer aim"
else
  SOUT2=$(CLAUDE_PROJECT_DIR="$R" bash "$SAB2" --unlisted 2>/dev/null)
  has "AC-12 without the lookup, the declared script is reported"  "$SOUT2" "scripts/declared-optional-helper.sh"
  SAB2_ROW=$(printf '%s\n' "$SOUT2" | grep -F 'scripts/declared-elsewhere-helper.sh')
  has "AC-12 and the declaring file reappears as a referrer"       "$SAB2_ROW" "bash-write-detect-hook.sh"
fi

# ---------------------------------------------------------------------------------------------
# AC-13 — TEMPLATE mode, the inverse question. The file loop asks "does the list name this file";
# this asks "is there a file behind this name", and until 2026-09-11 nothing did. A name with no
# file makes --is-core answer CORE, so core-machinery-guard-hook.sh refuses every edit to that path
# in every project while the sync has nothing to copy there — a path nobody may author downstream
# and nobody has authored here. run-mutation-gate.sh sat in that state for a week, with two prose
# blocks in this repository saying it is deliberately NOT shipped.
#
# The arm rewrites CORE_SCRIPTS down to two names in a copy, for the reason AC-08 rewrites it: the
# real list is ~110 names and a fixture holding none of them would report ~110 findings, which
# proves nothing about the one under test.
# ---------------------------------------------------------------------------------------------
echo
echo "== AC-13 — a CORE_SCRIPTS name with no file behind it"
TR="$TMP/tmplmode"; rm -rf "$TR"; mkdir -p "$TR/scripts"
( cd "$TR" && git init -q . >/dev/null 2>&1 && git remote add origin \
    "https://github.com/johanolofsson72/Claude.git" >/dev/null 2>&1 )
mkdir -p "$TR/.claude"
: > "$TR/scripts/present-core.sh"

TWO="$TMP/two-name-autosync.sh"
python3 - "$SCRIPT" "$TWO" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()
m = re.search(r'^CORE_SCRIPTS="(.*?)"$', s, re.S | re.M)
if not m:
    sys.stderr.write('CORE_SCRIPTS-ANCHOR-MISSING\n'); sys.exit(3)
open(dst, 'w', encoding='utf-8').write(
    s[:m.start(1)] + 'present-core.sh\nvanished-core.sh' + s[m.end(1):])
PYEOF
if [ $? -ne 0 ]; then
  bad "AC-13 CORE_SCRIPTS anchor not found — the list was reshaped and this arm cannot aim"
else
  TOUT=$(CLAUDE_PROJECT_DIR="$TR" bash "$TWO" --unlisted 2>/dev/null); TRC=$?
  same "AC-13 a missing name is a finding, so exit 0"        "$TRC"  "0"
  has  "AC-13 the missing name is reported"                  "$TOUT" "scripts/vanished-core.sh"
  has  "AC-13 and the report says why it matters"            "$TOUT" "no such file"
  hasnt "AC-13 the name that HAS a file is not reported"     "$TOUT" "scripts/present-core.sh"
fi

echo
printf 'unlisted: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
