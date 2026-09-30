#!/bin/bash
# Harness for scripts/validate-sync-sandbox-declarations.sh and the interlock it protects
# (spec 010 from consultpilot H7bm; spec 011 from consultpilot H7bo).
#
# A gate nobody has watched fail is a report, not a gate — this project's own lesson (spec 007bs,
# where four comments cited a traceability script that did not exist as having "reported 100% and
# exit 0"). So most of what is below is negative: fixtures written to be WRONG, each asserting that
# the gate names them and refuses. The passing cases only prove it is not refusing everything.
#
# Two sections are different in kind. AC-12/AC-12b assert the PROPERTY the query-mode exemption
# rests on — that all four query modes return from template-autosync.sh above the project-root
# resolution — rather than trusting a list of exempt files. Move one below the resolution and it
# reddens, and the exemption stops applying on its own. AC-60 asserts the argued exclusion list is
# exactly four entries and that deleting any one of them makes the gate report that file.
#
# Offline, in both halves and for different reasons. The gate half builds fixture scripts as text
# and never starts anything. The interlock half DOES run the real sync — there is no other way to
# check an interlock — but always against a local fixture template, so `refresh_local_template`
# returns at its origin-URL check and no run touches the network. The first draft of this file hit
# GitHub twenty times per run (71 s, of which 66 s was fetching).
#
# Labels. AC-01..AC-32 keep spec 010's numbering (AC-31/AC-32 are its CDPATH and GIT_DIR arms).
# consultpilot's H7bo AC-31..AC-42 are AC-45..AC-56 here, its AC-37 census is AC-57 and its per-driver
# arms AC-36 are AC-58; each carries "(H7bo AC-nn)". AC-59..AC-61 are spec 011's own.
#
# Scenario ids deliberately absent: this file is CORE and ships into projects whose SC numbering
# is their own (row 012).
#
# Run: bash scripts/test-validate-sync-sandbox-declarations.sh

set -u
cd "$(dirname "$0")/.." || exit 1
GATE="$PWD/scripts/validate-sync-sandbox-declarations.sh"
SYNC="$PWD/scripts/template-autosync.sh"
[ -f "$GATE" ] || { echo "FAIL: gate not found: $GATE"; exit 1; }
[ -f "$SYNC" ] || { echo "FAIL: template-autosync.sh not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')"; printf '       got: %s\n' "$(printf '%s' "$2" | tr '\n' '|' | cut -c1-220)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }
same()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# A fixture repo the gate can be pointed at: only scripts/ matters to it.
fixture() {  # fixture <name> -> echoes the root
  _r="$TMP/$1"; rm -rf "$_r"; mkdir -p "$_r/scripts"
  cp "$SYNC" "$_r/scripts/template-autosync.sh"
  # The helper belongs in every fixture: a real project has one, and the gate asserts there is
  # exactly one definition site. AC-35 is the fixture that deliberately does not.
  cp "$PWD/scripts/drive-sync.sh" "$_r/scripts/drive-sync.sh"
  printf '%s' "$_r"
}
gate() { SANDBOX_GATE_ROOT="$1" bash "$GATE" 2>&1; }
gate_rc() { SANDBOX_GATE_ROOT="$1" bash "$GATE" >/dev/null 2>&1; }

echo "== AC-01: the repository as it stands passes =="
OUT=$(bash "$GATE"); RC=$?
same "the gate exits 0 on the repo as it stands"  "$RC" "0"
has  "…reporting zero direct invocations"         "$OUT" "0 direct invocations outside the helper"
has  "…and query-mode exemptions, counted"        "$OUT" "exempt (query modes only)"
has  "…and two by self-reference"                 "$OUT" "2 by self-reference"
# Under spec 010 each compliant driver printed an `ok` line, because compliance was a property of an
# invocation the gate could see. Under spec 011 compliance is the ABSENCE of one, so the successor
# assertion is that none of the six is reported at all.
for d in test-template-autosync-stranded test-core-owed-tick-guard test-sync-count-honesty \
         test-template-autosync-owed test-template-autosync-eol test-template-autosync-unlisted; do
  hasnt "  $d is not reported"                    "$OUT" "scripts/$d.sh:"
done

echo "== AC-02: SABOTAGE — a script that runs the sync directly is named =="
# The arm that makes this a gate. Without it, every assertion above is satisfied by a script that
# prints "ok" unconditionally.
R=$(fixture sabotage)
cat > "$R/scripts/test-rogue.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && bash "$SYNC" --force ); }
run /tmp/whatever
EOS
OUT=$(gate "$R"); RC=$?
same "the gate exits 1"                           "$RC" "1"
has  "names the file and the line"                "$OUT" "scripts/test-rogue.sh:3"
has  "says what is wrong"                         "$OUT" "instead of through drive_sync"
has  "counts it"                                  "$OUT" "1 violation(s)"
has  "and shows the offending text"               "$OUT" 'bash "$SYNC" --force'

echo "== AC-03: the new rule is STRICTER — both halves is still a violation =="
# spec 010 asked "does this invocation carry both halves?" and passed a hand-spelled driver that did.
# spec 011 asks "is there an invocation at all?", so the same file now fails. This is the one place the
# two rules give different answers, and the difference is the point of the row: a driver that
# remembered both halves today is a driver that can forget one tomorrow.
R=$(fixture handspelled)
cat > "$R/scripts/test-handspelled.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" bash "$SYNC" --force ); }
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1 even with both halves spelled"      "$RC" "1"
has  "…naming the line"                           "$OUT" "scripts/test-handspelled.sh:3"

echo "== AC-04: one half is a violation too, for the same single reason =="
R=$(fixture halfway)
cat > "$R/scripts/test-halfway.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$SYNC" --force ); }
EOS
gate_rc "$R"; same "exits 1 with only the target named" "$?" "1"

echo "== AC-05: a driver that goes through the helper passes =="
R=$(fixture compliant)
cat > "$R/scripts/test-good.sh" <<'EOS'
#!/bin/bash
. "$PWD/scripts/drive-sync.sh"
run() { drive_sync "$1" "$TMP" --force; }
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
hasnt "…and the compliant driver is not reported" "$OUT" "test-good.sh"

echo "== AC-06: a continuation line does not hide the interpreter =="
# spec 010 needed a two-line lookback window to find the DECLARATION above an invocation. That window
# is gone, and this is its successor: the thing that must still be found is the invocation itself,
# wherever the line breaks fall.
#
# `\`-continuations are joined before the check — they must be, because `bash \` on one line and
# the path on the next put the interpreter and its target on different physical lines and each half
# alone looks innocent. The line REPORTED is the one that names the sync. consultpilot's gate
# reported the statement's first line (3 here); the lexer keeps each token's own line, and the line
# holding the path is the one a reader edits.
R=$(fixture continued)
cat > "$R/scripts/test-wrapped.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" \
    && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" \
       bash "$SYNC" --force ); }
EOS
OUT=$(gate "$R"); RC=$?
same "a wrapped invocation is still an invocation" "$RC" "1"
has  "…reported at the line that names the sync"    "$OUT" "scripts/test-wrapped.sh:5"

echo "== AC-07: an --is-core-only caller is exempt, and counted as exempt =="
R=$(fixture iscore)
cat > "$R/scripts/test-iscore-only.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
bash "$SYNC" --is-core scripts/whatever.sh >/dev/null 2>&1
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
has  "counted as exempt, not as a driver"         "$OUT" "1 exempt (query modes only)"
hasnt "…and not reported as a violation"          "$OUT" "test-iscore-only.sh:"

echo "== AC-07b: the other three query modes are exempt the same way =="
# The template has four modes that return above the project-root resolution; consultpilot's spec 011 gate
# knew only --is-core and reported the other three as violations here.
R=$(fixture querymodes)
cat > "$R/scripts/test-query-modes.sh" <<'EOS'
#!/bin/bash
TA="$PWD/scripts/template-autosync.sh"
N=$(bash "$TA" --list-core-scripts 2>/dev/null | wc -l)
done < <(bash "$TA" --list-core-rules 2>/dev/null)
TPL=$(bash scripts/template-autosync.sh --template-dir 2>/dev/null)
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
has  "counted as one exempt file"                 "$OUT" "1 exempt (query modes only)"

echo "== AC-08: one --is-core call does NOT exempt a script that also drives =="
# The exemption is per SCRIPT but earned per INVOCATION: a file that asks --is-core somewhere and
# syncs somewhere else is a driver.
R=$(fixture mixed)
cat > "$R/scripts/test-mixed.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
bash "$SYNC" --is-core scripts/x.sh >/dev/null 2>&1
( cd /tmp/sbx && bash "$SYNC" --force )
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…naming the syncing line, not the --is-core one" "$OUT" "scripts/test-mixed.sh:4"
hasnt "…and does not report line 3"               "$OUT" "test-mixed.sh:3"

echo "== AC-09: a script that only NAMES the sync is not a driver =="
# The measured case is test-template-clone-refresh.sh: it sed-extracts one function and passes the
# target as an argument, so it never resolves a project root. The first census of this defect got
# that file wrong by looking for a variable name instead of an invocation.
R=$(fixture mentions)
cat > "$R/scripts/test-mentions.sh" <<'EOS'
#!/bin/bash
SCRIPT="$PWD/scripts/template-autosync.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: template-autosync.sh not found at $SCRIPT"; exit 1; }
sed -n '/^refresh_local_template() {$/,/^}$/p' "$SCRIPT" > /tmp/harness
grep -c 'template-autosync.sh' "$SCRIPT"
cp "$SCRIPT" /tmp/elsewhere/template-autosync.sh
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0 — extraction and copying are not invocation" "$RC" "0"
hasnt "…and it is not reported"                   "$OUT" "test-mentions.sh"

echo "== AC-10: a filename ending in .sh does not read as an interpreter =="
# A project's run-gates.sh GATES array lists dozens of scripts/*.sh and its comments name the sync. Before the
# word-boundary fix the trailing `sh` of every filename matched `(bash|sh)` and the array read as
# fifty invocations.
R=$(fixture listing)
cat > "$R/scripts/test-listing.sh" <<'EOS'
#!/bin/bash
WANT="scripts/foo.sh scripts/template-autosync.sh scripts/bar.sh"
GATES=(
  scripts/test-sync-count-honesty.sh   # a comment mentioning scripts/template-autosync.sh
)
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
hasnt "a list of filenames is not a driver"       "$OUT" "test-listing.sh"

echo "== AC-11: the gate starts nothing =="
# If the gate executed what it reads, a fixture whose "sync" is a tripwire would leave a mark.
R=$(fixture offline)
printf '#!/bin/bash\ntouch "%s/TRIPPED"\n' "$TMP" > "$R/scripts/template-autosync.sh"
cat > "$R/scripts/test-driver.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
( cd "$1" && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX="$2" bash "$SYNC" )
EOS
gate "$R" >/dev/null 2>&1
[ -f "$TMP/TRIPPED" ] && bad "the gate executed a script it read" || ok "no fixture script was run"

echo "== AC-12: the --is-core exemption's PROPERTY, not its filenames =="
# Everything above trusts that --is-core cannot resolve a project root. This is where that is
# checked. Two independent readings, because either alone can rot:
IS_CORE_LINE=$(grep -n 'IS_CORE_REL' "$SYNC" | tail -1 | cut -d: -f1)
RESOLVE_LINE=$(grep -n 'DIR="${CLAUDE_PROJECT_DIR:-\$PWD}"' "$SYNC" | head -1 | cut -d: -f1)
if [ -n "$IS_CORE_LINE" ] && [ -n "$RESOLVE_LINE" ]; then
  if [ "$IS_CORE_LINE" -lt "$RESOLVE_LINE" ]; then
    ok "--is-core handling ends above the project-root resolution ($IS_CORE_LINE < $RESOLVE_LINE)"
  else
    bad "--is-core now reaches the project-root resolution ($IS_CORE_LINE >= $RESOLVE_LINE) — the exemption in validate-sync-sandbox-declarations.sh is no longer sound"
  fi
else
  bad "could not locate the --is-core block or the resolution line in template-autosync.sh"
fi
# And behaviourally: --is-core answers identically whether or not a project root exists to resolve.
OUTSIDE=$(mktemp -d)
# The subject must be NON-CORE, and that is the whole subtlety. --is-core answers from the path
# alone, so its answer is location-independent — which is exactly the property being asserted, and
# why the assertion is "identical", not "different".
#
# It only discriminates with a non-CORE subject. On a CORE path the answer is 0, and a run outside
# any git repo also exits 0 via the quiet skip, so that comparison is 0 against 0 and would still
# pass with the --is-core branch moved BELOW the project-root resolution. On README.md the answer
# is 1; move the branch down and the outside-repo run reaches the quiet skip and returns 0 instead,
# and this reddens. Same shape, one word changed, and only one of the two can fail.
A=$( cd "$OUTSIDE" && bash "$SYNC" --is-core README.md >/dev/null 2>&1; echo $? )
B=$( bash "$SYNC" --is-core README.md >/dev/null 2>&1; echo $? )
rm -rf "$OUTSIDE"
same "--is-core answers the same in and outside a repo (non-CORE subject)" "$A" "$B"

echo "== AC-12b: the same property for --list-core-scripts, --list-core-rules, --template-dir =="
for flag in MODE_TEMPLATE_DIR MODE_LIST_SCRIPTS MODE_LIST_RULES; do
  L=$(grep -nE "^if \[ \"[\$]$flag\"[[:space:]]+-eq 1 \]" "$SYNC" | head -1 | cut -d: -f1)
  if [ -n "$L" ] && [ -n "$RESOLVE_LINE" ] && [ "$L" -lt "$RESOLVE_LINE" ]; then
    ok "$flag is answered above the project-root resolution ($L < $RESOLVE_LINE)"
  else
    bad "$flag is not answered above the resolution (line '${L:-?}') — its exemption is no longer sound"
  fi
done
OUTSIDE=$(mktemp -d)
A=$( cd "$OUTSIDE" && bash "$SYNC" --list-core-scripts 2>/dev/null | wc -l | tr -d ' ' )
B=$( bash "$SYNC" --list-core-scripts 2>/dev/null | wc -l | tr -d ' ' )
rm -rf "$OUTSIDE"
same "--list-core-scripts answers the same in and outside a repo" "$A" "$B"

echo "== AC-45 (H7bo AC-31): a command written inside a string is text, not a command =="
# The class that cost spec 010 four of its six exclusions, closed here as a property. Every fixture
# below is a real shape from this repository: a refusal message quoting the fix command, a help
# line, a systemMessage. The gate must read all of them as prose AND still find the real
# invocation that follows, which is what makes this a pair of assertions rather than one.
R=$(fixture quoted)
cat > "$R/scripts/test-quoting.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
say "          bash scripts/template-autosync.sh … )"
WHERE="Edit it there, then bring it here the way every other project gets it:

  bash $ROOT/scripts/template-autosync.sh --force"
printf 'run %s\n' 'bash scripts/template-autosync.sh --owed'
cat <<'HEREDOC'
  bash scripts/template-autosync.sh --unlisted   # 1 = nothing unlisted
HEREDOC
echo "done"   # bash scripts/template-autosync.sh --check
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0 — five quoted forms, none a command" "$RC" "0"
hasnt "…and none is reported"                      "$OUT" "test-quoting.sh"

echo "== AC-46 (H7bo AC-32): …and a real invocation right after each one is still found =="
# The dangerous direction. A quote-tracker that got the state wrong would swallow the NEXT line
# too, and the gate would report a clean repository while a driver walked out.
R=$(fixture quoted_then_real)
cat > "$R/scripts/test-after-quotes.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
say "  bash scripts/template-autosync.sh"
bash "$SYNC" --force
WHERE="line one
  bash scripts/template-autosync.sh --force"
bash "$SYNC" --check
cat <<'HEREDOC'
  bash scripts/template-autosync.sh
HEREDOC
bash "$SYNC" --owed
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "finds the one after a single-line string"   "$OUT" "test-after-quotes.sh:4"
has  "finds the one after a multi-line string"    "$OUT" "test-after-quotes.sh:7"
has  "finds the one after a heredoc"              "$OUT" "test-after-quotes.sh:11"
has  "…and counts exactly three"                  "$OUT" "3 violation(s)"

echo "== AC-47 (H7bo AC-33): a handle still counts — the derivation was not the expensive part =="
# The tempting simplification was "match only the literal path". It would have made
# `S="$D/template-autosync.sh"; bash "$S"` invisible, i.e. traded a maintainability win for a hole
# in a security interlock.
R=$(fixture handle)
cat > "$R/scripts/test-handle.sh" <<'EOS'
#!/bin/bash
S="$PWD/scripts/template-autosync.sh"
( cd /tmp && exec "$S" --force )
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…naming the exec through a variable"        "$OUT" "scripts/test-handle.sh:3"

echo "== AC-48 (H7bo AC-34): the helper's exemption is a property, and the property is CHECKED =="
# The price of exempting the helper by "this file defines drive_sync" rather than by name. Without
# this assertion any driver could define its own drive_sync() and be exempt from the rule it is
# meant to obey — the property would be the hole.
R=$(fixture twodefs)
cat > "$R/scripts/test-impostor.sh" <<'EOS'
#!/bin/bash
drive_sync() { bash "$PWD/scripts/template-autosync.sh" "$@"; }
drive_sync --force
EOS
OUT=$(gate "$R"); RC=$?
same "a second definition site exits 1"           "$RC" "1"
has  "…and is named as a way out of the gate"     "$OUT" "a way out of this gate"
has  "…listing the impostor"                      "$OUT" "test-impostor.sh"

echo "== AC-48b: …including inside a file on the argued exclusion list =="
# An excluded file is not judged for runs, so it is the one place a reviewer would stop looking — and
# a drive_sync() defined there would still be a way out for every file that sources it.
R=$(fixture exclimpostor)
cat > "$R/scripts/lane-catchup.sh" <<'EOS'
#!/bin/bash
drive_sync() { bash "$PWD/scripts/template-autosync.sh" "$@"; }
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…named as a way out"                        "$OUT" "a way out of this gate"
has  "…listing the excluded file"                 "$OUT" "scripts/lane-catchup.sh"

echo "== AC-49 (H7bo AC-35): a tree with no helper at all is reported, not silently trusted =="
R=$(fixture nohelper); rm -f "$R/scripts/drive-sync.sh"
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…saying the exemption is unanchored"        "$OUT" "nothing defines drive_sync"

echo "== AC-52 (H7bo AC-38): the five bypasses the adversarial review found =="
# Every one of these got past an earlier draft of this gate, and TWO were already live in this
# repository — `test-no-sigpipe-assertions.sh` is a scanner candidate whose line 116 is a
# here-string, and the scanner was silently skipping that file from line 116 of 522 while
# reporting the tree clean. A fix without a failing test is a claim; these are the tests.
R=$(fixture bypasses)
cat > "$R/scripts/test-bypasses.sh" <<'EOS'
#!/bin/bash
export SYNC="$PWD/scripts/template-autosync.sh"
grep -q "hello" <<< "ok"
bash scripts/template-autosync.sh --here-string
cat <<MY-EOF
body
MY-EOF
bash scripts/template-autosync.sh --punctuated-delimiter
source "$PWD/scripts/template-autosync.sh" --source
. "$PWD/scripts/template-autosync.sh" --dot
bash \
  "$PWD/scripts/template-autosync.sh" --continuation
eval "bash $PWD/scripts/template-autosync.sh --eval"
bash "$SYNC" --exported-handle
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                      "$RC" "1"
has  "a here-string is not a heredoc open"          "$OUT" "test-bypasses.sh:4"
has  "a punctuated heredoc delimiter still closes"  "$OUT" "test-bypasses.sh:8"
has  "source runs it"                               "$OUT" "test-bypasses.sh:9"
has  "so does the dot form"                         "$OUT" "test-bypasses.sh:10"
has  "a \\-continuation does not split the check"   "$OUT" "test-bypasses.sh:12"
has  "eval executes its quoted argument"            "$OUT" "test-bypasses.sh:13"
has  "an exported handle is still a handle"         "$OUT" "test-bypasses.sh:14"
has  "…and all seven are counted"                   "$OUT" "7 violation(s)"

echo "== AC-53 (H7bo AC-39): a here-string does not swallow the rest of the file =="
# The failure this guards is silence, not a wrong answer: the scanner returned early with exit 0
# and no stderr, so SCAN_ERR could not catch it either. The assertion is that a real invocation
# AFTER a here-string is still found.
R=$(fixture herestring)
cat > "$R/scripts/test-hs.sh" <<'EOS'
#!/bin/bash
if grep -q 'x' <<< "$OUT"; then echo yes; fi
head -3 <<< "$OUT"
bash scripts/template-autosync.sh --after-here-strings
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "the line after two here-strings is found"   "$OUT" "test-hs.sh:4"

echo "== AC-54 (H7bo AC-40): scripts/ is searched to its leaves =="
# `scripts/*.sh` does not recurse, so a scripts/lib/ was invisible to BOTH the invocation scan and
# the uniqueness assertion that guards the helper's property exemption — the check and the thing it
# checks sharing one blind spot.
R=$(fixture subdir); mkdir -p "$R/scripts/lib"
printf '#!/bin/bash\nbash "$PWD/scripts/template-autosync.sh" --force\n' > "$R/scripts/lib/sneaky.sh"
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…naming the nested path in full"            "$OUT" "scripts/lib/sneaky.sh:2"

echo "== AC-55 (H7bo AC-41): a nested second drive_sync definition is found too =="
R=$(fixture subdirdef); mkdir -p "$R/scripts/lib"
printf '#!/bin/bash\ndrive_sync() { bash "$PWD/scripts/template-autosync.sh" "$@"; }\n' > "$R/scripts/lib/impostor.sh"
OUT=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and names it as a way out"                 "$OUT" "a way out of this gate"
has  "…by its nested path"                        "$OUT" "scripts/lib/impostor.sh"

echo "== AC-56 (H7bo AC-42): the scanner's own failure is reported, never swallowed =="
# The gate reads files with awk inside a command substitution. A broken awk program writes to
# stderr, emits no lines, and every file reads clean — a status shaped like success for a check
# that never ran. Met for real during this row via a half-applied edit. So break the program in a
# copy of the gate and require exit 2, against a fixture that holds a real violation: a clean
# verdict here would be the scanner failing silently.
R=$(fixture brokenscanner)
printf '#!/bin/bash\nbash "$PWD/scripts/template-autosync.sh" --force\n' > "$R/scripts/test-driver.sh"
sed 's/^function bare(w) {/function bare(w {/' "$GATE" > "$TMP/gate-broken.sh"
if cmp -s "$GATE" "$TMP/gate-broken.sh"; then
  bad "the sabotage changed nothing, so this case proves nothing"
else
  GOUT=$(SANDBOX_GATE_ROOT="$R" bash "$TMP/gate-broken.sh" 2>&1); GRC=$?
  same "a broken scanner exits 2, not 0 and not 1"  "$GRC" "2"
  has  "…saying it cannot answer"                   "$GOUT" "cannot answer"
fi

echo "== AC-57 (H7bo AC-37): the census — no driver spells the declaration by hand =="
# 's full claim is "the six suites are green with unchanged assertion counts before and
# after", which one run cannot check: "before" is a different tree. What IS checkable, and is the
# durable half, is the state that claim was about — every driver reaches the sync through the
# helper and none re-spells the contract. Measured before this row: 17 hand-spelled
# CLAUDE_TEMPLATE_SYNC_SANDBOX= assignments across these six files, under four wrapper names.
HANDSPELLED=0
for d in test-core-owed-tick-guard test-sync-count-honesty test-template-autosync-eol \
         test-template-autosync-owed test-template-autosync-stranded test-template-autosync-unlisted; do
  _f="$PWD/scripts/$d.sh"
  case "$(grep -c 'drive-sync.sh' "$_f")" in
    0) bad "  $d does not source the helper" ;;
    *) ok  "  $d sources the helper" ;;
  esac
  # Whole-line comments do not count; a file explaining the rule is not breaking it.
  _n=$(grep -vE '^[[:space:]]*#' "$_f" | grep -c 'CLAUDE_TEMPLATE_SYNC_SANDBOX=')
  HANDSPELLED=$((HANDSPELLED + _n))
done
# One survives, and it is not a sync invocation: test-template-autosync-eol.sh drives the HOOK,
# which is a different program that runs the sync itself. The declaration there is what keeps that
# nested run inside its sandbox, and routing a hook through a sync helper would be the helper
# growing a second job. So the honest figure is 17 -> 1, not 17 -> 0, and the 1 is named.
same "the six drivers hold exactly one hand-spelled declaration (the hook call)" "$HANDSPELLED" "1"
_eol=$(grep -vE '^[[:space:]]*#' "$PWD/scripts/test-template-autosync-eol.sh" | grep 'CLAUDE_TEMPLATE_SYNC_SANDBOX=')
has  "…and it is the hook invocation, not a sync invocation" "$_eol" "CLAUDE_TEMPLATE_AUTOSYNC_ALWAYS=1"

echo "== AC-58 (H7bo AC-36): the six real drivers, one falsification arm each =="
# Six arms, not one: an arm per file proves the rule bites in every file rather than in whichever
# one the single arm happened to pick. Each takes the REAL driver, swaps its drive_sync call back
# for a hand-spelled invocation, and requires the gate to name THAT file.
for d in test-core-owed-tick-guard test-sync-count-honesty test-template-autosync-eol \
         test-template-autosync-owed test-template-autosync-stranded test-template-autosync-unlisted; do
  R=$(fixture "arm-$d")
  # Replace the FIRST drive_sync call with the shape it had before spec 011. awk, not sed: BSD sed
  # rejects the `0,/re/` address and silently changes nothing, and an arm that changes nothing
  # reports green — which is exactly how a falsification arm becomes decoration. Caught here
  # because the arm's own failure message distinguishes "gate stayed green" from "gate named
  # something else", so a no-op sabotage could not read as a pass.
  awk 'BEGIN { done = 0 }
       /drive_sync / && !done {
         # The LITERAL path, not a $SYNC handle: four of these six files hold the sync in $SCRIPT
         # instead, so a handle-shaped sabotage would be invisible in exactly those four — and an
         # invisible sabotage reports the arm green.
         print "  ( cd \"$_p\" && CLAUDE_PROJECT_DIR=\"$_p\" CLAUDE_TEMPLATE_SYNC_SANDBOX=\"$TMP\" bash scripts/template-autosync.sh \"$@\" )"
         done = 1; next }
       { print }' "$PWD/scripts/$d.sh" > "$R/scripts/$d.sh"
  if cmp -s "$PWD/scripts/$d.sh" "$R/scripts/$d.sh"; then
    bad "  arm: $d — the sabotage changed nothing, so the arm proves nothing"
    continue
  fi
  OUT=$(gate "$R"); RC=$?
  if [ "$RC" -eq 1 ]; then
    case "$OUT" in
      *"scripts/$d.sh:"*) ok "  arm: $d reverted → the gate names $d" ;;
      *) bad "  arm: $d reverted → the gate failed, but named something else" ;;
    esac
  else
    bad "  arm: $d reverted → the gate stayed green; the rule does not bite in this file"
  fi
done

echo "== the interlock itself: template-autosync.sh's CLAUDE_TEMPLATE_SYNC_SANDBOX =="
# The gate above makes callers declare. This section checks that declaring achieves anything —
# they are two halves of one mechanism and neither is worth much alone. Every case below runs the
# REAL sync, inside a sandbox it declares.
ILOCK="$TMP/ilock"; mkdir -p "$ILOCK"
# The template every interlock case syncs against. Local, so nothing resolves a remote.
FT="$ILOCK/template"; mkdir -p "$FT/scripts" "$FT/.claude/rules"
cp "$SYNC" "$FT/scripts/"; echo prompt > "$FT/scripts/sync-prompt.md"
printf 'rule v1\n' > "$FT/.claude/rules/demo-rule.md"
mkrepo() {  # mkrepo <dir>
  mkdir -p "$1/.claude" "$1/scripts"; cp "$SYNC" "$1/scripts/"; echo '{}' > "$1/package.json"
  git -C "$1" init -q -b main
  git -C "$1" config user.email a@a; git -C "$1" config user.name A
  git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm init >/dev/null 2>&1
}
SBX="$ILOCK/sandbox"; mkdir -p "$SBX"
IN="$SBX/proj"; OUT_REPO="$ILOCK/outside"; mkrepo "$IN"; mkrepo "$OUT_REPO"
# HAND-SPELLED ON PURPOSE, and this is the sharpest reason this file is one of the gate's four
# argued exclusions. The section below tests the SYNC'S OWN INTERLOCK, and half its cases pass
# deliberately invalid declarations — `/`, the empty string, a path that does not exist — to prove
# the sync refuses them. drive_sync validates exactly those arguments and refuses first, with exit
# 64, so routing this through the helper does not test the interlock: it MASKS it. Five assertions
# turned red the moment it was converted, all of them reporting 64 where they expected the sync's
# own verdict, which is the good outcome — a silent version of this would have left the interlock
# untested behind a green suite.
#
# The helper guards CALLERS. This function is not a caller; it is the interlock's test rig, and a
# test rig for a lock has to be able to try the wrong keys. Specs 010, 011.
run_sync() {  # run_sync <sandbox> <project> [args...]
  _s="$1"; _p="$2"; shift 2
  ( cd "$_p" && CLAUDE_PROJECT_DIR="$_p" CLAUDE_TEMPLATE_SYNC_SANDBOX="$_s" \
      CLAUDE_TEMPLATE_DIR="$FT" bash scripts/template-autosync.sh "$@" 2>&1 )
}
rc_sync() { run_sync "$@" >/dev/null 2>&1; }
# The undeclared path — no sandbox variable at all, which is what every production run does. Two
# cases need it, and neither can go through drive_sync, which ALWAYS declares — the same reason as
# run_sync above. It is the fixture for AC-23, "an undeclared run is byte-identical to before
# spec 010". Delete the exclusion in validate-sync-sandbox-declarations.sh and these lines are what the
# gate reports (AC-60).
sync_undeclared() {  # sync_undeclared <project> [args...]
  _p="$1"; shift
  ( cd "$_p" && CLAUDE_PROJECT_DIR="$_p" CLAUDE_TEMPLATE_DIR="$FT" \
      bash scripts/template-autosync.sh "$@" 2>&1 )
}

echo "-- AC-13: a root inside the declared sandbox is allowed through"
rc_sync "$SBX" "$IN" --check; same "exits 0"      "$?" "0"

echo "-- AC-14: a root OUTSIDE it refuses, before writing, naming both paths"
BEFORE_FILES=$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')
BEFORE_LOG=$(git -C "$OUT_REPO" log --oneline | wc -l | tr -d ' ')
O=$(run_sync "$SBX" "$OUT_REPO"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "says nothing was written"                   "$O" "Nothing was written"
has  "names the declared sandbox"                 "$O" "declared sandbox:"
has  "names the resolved project"                 "$O" "resolved project:"
same "the outside repo gained no dirty file"      "$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')" "$BEFORE_FILES"
same "…and no commit"                             "$(git -C "$OUT_REPO" log --oneline | wc -l | tr -d ' ')" "$BEFORE_LOG"
[ -f "$OUT_REPO/.claude/.template-sync" ] && bad "…and no stamp was written" || ok "…and no stamp was written"

echo "-- AC-15: it refuses under --quiet too"
# A refusal nobody sees is the warning that went unread on 2026-08-30.
O=$(run_sync "$SBX" "$OUT_REPO" --quiet)
has  "--quiet does not silence the refusal"       "$O" "[refused]"

echo "-- AC-16: a declaration that is SET BUT EMPTY refuses (spec 010 — consultpilot read it as undeclared)"
# An empty prefix contains every path, so it can never mean "/". It cannot mean "undeclared" either:
# a driver writing CLAUDE_TEMPLATE_SYNC_SANDBOX="$TMP" whose mktemp failed would pass the gate and run
# with no interlock. Refusing is the only reading that fails in the safe direction.
BEFORE_FILES=$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')
O=$(run_sync "" "$OUT_REPO" --force --no-commit); RC=$?
same "set-but-empty exits 1"                      "$RC" "1"
has  "…and says it is empty"                      "$O" "set but empty"
same "…and nothing was written"                   "$(git -C "$OUT_REPO" status --porcelain | wc -l | tr -d ' ')" "$BEFORE_FILES"

echo "-- AC-17: a declaration naming nothing is a refusal, not a pass"
O=$(run_sync "$ILOCK/does-not-exist" "$IN" --check); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and says which declaration"                "$O" "names no existing directory"

echo "-- AC-18: a declaration that is a FILE, not a directory"
printf 'x\n' > "$ILOCK/a-file"
rc_sync "$ILOCK/a-file" "$IN" --check; same "exits 1"  "$?" "1"

echo "-- AC-19: segments, not characters — /sandbox-evil is not inside /sandbox"
EVIL="$ILOCK/sandbox-evil"; mkdir -p "$EVIL"; mkrepo "$EVIL/proj"
rc_sync "$SBX" "$EVIL/proj" --check
same "the sibling with a shared prefix is refused" "$?" "1"

echo "-- AC-20: physical paths — macOS /var vs /private/var"
# mktemp -d hands out /var/folders/…; `pwd -P` reports /private/var/folders/…. A string comparison
# refuses every legitimate sandbox run on this platform, which is the difference between a guard
# and an obstacle.
MT=$(mktemp -d); mkrepo "$MT/proj"
rc_sync "$MT" "$MT/proj" --check
same "a symlinked sandbox path is accepted"       "$?" "0"
DECL_PHYS=$(cd "$MT" && pwd -P)
if [ "$MT" != "$DECL_PHYS" ]; then
  ok "…and the two spellings really did differ ($MT vs $DECL_PHYS)"
else
  ok "…(this platform does not symlink TMPDIR; the case is a no-op here)"
fi
rm -rf "$MT"

echo "-- AC-21: trailing slashes and .. segments in the declaration"
rc_sync "$SBX/" "$IN" --check;               same "trailing slash accepted"    "$?" "0"
rc_sync "$SBX/proj/.." "$IN" --check;        same "a .. segment resolves"      "$?" "0"

echo "-- AC-22: a path with a space and a non-ASCII name"
ODD="$ILOCK/en katalog med ÅÄÖ"; mkdir -p "$ODD"; mkrepo "$ODD/proj"
rc_sync "$ODD" "$ODD/proj" --check;          same "spaces and diacritics survive" "$?" "0"
rc_sync "$SBX" "$ODD/proj" --check;          same "…and are still refused when outside" "$?" "1"

echo "-- AC-23: the undeclared run is untouched (FR-006)"
# The load-bearing non-event. Every production run of this script takes this path.
A=$(sync_undeclared "$IN" --check)
B=$(run_sync "$SBX" "$IN" --check)
same "declared and undeclared produce identical output" "$A" "$B"
hasnt "…and the undeclared run says nothing new" "$A" "[refused]"

echo "-- AC-24: --is-core costs nothing extra with a declaration set (FR-013b, behavioural)"
sync_undeclared "$IN" --is-core scripts/x.sh >/dev/null 2>&1; C1=$?
rc_sync "$SBX" "$IN" --is-core scripts/x.sh; C2=$?
same "--is-core answers the same either way"      "$C1" "$C2"

echo "-- AC-25: outside a git repository the quiet skip stays quiet"
# FR-008. The interlock must not turn an existing silent exit 0 into a hard failure: the
# SessionStart hook runs this script in whatever directory a session opens in, and most of them are
# not projects.
NOGIT="$ILOCK/not-a-repo"; mkdir -p "$NOGIT"
O=$( cd "$NOGIT" && CLAUDE_PROJECT_DIR="$NOGIT" CLAUDE_TEMPLATE_SYNC_SANDBOX="$ILOCK" \
       CLAUDE_TEMPLATE_DIR="$FT" bash "$SYNC" --check 2>&1 ); RC=$?
same "still exits 0"                              "$RC" "0"
has  "…with the pre-existing message"             "$O" "not inside a git repository"
hasnt "…and not a refusal"                        "$O" "[refused]"

echo "== the adversarial review's findings, as permanent tests =="
# Every case below reproduced against the first implementation of this row and is now a regression
# test. They are grouped so it stays obvious that they came from a review pass, not from design:
# the design missed them, and the only reason they are not still there is that something adversarial
# looked.

echo "-- AC-26: a sandbox declared as / is refused"
# The single line that, alone, reopened the 2026-08-30 incident. `_within` had an explicit `/`
# branch written as a formatting concern ("never build //"), and nothing had asked what declaring
# the root MEANT: every path is inside it, so the interlock accepted and the run proceeded to
# write, commit and push. AC-16 covered the EMPTY declaration and read as though it covered this.
O=$(run_sync / "$OUT_REPO" --check); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and says why the root is not a sandbox"    "$O" "declares nothing and protects nothing"

echo "-- AC-31: an ambient CDPATH cannot steer the check away from the write (adversarial review, 010)"
# A relative project name plus CDPATH pointing into the sandbox: before the fix `cd` followed CDPATH,
# printed the decoy, and the check passed while the walk wrote to the real relative directory.
# Physical paths on purpose: on macOS the unfixed cd echoes the /var spelling while the sandbox
# resolves to /private/var, and that mismatch refused by accident — the arm passed against the bug.
CD_T="$(cd "$ILOCK" && pwd -P)/cdpath"; mkdir -p "$CD_T/sbx/proj" "$CD_T/real"; mkrepo "$CD_T/real/proj"
mkdir -p "$CD_T/sbx/proj/.git"
O=$( cd "$CD_T/real" && CDPATH="$CD_T/sbx" CLAUDE_PROJECT_DIR=proj CLAUDE_TEMPLATE_SYNC_SANDBOX="$CD_T/sbx" \
       CLAUDE_TEMPLATE_DIR="$FT" bash "$SYNC" --force --no-commit 2>&1 ); RC=$?
same "exits 1 — the real relative project is outside the sandbox" "$RC" "1"
same "…and the real project is untouched" "$(git -C "$CD_T/real/proj" status --porcelain | wc -l | tr -d ' ')" "0"

echo "-- AC-32: an inherited GIT_DIR cannot redirect a declared run's commit (adversarial review, 010)"
# Git exports GIT_DIR / GIT_INDEX_FILE to its hooks and both beat `git -C`. The root check passes
# (the project IS in the sandbox); only the unset makes the commit land there.
GD_T="$ILOCK/gitdir"; mkdir -p "$GD_T"; mkrepo "$GD_T/victim"; mkrepo "$SBX/gd-proj"
V_HEAD=$(git -C "$GD_T/victim" rev-parse HEAD)
GIT_DIR="$GD_T/victim/.git" GIT_INDEX_FILE="$GD_T/victim/.git/index" rc_sync "$SBX" "$SBX/gd-proj" --force
same "the victim repository's HEAD did not move"  "$(git -C "$GD_T/victim" rev-parse HEAD)" "$V_HEAD"
same "…and its tree is clean"                     "$(git -C "$GD_T/victim" status --porcelain | wc -l | tr -d ' ')" "0"
[ -f "$SBX/gd-proj/.claude/.template-sync" ] && ok "…and the sync landed in the sandboxed project" \
                                             || bad "the sandboxed project got no stamp"

echo "-- AC-27: a driver that declares / is still refused, by its SUCCESSOR"
# spec 010's gate read declarations and had a branch for `/`, because presence of the assignment was
# all it checked — a driver could be certified compliant by the very tool built to prevent the
# bypass it was performing. spec 011's gate reads no declarations at all, so the branch is gone and
# the capability moved into drive_sync's argument validation, where it is one check against a
# VALUE rather than a pattern against a line. The successor lives in test-drive-sync.sh AC-15.
#
# What is asserted here is that the move is real and not a deletion: the same driver is still
# refused, now for the prior reason that it does not go through the helper at all — and the
# helper it would have to go through is the thing that refuses `/`.
R=$(fixture rootdecl)
cat > "$R/scripts/test-rootdecl.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
run() { ( cd "$1" && CLAUDE_PROJECT_DIR="$1" CLAUDE_TEMPLATE_SYNC_SANDBOX=/ bash "$SYNC" --force ); }
EOS
O=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…naming the line"                           "$O" "scripts/test-rootdecl.sh:3"
# And the successor itself, run here so this file cannot go green while the capability is gone.
( . "$PWD/scripts/drive-sync.sh"; drive_sync "$TMP" / >/dev/null 2>&1 )
same "the helper refuses / (the capability's new home)" "$?" "64"

echo "-- AC-28: direct execution is an invocation, with or without an interpreter"
# template-autosync.sh carries a #! line, so `exec "$SYNC"` runs it. The first detector required a
# literal bash/sh token and was blind to this: the file was not reported as a driver, nor as
# exempt — simply absent, which is the worst of the three.
R=$(fixture execform)
cat > "$R/scripts/test-execform.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
( cd /some/other/repo && exec "$SYNC" --force )
EOS
O=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and names the file and line"               "$O" "scripts/test-execform.sh:3"

echo "-- AC-29: a backtick is a command-word anchor too"
R=$(fixture backtick)
cat > "$R/scripts/test-backtick.sh" <<'EOS'
#!/bin/bash
SYNC="$PWD/scripts/template-autosync.sh"
OUT=`bash "$SYNC" --force`
EOS
O=$(gate "$R"); RC=$?
same "exits 1"                                    "$RC" "1"
has  "…and names the file and line"               "$O" "scripts/test-backtick.sh:3"

echo "-- AC-30: prose is still not an invocation"
# The two false positives the tightened detector had to shed, kept as fixtures so a future
# broadening of the anchors reintroduces them loudly. Both are real lines from this repository.
R=$(fixture prose)
cat > "$R/scripts/test-prose.sh" <<'EOS'
#!/bin/bash
MSG="STACK MARKER MISSING.

template-autosync.sh reads that marker to decide which testing docs to install."
echo "  (scripts/template-autosync.sh), is shared verbatim with every project that syncs it"
EOS
O=$(gate "$R"); RC=$?
same "exits 0"                                    "$RC" "0"
hasnt "a message string is not a driver"          "$O" "test-prose.sh"

echo "== AC-59: F014 — the shapes spec 010's gate could not see =="
# Recorded against spec 010's heuristic matcher by its adversarial review (finding F014), and the
# reason this row replaced a line regex with a lexer rather than adding more regexes. Every line
# below runs the sync; each must be named.
R=$(fixture f014)
cat > "$R/scripts/test-f014.sh" <<'EOS'
#!/bin/bash
S="$PWD/scripts/template-autosync.sh"
/bin/bash "$S" --absolute-interpreter
zsh "$S" --zsh
timeout 5 bash "$S" --timeout-wrapper
env X=1 bash "$S" --env-wrapper
nohup "$S" --nohup-direct
f() {
  local L="$PWD/scripts/template-autosync.sh"
  bash "$L" --local-handle
}
bash "$S" --force   # --is-core
out="$(bash "$S" --inside-a-quoted-substitution)"
[ -x "$S" ] && "$S" --direct-after-and
bash "$S" --is-core x.sh; bash "$S" --sync-after-a-query
bash -c "bash $PWD/scripts/template-autosync.sh --bash-dash-c"
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                          "$RC" "1"
has  "/bin/bash is an interpreter"                      "$OUT" "test-f014.sh:3"
has  "so is zsh"                                        "$OUT" "test-f014.sh:4"
has  "a timeout wrapper does not hide it"               "$OUT" "test-f014.sh:5"
has  "nor an env wrapper"                               "$OUT" "test-f014.sh:6"
has  "nohup with the path as the command"               "$OUT" "test-f014.sh:7"
has  "a local handle is a handle"                       "$OUT" "test-f014.sh:10"
has  "a trailing '# --is-core' comment exempts nothing" "$OUT" "test-f014.sh:12"
has  "bash inside \"\$(…)\" is code, not text"           "$OUT" "test-f014.sh:13"
has  "a bare path after && is a command"                "$OUT" "test-f014.sh:14"
has  "a query before ; does not excuse a sync after it" "$OUT" "test-f014.sh:15"
has  "bash -c's string is code"                         "$OUT" "test-f014.sh:16"
has  "…and all eleven are counted"                      "$OUT" "11 violation(s)"

echo "== AC-59b: nothing a lexer can trip on swallows the line after it =="
# The dangerous direction: a lexing mistake does not produce a wrong answer, it produces NO answer
# for the rest of the file, with exit 0. Each trap below is followed by a real run that must be found.
R=$(fixture traps)
cat > "$R/scripts/test-traps.sh" <<'EOS'
#!/bin/bash
S="$PWD/scripts/template-autosync.sh"
# a comment line ending in a backslash \
bash "$S" --after-comment-backslash
echo "use <<EOF inside a string"
bash "$S" --after-a-quoted-heredoc-operator
x=$(cat <<EOF
body with an "unbalanced quote
EOF
)
bash "$S" --after-a-heredoc-inside-a-substitution
echo 'it'"'"'s' && bash "$S" --after-mixed-quotes
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                          "$RC" "1"
has  "a comment's trailing backslash joins nothing"     "$OUT" "test-traps.sh:4"
has  "a << inside a string opens no heredoc"            "$OUT" "test-traps.sh:6"
has  "a heredoc body inside \$( is skipped, not lexed"  "$OUT" "test-traps.sh:11"
has  "adjacent quoting styles close where they close"   "$OUT" "test-traps.sh:12"
has  "…and exactly four are counted"                    "$OUT" "4 violation(s)"

echo "== AC-59c: what is not a run stays not a run =="
R=$(fixture notruns)
cat > "$R/scripts/test-notruns.sh" <<'EOS'
#!/bin/bash
S="$PWD/scripts/template-autosync.sh"
cat > "$d/scripts/template-autosync.sh" <<'X'
bash "$S" --inside-a-heredoc-body
X
printf 'x\n' > "$d/scripts/template-autosync.sh"
L=( scripts/template-autosync.sh scripts/other.sh )
M=(
  scripts/template-autosync.sh
)
cp "$S" "$T/scripts/template-autosync.sh"
git show "HEAD:scripts/template-autosync.sh" > /dev/null
T2=$( [ -f scripts/template-autosync.sh ] && echo yes )
bash "$T2/scripts/install.sh"
bash "$T2" --a-mention-is-not-a-handle
bash "$S" --list-core-scripts | wc -l
EOS
OUT=$(gate "$R"); RC=$?
same "exits 0 — heredoc body, redirection, array, copy, git path, mention-only handle" "$RC" "0"
hasnt "…and the file is not reported"                   "$OUT" "test-notruns.sh:"
has   "…and its query-mode run is counted as exempt"    "$OUT" "1 exempt (query modes only)"

echo "== AC-60: the argued list is exactly four, and every entry is load-bearing =="
# A cap nobody measures is a quota. Four is the developer's number for the template (2026-09-29).
# Then each entry is falsified the way the gate's header says a reviewer should: delete it, re-run
# against this repository, and the gate must name that file. An entry whose removal changes nothing
# is a grandfather line and fails here.
N=$(sed -n '/^EXCLUDED="$/,/^"$/p' "$GATE" | grep -c '|')
same "the exclusion list holds exactly 4 entries" "$N" "4"
# One run with all four entries removed proves the same thing as four: the entries are independent
# per-file keys, so each file either appears in that run's report or its entry held nothing up.
EXS=$(sed -n '/^EXCLUDED="$/,/^"$/p' "$GATE" | grep '|' | cut -d'|' -f1)
grep -v '^scripts/[^|]*|' "$GATE" > "$TMP/gate-minus.sh"
OUT=$(SANDBOX_GATE_ROOT="$PWD" bash "$TMP/gate-minus.sh" 2>&1); RC=$?
same "without its list, the gate fails on this repository" "$RC" "1"
for ex in $EXS; do
  case "$OUT" in
    *"$ex:"*) ok "  without its entry, $ex is reported" ;;
    *) bad "  without its entry, $ex is NOT reported — the entry holds nothing up" ;;
  esac
done

echo "== AC-61: a file the lexer cannot finish is 'cannot answer', never clean =="
# An unclosed quote swallows everything after it. Reading that as "no runs found" would be a status
# shaped like success for a scan that stopped; the gate exits 2 and names the file instead.
R=$(fixture unfinished)
printf '#!/bin/bash\nS="$PWD/scripts/template-autosync.sh"\necho "never closed\nbash "$S" --force\n' > "$R/scripts/test-unfinished.sh"
OUT=$(gate "$R"); RC=$?
same "exits 2"                                          "$RC" "2"
has  "…saying it cannot answer"                         "$OUT" "cannot answer"
has  "…and naming the file"                             "$OUT" "scripts/test-unfinished.sh"
echo "== AC-62: the adversarial review of spec 011 — every bypass it traced, as a fixture =="
# The first version of the lexer passed 161 assertions and every one of these. Each shape below
# exited 0 against it; each is traced to the lexer rule that now catches it.
R=$(fixture review011)
cat > "$R/scripts/test-review.sh" <<'EOS'
#!/bin/bash
bash "$(dirname "$0")/template-autosync.sh" --glued-after-a-substitution
"$(git rev-parse --show-toplevel)/scripts/template-autosync.sh" --glued-direct
m=$(( 1 << 3 ))
bash "$PWD/scripts/template-autosync.sh" --after-an-arithmetic-shift
NAME=template-autosync.sh
bash "$PWD/scripts/$NAME" --handle-inside-a-word
S="$PWD/scripts/template-autosync.sh"
bash "${S:?}" --handle-with-an-expansion-operator
T=$PWD/scripts/template-autosync.sh; bash "$T" --assigned-before-a-semicolon
f() {
  local -r L=$PWD/scripts/template-autosync.sh
  bash "$L" --local-with-an-option
}
for F in "$D"/scripts/template-autosync.sh; do bash "$F" --loop-variable; done
RP=$(realpath scripts/template-autosync.sh)
bash "$RP" --assigned-from-a-substitution
CMD=(bash "$PWD/scripts/template-autosync.sh" --force)
"${CMD[@]}"
bash -o pipefail "$S" --interpreter-option-with-an-argument
exec -a name "$S" --exec-with-a-name
env -u FOO "$S" --env-unset
timeout -s KILL 5 "$S" --timeout-signal
setsid "$S" --setsid
busybox ash "$S" --busybox
bash "$S" --force > --is-core
x=$(:)# ; bash "$PWD/scripts/template-autosync.sh" --hash-inside-a-word
H="$(cd "$(dirname "$0")" && pwd)/template-autosync.sh"
bash "$H" --handle-from-a-glued-substitution
echo "see $(pwd)/template-autosync.sh"
EOS
OUT=$(gate "$R"); RC=$?
same "exits 1"                                                  "$RC" "1"
has  "a glued tail after \$(…) is part of the word"              "$OUT" "test-review.sh:2 "
has  "…also when the path is the command"                       "$OUT" "test-review.sh:3 "
has  "\$(( 1 << 3 )) is a shift, not a heredoc"                  "$OUT" "test-review.sh:5 "
has  "a handle inside a longer word"                            "$OUT" "test-review.sh:7 "
has  "\${S:?} is still \$S"                                      "$OUT" "test-review.sh:9 "
has  "an assignment followed by ; is still a handle"            "$OUT" "test-review.sh:10 "
has  "local -r is still a handle"                               "$OUT" "test-review.sh:13 "
has  "a for-loop variable over the sync is a handle"            "$OUT" "test-review.sh:15 "
has  "a value assigned from \$(realpath …) is a handle"          "$OUT" "test-review.sh:17 "
has  "an array holding the command runs it"                     "$OUT" "test-review.sh:19 "
has  "bash -o pipefail"                                         "$OUT" "test-review.sh:20 "
has  "exec -a"                                                  "$OUT" "test-review.sh:21 "
has  "env -u"                                                   "$OUT" "test-review.sh:22 "
has  "timeout -s"                                               "$OUT" "test-review.sh:23 "
has  "setsid"                                                   "$OUT" "test-review.sh:24 "
has  "busybox ash"                                              "$OUT" "test-review.sh:25 "
has  "a redirection's file is not a query mode"                 "$OUT" "test-review.sh:26 "
has  "# right after ) is not a comment"                         "$OUT" "test-review.sh:27 "
has  "a handle assigned through a glued \$(…) is a handle"      "$OUT" "test-review.sh:29 "
hasnt "…but a glued \$(…) inside echo's string is not a run"     "$OUT" "test-review.sh:30 "
has  "…and exactly nineteen are counted"                        "$OUT" "19 violation(s)"

R=$(fixture review011b)
printf '#!/bin/bash\ncat <<NEVER\nbash "$PWD/scripts/template-autosync.sh" --force\n' > "$R/scripts/test-open-heredoc.sh"
OUT=$(gate "$R"); RC=$?
same "a heredoc that never closes is 'cannot answer', not clean" "$RC" "2"
has  "…naming where it opened"                                  "$OUT" "test-open-heredoc.sh:2"

R=$(fixture review011c)
printf '#!/bin/bash\nbash "$PWD/scripts/template-autosync.sh" --force\n' > "$R/scripts/rogue-no-extension"
OUT=$(gate "$R"); RC=$?
same "an extensionless shell script is opened"                  "$RC" "1"
has  "…and named"                                               "$OUT" "scripts/rogue-no-extension:2"

R=$(fixture review011d)
printf '#!/bin/bash\n. scripts/drive-sync.sh\n_drive_sync_check_sandbox() { :; }\n_drive_sync_own_repo=""\nDRIVE_SYNC_EBADARG=0\n' > "$R/scripts/test-tamper.sh"
OUT=$(gate "$R"); RC=$?
same "redefining or reassigning the helper's internals exits 1" "$RC" "1"
has  "…as a way out of the gate"                                "$OUT" "a way out of this gate"
has  "…naming the file"                                         "$OUT" "scripts/test-tamper.sh"

R=$(fixture review011d2)
printf '#!/bin/bash\n. scripts/drive-sync.sh\n_drive_sync_own_repo=""\n' > "$R/scripts/test-tamper-assign.sh"
OUT=$(gate "$R"); RC=$?
same "ASSIGNING an internal alone is caught too, not only redefining one" "$RC" "1"
has  "…naming the file"                                         "$OUT" "scripts/test-tamper-assign.sh"

R=$(fixture review011e)
printf 'bash "$_drive_sync_dir/template-autosync.sh" --force\n' >> "$R/scripts/drive-sync.sh"
OUT=$(gate "$R"); RC=$?
same "a run at the helper's TOP level is not exempt"            "$RC" "1"
has  "…and is named"                                            "$OUT" "scripts/drive-sync.sh:"

R=$(fixture review011f)
printf '#!/bin/bash\nS="$PWD/scripts/template-autosync.sh"\ncommand -v "$S" >/dev/null\n' > "$R/scripts/test-command-v.sh"
OUT=$(gate "$R"); RC=$?
same "command -v asks where the file is; it runs nothing"       "$RC" "0"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
