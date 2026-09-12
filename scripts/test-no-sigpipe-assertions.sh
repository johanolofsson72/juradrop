#!/usr/bin/env bash
# test-no-sigpipe-assertions.sh — self-test for scripts/validate-no-sigpipe-assertions.sh (H7x, H7ax).
#
# WHY EVERY EXEMPTION GETS A GREEN ARM, NOT A CLAIM. The gate refuses one idiom and excuses four things:
# diagnostic pipes, all-consuming consumers, CORE (template-owned) files, and comments. An excuse nobody
# has driven is an excuse that quietly grows — and a gate that grew too broad is a gate somebody switches
# off. So each exemption is a fixture here, not a sentence in a header.
#
# WHY THE RED ARMS COME IN BOTH DIRECTIONS. The defect has two faces: a positive assertion reads a true
# claim as false (loud), a NEGATED one reads a false claim as PASS (silent). The gate must reject both, so
# both are driven — ARM 1 and ARM 5.
#
# WHY THE SCOPE PREDICATE GETS ITS OWN ARMS (row H7ax). The exemption is the part that CHANGED, and an
# exemption is the one thing a green run can never demonstrate — it is the absence of a complaint. Ported
# verbatim into the template this gate scanned 5 of 22 files and printed `clean`, because there `CORE`
# means "mine" rather than "eaten by the next sync". So ARMS 14-20 drive the predicate in both directions
# and both fallbacks, and ARM 14 is the red case for the inversion itself: the same CORE file that ARM 15
# excuses downstream must be REFUSED in the template.
#
# HERMETIC. Every arm builds a throwaway scripts/ tree in $TMPDIR with its own template-autosync.sh, and
# drives the real gate through SCAN_ROOT/AUTOSYNC. The fixture declares a FICTIONAL template
# (acme/Template), never the real one, so an arm cannot pass because the gate happens to carry the right
# name — the same reason ARM 4b moves a file out of CORE_SCRIPTS instead of trusting the filename.
# Nothing outside $TMPDIR is read or written; `git init` and `git remote add` are local and touch no
# network.
#
# Usage:  bash scripts/test-no-sigpipe-assertions.sh
# Exit:   0 all arms pass · 1 at least one arm failed
#
# Covers: SC-1731 SC-1732 SC-1733 SC-1734 SC-1735 SC-1746 SC-1747 SC-1748 SC-1749 SC-1750 SC-1751
#         SC-1752

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="${GATE:-$REPO_ROOT/scripts/validate-no-sigpipe-assertions.sh}"

PASS=0
FAIL=0
SANDBOX_ROOT="$(mktemp -d -t h7x-selftest.XXXXXX)" || exit 1
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n         %s\n' "$1" "$2"; }

# The fictional template every fixture declares. Fictional on purpose: an arm that named the real repo
# could pass because the gate carries that name hardcoded, which is precisely the drift the gate refuses
# to have about CORE_SCRIPTS and must equally refuse to have about this.
FIXTURE_TEMPLATE_URL="https://example.invalid/acme/Template.git"

# build_tree <dir> [origin-mode] — a sandbox with a template-autosync.sh whose CORE_SCRIPTS names exactly
# one test file and whose TEMPLATE_REPO_URL names the fictional template. The gate reads both from that
# file rather than carrying copies, so the fixture has to supply them; that is also what makes ARM 4 and
# ARM 16 tests of the boundary instead of tests of a hardcoded name.
#
# origin-mode decides which tree the gate should think it is looking at (row H7ax):
#   project  (default) no git at all, but .claude/.template-sync present — the SECOND signal, and the
#                      shape of a real project. Every pre-H7ax arm uses this, so their meaning is
#                      unchanged: downstream, CORE exempt.
#   template           git origin = the declared template  -> CORE is MINE, nothing is exempt.
#   foreign            git origin = some other repo        -> downstream, CORE exempt.
#   realorigin         git origin = the REAL template repo while the fixture declares acme/Template.
#                      Must read downstream: the answer comes from the file, not from a name in the gate.
#   unknown            neither signal. Must resolve toward scanning, never toward silence.
build_tree() {
  local d="$1" mode="${2:-project}"
  mkdir -p "$d/scripts"
  cat > "$d/scripts/template-autosync.sh" <<AS
#!/usr/bin/env bash
TEMPLATE_REPO_URL="$FIXTURE_TEMPLATE_URL"
CORE_SCRIPTS="spec_active.py resolve-active-spec.sh
test-core-owned.sh archive-spec-history.sh"

CORE_RULES="specs.md"
AS
  case "$mode" in
    project)    mkdir -p "$d/.claude"; printf 'deadbeef  scripts/x.sh\n' > "$d/.claude/.template-sync" ;;
    template)   git_origin "$d" "$FIXTURE_TEMPLATE_URL" ;;
    foreign)    git_origin "$d" "https://example.invalid/acme/SomeProject.git" ;;
    realorigin) git_origin "$d" "https://github.com/johanolofsson72/Claude.git" ;;
    unknown)    : ;;
    *) printf 'build_tree: unknown origin-mode %s\n' "$mode" >&2; exit 2 ;;
  esac
}

# A real local repo with a real remote URL. `git remote add` records a string; nothing is contacted.
git_origin() {
  git -c init.defaultBranch=main init -q "$1" >/dev/null 2>&1
  git -C "$1" remote add origin "$2" >/dev/null 2>&1
}

# run_gate <dir> — echoes "<rc>\n<output>"; the caller reads rc from the first line. The gate's own exit
# code is the thing under test, so it is captured explicitly rather than let into an `if`.
run_gate() {
  local d="$1" out rc
  out="$(SCAN_ROOT="$d" AUTOSYNC="$d/scripts/template-autosync.sh" bash "$GATE" 2>&1)"
  rc=$?
  printf '%s\n' "$rc"
  printf '%s\n' "$out" > "$d/.gate-out"
}

gate_out() { cat "$1/.gate-out"; }

printf 'no-sigpipe-assertions self-test\n\n'

# --- ARM 1 — a positive assertion carrying the idiom is REFUSED, with file and line -------------------
D="$SANDBOX_ROOT/arm1"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if printf '%s' "$OUT" | grep -q "hello"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 1 ] && grep -q 'scripts/test-thing.sh:4' <<< "$OUT"; then
  ok "a positive assertion is refused, named by file and line"
else
  bad "a positive assertion is refused, named by file and line" "rc=$RC out=$(head -3 <<< "$OUT")"
fi

# The refusal has to carry the replacement. A gate that says "no" without saying "instead" is a gate the
# next author routes around.
if grep -q 'here-string' <<< "$OUT"; then
  ok "…and the refusal names the replacement form"
else
  bad "…and the refusal names the replacement form" "no here-string suggestion in the output"
fi

# --- ARM 2 — a diagnostic pipe is NOT an assertion (SC-1733) ------------------------------------------
# `else bad "…"; printf … | head -4` prints context AFTER bad has already counted the failure. Its exit
# status is never read. This is the shape the gate first mis-filed as UNDECIDED, which is why it is here.
D="$SANDBOX_ROOT/arm2"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if grep -q "hello" <<< "$OUT"; then ok "fine"
else bad "not fine"; printf '        %s\n' "$OUT" | head -4
fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 0 ]; then
  ok "a diagnostic pipe inside a bad-arm is exempt"
else
  bad "a diagnostic pipe inside a bad-arm is exempt" "rc=$RC out=$(gate_out "$D" | head -3)"
fi

# --- ARM 3 — an all-consuming consumer cannot orphan the writer (SC-1734) ------------------------------
# grep -c and wc read stdin to EOF. There is no early exit, so there is no SIGPIPE and nothing to fix.
# Refusing these would make the gate a nuisance about lines that are already correct.
D="$SANDBOX_ROOT/arm3"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="a
b"
if [ "$(printf '%s\n' "$OUT" | grep -c 'a')" -eq 1 ]; then echo one; fi
if [ "$(printf '%s\n' "$OUT" | wc -l)" -ge 1 ]; then echo lines; fi
N=$(printf '%s\n' "$OUT" | sort | head -1)
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 0 ]; then
  ok "grep -c / wc / an assigned command substitution are exempt"
else
  bad "grep -c / wc / an assigned command substitution are exempt" "rc=$RC out=$(gate_out "$D" | head -4)"
fi

# --- ARM 4 — a CORE file carrying the idiom is exempt DOWNSTREAM (SC-1735) -----------------------------
# NOT because the idiom is fine there. Because a fix written into a sync-owned file is overwritten by the
# next `chore(sync)` — the H7t lesson — so the gate would nag forever about a line this repo cannot
# durably change. Those files are scanned in the template instead (ARM 14), and the gate must say so.
D="$SANDBOX_ROOT/arm4"; build_tree "$D"
cat > "$D/scripts/test-core-owned.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if printf '%s' "$OUT" | grep -q "hello"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 0 ] && grep -q 'mode: downstream' <<< "$OUT"; then
  ok "a CORE (sync-owned) self-test is exempt downstream — the sync would eat the fix"
else
  bad "a CORE (sync-owned) self-test is exempt downstream" "rc=$RC out=$(head -3 <<< "$OUT")"
fi

# …and with the whole population exempted the gate must NOT say "clean". There is no verdict about files
# nobody opened, and a green line that reads as one is the defect row H7ax removed. (SC-1749)
if grep -q 'NOT RUN' <<< "$OUT" && ! grep -q 'clean' <<< "$OUT"; then
  ok "…and an emptied population reports NOT RUN, never clean"
else
  bad "…and an emptied population reports NOT RUN, never clean" "$(tail -3 <<< "$OUT")"
fi

# …and the second signal is the one that decided it: no git remote here, only the sync's own stamp.
# The affirmative phrase, not the bare filename: the undecidable message names the stamp too ("neither an
# origin remote nor a sync stamp answers"), so a grep for `.template-sync` alone passes for the tree that
# could not decide. Measured — falsification M-D went BLIND against exactly that assertion.
if grep -q '.claude/.template-sync is present' <<< "$OUT"; then
  ok "…and the mode names the signal that decided it (.claude/.template-sync)"
else
  bad "…and the mode names the signal that decided it (.claude/.template-sync)" "$(grep '^mode' <<< "$OUT")"
fi

# …and the exemption must come from the LIST, not from the name. Move the same file out of CORE_SCRIPTS
# and it must be refused — otherwise ARM 4 is passing for the wrong reason.
D="$SANDBOX_ROOT/arm4b"; build_tree "$D"
sed -i.bak 's/^test-core-owned\.sh //' "$D/scripts/template-autosync.sh"
cat > "$D/scripts/test-core-owned.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if printf '%s' "$OUT" | grep -q "hello"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 1 ]; then
  ok "…and that exemption comes from CORE_SCRIPTS, not from the filename"
else
  bad "…and that exemption comes from CORE_SCRIPTS, not from the filename" "rc=$RC"
fi

# --- ARM 5 — the NEGATED direction is refused too ------------------------------------------------------
# This is the face H7h never described and the one that matters: 141 inverted by `!` is TRUE, so the
# assertion PASSES for exactly the state it forbids. A gate that only caught the loud direction would
# leave every silent one standing.
D="$SANDBOX_ROOT/arm5"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if ! printf '%s' "$OUT" | grep -q "forbidden"; then echo clean; fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 1 ] && grep -q 'test-thing.sh:4' <<< "$(gate_out "$D")"; then
  ok "a negated assertion — the silent-pass direction — is refused"
else
  bad "a negated assertion — the silent-pass direction — is refused" "rc=$RC"
fi

# --- ARM 6 — the fixed form is accepted ----------------------------------------------------------------
# The gate has to have a shape it says yes to. Without this arm "clean" could mean "the scanner is broken".
D="$SANDBOX_ROOT/arm6"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if grep -q "hello" <<< "$OUT"; then echo yes; fi
if ! grep -qE "forbidden" <<< "$OUT"; then echo clean; fi
if grep -q "x" "$0"; then echo file; fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 0 ]; then
  ok "the here-string and direct-file forms are accepted"
else
  bad "the here-string and direct-file forms are accepted" "rc=$RC out=$(gate_out "$D" | head -3)"
fi

# --- ARM 7 — a comment that quotes the idiom is not a hit ---------------------------------------------
# Every file that explains this defect has to write the banned idiom down. test-census-alarm-tokens.sh
# already does, and so does the gate's own header. A scanner that counted those would be unusable in the
# one place the lesson is written.
D="$SANDBOX_ROOT/arm7"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
# THE IDIOM IS DELIBERATELY NOT `printf ... | grep -q` — under pipefail it returns 141.
OUT="hello"
if grep -q "hello" <<< "$OUT"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 0 ]; then
  ok "a comment quoting the idiom is not counted"
else
  bad "a comment quoting the idiom is not counted" "rc=$RC out=$(gate_out "$D" | head -3)"
fi

# --- ARM 8 — head and grep -m in an assertion are refused ----------------------------------------------
# grep -q is not the only early exit. `find … | head -1 | grep -q .` orphans find the same way, and
# `grep -m 1` orphans its writer after one match. A gate keyed to the literal string `grep -q` would miss
# both and report a clean tree it never checked properly.
D="$SANDBOX_ROOT/arm8"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if find . -name '*.cs' | head -1 | grep -q .; then echo found; fi
if printf 'a\nb\n' | grep -m 1 'a'; then echo m; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 1 ] && [ "$(grep -c 'test-thing.sh:' <<< "$OUT")" -eq 2 ]; then
  ok "head and grep -m are early exits too, and both are refused"
else
  bad "head and grep -m are early exits too, and both are refused" \
      "rc=$RC hits=$(grep -c 'test-thing.sh:' <<< "$OUT")"
fi

# --- ARM 9 — a tree with nothing to scan is a REFUSAL, not silence -------------------------------------
# K5: zero results are a fault until proven benign. A gate that prints "clean" for a directory it found no
# files in is the exact shape this series keeps removing.
D="$SANDBOX_ROOT/arm9"; build_tree "$D"
RC="$(run_gate "$D")"
if [ "$RC" -eq 2 ] && grep -q 'nothing was scanned' <<< "$(gate_out "$D")"; then
  ok "an empty tree is refused with rc 2, not reported clean"
else
  bad "an empty tree is refused with rc 2, not reported clean" "rc=$RC"
fi

# --- ARM 10 — an unreadable CORE boundary is a REFUSAL --------------------------------------------------
# Without CORE_SCRIPTS the gate cannot tell a durable fix from one the next sync eats. Guessing either way
# is wrong: guess "none are CORE" and it nags about files this repo cannot change; guess "all are" and it
# goes quiet about the ones it can.
D="$SANDBOX_ROOT/arm10"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
if printf '%s' "x" | grep -q x; then echo y; fi
EOF
: > "$D/scripts/template-autosync.sh"
RC="$(run_gate "$D")"
if [ "$RC" -eq 2 ] && grep -q 'CORE_SCRIPTS' <<< "$(gate_out "$D")"; then
  ok "an unreadable CORE boundary is refused rather than guessed"
else
  bad "an unreadable CORE boundary is refused rather than guessed" "rc=$RC"
fi

# --- ARM 11 — a heredoc body is fixture data, and code around it is still checked ----------------------
# This file itself is the reason: it has to write the banned idiom into seven fixtures, and the first
# version of the gate flagged all seven. Exempting heredoc bodies makes the gate testable; the second half
# of the arm is what keeps that exemption from becoming a hiding place.
D="$SANDBOX_ROOT/arm11"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'OUTER'
#!/usr/bin/env bash
set -uo pipefail
cat > /dev/null <<'INNER'
if printf '%s' "$OUT" | grep -q "hello"; then echo yes; fi
INNER
if grep -q "hello" <<< "ok"; then echo yes; fi
OUTER
RC="$(run_gate "$D")"
if [ "$RC" -eq 0 ]; then
  ok "a heredoc body is fixture data, not an assertion"
else
  bad "a heredoc body is fixture data, not an assertion" "rc=$RC out=$(gate_out "$D" | head -3)"
fi

D="$SANDBOX_ROOT/arm11b"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'OUTER'
#!/usr/bin/env bash
set -uo pipefail
cat > /dev/null <<'INNER'
harmless fixture text
INNER
if printf '%s' "$OUT" | grep -q "hello"; then echo yes; fi
OUTER
RC="$(run_gate "$D")"
if [ "$RC" -eq 1 ] && grep -q 'test-thing.sh:6' <<< "$(gate_out "$D")"; then
  ok "…and a real assertion AFTER the heredoc closes is still refused"
else
  bad "…and a real assertion AFTER the heredoc closes is still refused" "rc=$RC"
fi

# --- ARM 12 — a pipe inside a quoted string is prose, and code beside it is still checked --------------
# The failure message this gate prints has to name the idiom it rejects, and so does every diagnostic that
# explains the defect to a reader. If the scanner counted those, the cheapest way to a green tree would be
# to reword the explanation — a gate that pressures authors into deleting the explanation of the thing it
# guards is worse than no gate. The second half keeps the exemption from becoming a hiding place: real code
# on the same line is still found.
D="$SANDBOX_ROOT/arm12"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="x"
if grep -q "x" <<< "$OUT"; then ok "fine"
else bad "fine" "expected 'printf | grep -q' to be named here, as prose"
fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 0 ]; then
  ok "the idiom named inside a quoted message is prose, not a pipeline"
else
  bad "the idiom named inside a quoted message is prose" "rc=$RC out=$(gate_out "$D" | head -3)"
fi

D="$SANDBOX_ROOT/arm12b"; build_tree "$D"
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="x"
if printf '%s' "$OUT" | grep -q "x"; then echo "mentions 'printf | grep -q' as well"; fi
EOF
RC="$(run_gate "$D")"
if [ "$RC" -eq 1 ]; then
  ok "…and a real pipeline on a line that also quotes the idiom is still refused"
else
  bad "…and a real pipeline on a line that also quotes the idiom is still refused" "rc=$RC"
fi

# --- ARM 14 — in the TEMPLATE the exemption inverts, and the same file is REFUSED (SC-1746) ------------
# The red case for the change itself. ARM 4's fixture, one line different: the tree's origin is the
# declared template. There "CORE" means "mine" — every one of those files is fixable and the fix is what
# every project's copy comes from — so exempting them is the opposite of what the exemption is for. Ported
# verbatim, the gate scanned 5 of the template's 22 self-tests and printed `clean`, excusing precisely the
# files the sweep it enforces was written for.
D="$SANDBOX_ROOT/arm14"; build_tree "$D" template
cat > "$D/scripts/test-core-owned.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
OUT="hello"
if printf '%s' "$OUT" | grep -q "hello"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 1 ] && grep -q 'test-core-owned.sh:4' <<< "$OUT" && grep -q 'mode: template' <<< "$OUT"; then
  ok "in the template the same CORE file is refused, not exempted"
else
  bad "in the template the same CORE file is refused" "rc=$RC out=$(head -4 <<< "$OUT")"
fi

# --- ARM 15 — a foreign origin reads downstream, and the exemption is counted (SC-1747) ----------------
# Two files so the population is not empty: without the clean one this arm would pass through ARM 4's
# NOT RUN branch and prove nothing about the exemption being APPLIED rather than the tree being bare.
D="$SANDBOX_ROOT/arm15"; build_tree "$D" foreign
cat > "$D/scripts/test-core-owned.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if printf '%s' "x" | grep -q "x"; then echo yes; fi
EOF
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if grep -q "x" <<< "x"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 0 ] && grep -q 'mode: downstream' <<< "$OUT" \
   && grep -q 'population: 1 of 2 scripts/test-\*\.sh in scope, 1 exempt' <<< "$OUT"; then
  ok "a foreign origin reads downstream, and the population line counts the exemption"
else
  bad "a foreign origin reads downstream, and the population line counts the exemption" \
      "rc=$RC $(grep '^population' <<< "$OUT")"
fi

# --- ARM 16 — the template is the one the FIXTURE declares, not a name the gate carries (SC-1748) ------
# The mirror of ARM 4b, one level up. This tree's origin IS the real template repo, but the autosync it
# was handed declares acme/Template. A gate carrying the real slug would call this the template and stop
# exempting; reading the slug from the file, it correctly calls it downstream. A copied boundary is a
# boundary that is wrong the day the template moves.
D="$SANDBOX_ROOT/arm16"; build_tree "$D" realorigin
cat > "$D/scripts/test-core-owned.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if printf '%s' "x" | grep -q "x"; then echo yes; fi
EOF
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if grep -q "x" <<< "x"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 0 ] && grep -q 'mode: downstream' <<< "$OUT"; then
  ok "the template's identity is read from TEMPLATE_REPO_URL, not carried in the gate"
else
  bad "the template's identity is read from TEMPLATE_REPO_URL, not carried in the gate" \
      "rc=$RC $(grep '^mode' <<< "$OUT")"
fi

# --- ARM 17 — an undecidable tree scans EVERYTHING and says why (SC-1750) ------------------------------
# No origin, no sync stamp. The two ways to be wrong are not symmetric: exempt wrongly and the gate goes
# quiet about files it could have fixed (this row's defect, invisible); scan wrongly and it nags about
# files a sync will overwrite (loud, and the next reader corrects it). Doubt resolves toward looking.
D="$SANDBOX_ROOT/arm17"; build_tree "$D" unknown
cat > "$D/scripts/test-core-owned.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if printf '%s' "x" | grep -q "x"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
OUT="$(gate_out "$D")"
if [ "$RC" -eq 1 ] && grep -q 'undecidable' <<< "$OUT"; then
  ok "an undecidable tree scans everything rather than going quiet, and names the doubt"
else
  bad "an undecidable tree scans everything rather than going quiet" "rc=$RC $(grep '^mode' <<< "$OUT")"
fi

# --- ARM 18 — the population line is printed in EVERY branch (SC-1751) ---------------------------------
# The one fact that would have caught this gate going blind is how many files it opened out of how many it
# found. A number you only see when something else already went wrong is a number nobody has, so it is
# asserted on the clean branch, the failing branch, and --list.
D="$SANDBOX_ROOT/arm18"; build_tree "$D" foreign
cat > "$D/scripts/test-thing.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if grep -q "x" <<< "x"; then echo yes; fi
EOF
RC="$(run_gate "$D")"
CLEAN_OUT="$(gate_out "$D")"
LIST_OUT="$(SCAN_ROOT="$D" AUTOSYNC="$D/scripts/template-autosync.sh" bash "$GATE" --list 2>&1)"
FAIL_OUT="$(gate_out "$SANDBOX_ROOT/arm14")"
N=0
grep -q '^population:' <<< "$CLEAN_OUT" && N=$((N + 1))
grep -q '^population:' <<< "$LIST_OUT"  && N=$((N + 1))
grep -q 'population:'  <<< "$FAIL_OUT"  && N=$((N + 1))
if [ "$N" -eq 3 ]; then
  ok "the population line is printed on the clean, failing and --list branches alike"
else
  bad "the population line is printed on the clean, failing and --list branches alike" \
      "only $N of 3 branches carried it"
fi

# --- ARM 13 — the real repo is clean (SC-1731) ---------------------------------------------------------
# The only arm that touches the real tree. It is last on purpose: if the sweep regresses, every fixture arm
# above still passes and this one alone goes red, which points at the tree rather than at the gate.
REAL_OUT="$(bash "$GATE" 2>&1)"; REAL_RC=$?
if [ "$REAL_RC" -eq 0 ]; then
  ok "the real tree is clean"
else
  bad "the real tree is clean" "rc=$REAL_RC — $(tail -3 <<< "$REAL_OUT")"
fi

printf '\nno-sigpipe-assertions self-test: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
