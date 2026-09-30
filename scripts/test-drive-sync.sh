#!/bin/bash
# Harness for scripts/drive-sync.sh (spec 011, landed from consultpilot H7bo).
#
# The helper is the single path from every self-test to template-autosync.sh. That concentration is
# deliberate and it is an improvement — before it the same defect could sit in one of 19 sites and
# fail ONE assertion silently, which is the shape the 2026-08-30 incident had. Concentrated failure is
# loud. But the price of concentration is that a defect here fails everything, so the helper gets
# the sabotage arms no individual call site ever had.
#
# THE ARMS ARE THE POINT. A gate nobody has watched fail is a report, not a gate (spec 007bs). Each
# arm below breaks ONE validation branch in a copy of the helper and requires the check to redden.
# The count is reported as a number, because on a bash file there is no Stryker to run and "we have
# tests" is not a measurement.
#
# Offline. Every run drives a stub script, never the real sync — this file is about the helper's
# argument handling, and a harness for a sandbox helper must not be the thing that escapes one.
#
# Scenario ids deliberately absent: this file is CORE and ships into projects whose SC numbering is
# their own (row 012). AC labels match consultpilot's H7bo harness for cross-reference.
#
# Run: bash scripts/test-drive-sync.sh

set -u
cd "$(dirname "$0")/.." || exit 1
HELPER="$PWD/scripts/drive-sync.sh"
[ -f "$HELPER" ] || { echo "FAIL: drive-sync.sh not found at $HELPER"; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
same() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')"; printf '       got: %s\n' "$(printf '%s' "$2" | cut -c1-160)" ;; esac; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; SBX="$TMP/sbx"; mkdir -p "$P" "$SBX"

# Stubs. The helper's contract is about environment and arguments, so the "sync" only has to report
# what it was handed.
STUB="$TMP/stub.sh"
cat > "$STUB" <<'EOS'
#!/bin/bash
printf 'PROJ=%s SBX=%s TPL=%s CWD=%s ARGS=' \
  "${CLAUDE_PROJECT_DIR:-none}" "${CLAUDE_TEMPLATE_SYNC_SANDBOX:-none}" \
  "${CLAUDE_TEMPLATE_DIR:-none}" "$PWD"
for a in "$@"; do printf '<%s>' "$a"; done
echo
exit "${STUB_EXIT:-0}"
EOS
SLOW="$TMP/slow.sh"; printf '#!/bin/bash\nsleep 9\n' > "$SLOW"
chmod +x "$STUB" "$SLOW"

# Sourced at TOP LEVEL, not only inside the per-assertion subshells, so this harness reads the
# helper's own constant instead of a second copy of the number. It was a literal `EBADARG=64` here
# before: every `. "$HELPER"` below happens inside a subshell, so the top level never saw
# DRIVE_SYNC_EBADARG, and changing the helper to `1` left every refusal assertion passing — the
# harness comparing its own 64 against its own 64, across precisely the boundary it exists to check.
. "$HELPER"
EBADARG="${DRIVE_SYNC_EBADARG:?drive-sync.sh did not define DRIVE_SYNC_EBADARG}"

# ================================================================= A. the happy path

echo "=== A. drive_sync sets both halves, forwards everything, returns the sync's code ==="
( . "$HELPER"
  OUT=$(DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" --force "two words" 2>&1)
  printf '%s\n' "$OUT" ) > "$TMP/a.out"
A=$(cat "$TMP/a.out")
has "AC-01 names the target project"     "$A" "PROJ=$P"
has "AC-02 declares the sandbox"         "$A" "SBX=$SBX"
has "AC-03 forwards argv verbatim"       "$A" "<--force><two words>"
has "AC-04 cwd defaults to the project"            "$A" "CWD=$P"

( . "$HELPER"; STUB_EXIT=7 DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1 )
same "AC-05 the sync's exit code passes through" "$?" "7"

( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1 )
same "AC-06 a clean run exits 0" "$?" "0"

# ================================================================= B. the caller's shell survives

echo
echo "=== B. the helper leaks nothing — the failure mode centralisation could introduce ==="
# A leak would poison the NEXT assertion in the calling file rather than crash it, which is quieter
# than failing and is why this is asserted directly rather than assumed from the subshell.
#
# BEFORE-AND-AFTER, not "is it unset". The first version asserted the variables were unset
# afterwards, which passed standalone and FAILED under consultpilot's run-gates.sh — because the gate runner runs
# with CLAUDE_PROJECT_DIR already exported, so the assertion was reading the ambient value and
# calling it a leak. That is the spec 010 lesson landing on this row's own test: an inherited
# CLAUDE_PROJECT_DIR makes an assertion answer about something other than what it names. It is also
# the more dangerous direction than the false alarm it gave here — had the ambient value happened to
# match what the helper sets, a real leak would have read as clean.
#
# `${VAR-x}` and not `${VAR:-x}`: the first distinguishes unset from empty, and "the helper set it
# to the empty string" is a leak too.
LEAK=$( . "$HELPER"
  P0="${CLAUDE_PROJECT_DIR-<unset>}"; S0="${CLAUDE_TEMPLATE_SYNC_SANDBOX-<unset>}"; C0=$PWD
  DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1
  DRIVE_SYNC_SCRIPT="$STUB" drive_sync_readonly "$P" --is-core x.sh >/dev/null 2>&1
  DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" / >/dev/null 2>&1          # the refusal path too
  printf 'proj=%s sbx=%s cwd=%s\n' \
    "$([ "${CLAUDE_PROJECT_DIR-<unset>}" = "$P0" ] && echo same || echo CHANGED)" \
    "$([ "${CLAUDE_TEMPLATE_SYNC_SANDBOX-<unset>}" = "$S0" ] && echo same || echo CHANGED)" \
    "$([ "$PWD" = "$C0" ] && echo same || echo MOVED)" )
same "AC-07 nothing leaks after three calls" "$LEAK" "proj=same sbx=same cwd=same"

# The arm for the arm. AC-07 passed standalone and failed under consultpilot's run-gates.sh, because the runner
# exports CLAUDE_PROJECT_DIR and the assertion was reading the ambient value. Run it again with a
# hostile ambient environment — the one the 2026-08-30 incident happened in — so the class cannot
# come back the next time someone rewrites this check.
LEAK2=$( export CLAUDE_PROJECT_DIR=/ambient/decoy CLAUDE_TEMPLATE_SYNC_SANDBOX=/ambient/sbx
  . "$HELPER"
  P0="${CLAUDE_PROJECT_DIR-<unset>}"; S0="${CLAUDE_TEMPLATE_SYNC_SANDBOX-<unset>}"
  DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1
  printf '%s/%s' \
    "$([ "${CLAUDE_PROJECT_DIR-<unset>}" = "$P0" ] && echo same || echo CHANGED)" \
    "$([ "${CLAUDE_TEMPLATE_SYNC_SANDBOX-<unset>}" = "$S0" ] && echo same || echo CHANGED)" )
same "AC-07b nothing leaks under an inherited environment either" "$LEAK2" "same/same"

# ================================================================= C. optional mechanisms

echo
echo "=== C. one mechanism per optional behaviour, not one per caller ==="
C=$( . "$HELPER"; CLAUDE_TEMPLATE_DIR=marker DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" 2>&1 )
has "AC-08 extra env rides a prefix assignment" "$C" "TPL=marker"
# The measured half of AC-08: bash exports a function-call prefix to the child and leaves nothing
# in the caller. The whole design rests on that, so it is asserted rather than cited.
C2=$( . "$HELPER"; CLAUDE_TEMPLATE_DIR=marker DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1
      printf '%s' "${CLAUDE_TEMPLATE_DIR:-unset}" )
same "AC-09 …and does not survive into the caller" "$C2" "unset"

mkdir -p "$TMP/elsewhere"
C3=$( . "$HELPER"; DRIVE_SYNC_CWD="$TMP/elsewhere" DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" 2>&1 )
has "AC-10 DRIVE_SYNC_CWD moves the run, not the target" "$C3" "CWD=$TMP/elsewhere"
has "AC-11 …and the target is still the project"         "$C3" "PROJ=$P"

if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  ( . "$HELPER"; DRIVE_SYNC_TIMEOUT=1 DRIVE_SYNC_SCRIPT="$SLOW" drive_sync "$P" "$SBX" >/dev/null 2>&1 )
  same "AC-12 DRIVE_SYNC_TIMEOUT bounds the run" "$?" "124"
else
  ok "AC-12 skipped — no timeout binary on this machine"
fi

# A bound that was asked for and silently not applied is the no-silent-misses rule broken by
# convenience: the source would read bounded and the run would be unbounded.
T13=$( . "$HELPER"; PATH=/nonexistent DRIVE_SYNC_TIMEOUT=1 DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" 2>&1 )
same "AC-13 no timeout binary refuses, does not run unbounded" "$?" "$EBADARG"
has  "AC-13b …and says so"                                     "$T13" "refusing rather than running unbounded"

# ================================================================= D. refusals

echo
echo "=== D. every argument is checked before anything starts ==="
refuses() {  # refuses <label> <expected-substring> <cmd…>
  _l="$1"; _sub="$2"; shift 2
  _o=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" "$@" 2>&1 ); _rc=$?
  if [ "$_rc" -ne "$EBADARG" ]; then bad "$_l (expected rc=$EBADARG, got $_rc)"; return; fi
  case "$_o" in *"$_sub"*) ok "$_l" ;; *) bad "$_l (message did not say why: $_o)" ;; esac
}
refuses "AC-14 empty sandbox"        "no declaration at all"      drive_sync "$P" ""
refuses "AC-15 sandbox is /"         "constrains nothing"         drive_sync "$P" "/"
refuses "AC-16 relative sandbox"     "is relative"                drive_sync "$P" "sbx"
refuses "AC-17 sandbox missing"      "does not exist"             drive_sync "$P" "$TMP/nope"
refuses "AC-18 sandbox is a file"    "not a directory"            drive_sync "$P" "$STUB"
refuses "AC-19 project missing"                "does not exist"             drive_sync "$TMP/nope" "$SBX"
refuses "AC-20 project is a file"              "not a directory"            drive_sync "$STUB" "$SBX"
refuses "AC-21 project empty"                  "project is empty"           drive_sync "" "$SBX"
refuses "AC-22 too few arguments"              "usage: drive_sync"          drive_sync "$P"

R23=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="$TMP/not-here.sh" drive_sync "$P" "$SBX" 2>&1 ); RC23=$?
same "AC-23 missing sync script refuses"  "$RC23" "$EBADARG"
has  "AC-23b …naming the path"            "$R23"  "sync script not found"

R24=$( . "$HELPER"; DRIVE_SYNC_CWD="$TMP/nope" DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" 2>&1 ); RC24=$?
same "AC-24 unusable DRIVE_SYNC_CWD refuses" "$RC24" "$EBADARG"
has  "AC-24b …with a specific message"       "$R24"  "cannot cd to"

# The refusal must not be readable as a verdict.
echo
echo "=== E. a refusal cannot be mistaken for a verdict ==="
same "AC-25 the refusal code is not the sync's 0/1/2" \
     "$( [ "$EBADARG" -ne 0 ] && [ "$EBADARG" -ne 1 ] && [ "$EBADARG" -ne 2 ] && echo distinct )" "distinct"
# Nothing may have started. If the stub ran, it left a line on stdout; a refusal must leave none.
E=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "/" 2>/dev/null )
same "AC-26 a refused call starts nothing" "$E" ""

# ================================================================= F. the write-free entry point

echo
echo "=== F. the write-free entry point is checked, not trusted ==="
F=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync_readonly "$P" --is-core scripts/x.sh 2>&1 )
has "AC-27 --is-core runs with no sandbox" "$F" "SBX=none"
has "AC-28 …and still names the project"             "$F" "PROJ=$P"
# The template's sync has four modes that return above the project-root resolution, not one.
# consultpilot's helper accepted --is-core only, so a --list-core-scripts caller there had to
# hand-spell or pass a fake sandbox. Each mode is its own assertion: a helper that knew three of
# the four would pass any single probe.
for _m in --list-core-scripts --list-core-rules --template-dir; do
  F2=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync_readonly "$P" "$_m" 2>&1 )
  has "AC-28b $_m runs with no sandbox too" "$F2" "SBX=none"
done

refuses "AC-29 readonly without a query mode" "none is in these arguments" \
        drive_sync_readonly "$P" --force
refuses "AC-30 readonly with no arguments at all" "none is in these arguments" \
        drive_sync_readonly "$P"
refuses "AC-31 readonly still validates the project" "does not exist" \
        drive_sync_readonly "$TMP/nope" --is-core x.sh

# The arm that matters most, and it used to be an unconditional `ok` citing AC-14 — a comment
# wearing an assertion's clothes, in the file that opens by saying a gate nobody has watched fail is
# a report. It is a real check now: an empty-sandbox sentinel would have been the smaller change and
# the larger hole, so what must hold is that NO argument value makes the writing entry point run
# without a sandbox. Probe every shape a sentinel could take.
S32=ok
for _s in "" " " "." ".." "-" "/" "0"; do
  _o=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$_s" --force 2>/dev/null )
  [ -n "$_o" ] && S32="a sandbox of '$_s' started a run: $_o"
done
same "AC-32 no sandbox value opens a door on drive_sync" "$S32" "ok"

echo
echo "=== H. a sandbox that contains this repository is not a sandbox ==="
# `/` was already refused as the extreme case. This is the same argument carried to every other
# ancestor: $HOME, /Users, the repo's own parent all satisfy "absolute, exists, is a directory"
# while permitting writes to the very repository the interlock exists to protect. Found by the
# adversarial review, which pointed out that "a sandbox was declared" and "the run is confined" are
# different properties and only the first was being checked.
OWNREPO=$(cd "$PWD" && pwd -P)
refuses "AC-33 the repo itself as sandbox"   "contains this repository" drive_sync "$P" "$OWNREPO"
refuses "AC-34 the repo's parent as sandbox" "contains this repository" drive_sync "$P" "$(cd .. && pwd -P)"
refuses "AC-35 \$HOME as sandbox"            "contains this repository" drive_sync "$P" "$HOME"
# …and the ordinary case is untouched, or the check would be a blanket refusal wearing a reason.
( . "$HELPER"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1 )
same "AC-36 a real throwaway sandbox still runs" "$?" "0"

echo
echo "=== I. DRIVE_SYNC_SCRIPT is required, because every caller sets it ==="
# Measured across consultpilot's six converted suites: 19 of 19 call sites set it, so the default did no work
# while giving the one universal parameter the property this helper removes from the other two.
# Forgetting it would have quietly run the REPO's sync where a fixture, era or sabotaged copy was
# meant — the sandbox still holds, so nothing breaks and the test measures the wrong binary.
I1=$( . "$HELPER"; unset DRIVE_SYNC_SCRIPT; drive_sync "$P" "$SBX" 2>&1 ); IRC=$?
same "AC-37 an unset script refuses"        "$IRC" "$EBADARG"
has  "AC-37b …naming the variable"          "$I1"  "DRIVE_SYNC_SCRIPT is not set"
has  "AC-37c …and saying there is no default" "$I1" "no default"
I2=$( . "$HELPER"; unset DRIVE_SYNC_SCRIPT; drive_sync_readonly "$P" --is-core x.sh 2>&1 ); IRC2=$?
same "AC-38 the write-free entry point too" "$IRC2" "$EBADARG"

echo
echo "=== J. the adversarial review of spec 011 — the helper's own holes ==="
# Each of these went ahead, or returned a verdict-shaped code, against the first version.
J1=$( . "$HELPER"; DRIVE_SYNC_EBADARG=0; DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" / 2>/dev/null ); JRC=$?
same "AC-39 reassigning DRIVE_SYNC_EBADARG does not turn a refusal into a pass" "$JRC" "64"
same "AC-39b …and nothing ran"                                   "$J1" ""
refuses "AC-40 a relative DRIVE_SYNC_SCRIPT is refused"          "sync script is relative" \
        env DRIVE_SYNC_SCRIPT=scripts/stub.sh bash -c '. "$0"; drive_sync "$1" "$2"' "$HELPER" "$P" "$SBX"
for _t in --version 0 abc 5s -1; do
  _o=$( . "$HELPER"; DRIVE_SYNC_TIMEOUT="$_t" DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" 2>&1 ); _rc=$?
  same "AC-41 DRIVE_SYNC_TIMEOUT=$_t is refused, not obeyed" "$_rc" "$EBADARG"
done
# A copy whose own repository resolves to `/`, built by editing text rather than by assigning the
# helper's internals from here: the gate refuses any file but the helper that assigns them.
ROOTED="$TMP/rooted.sh"
sed 's|^_drive_sync_own_repo=\$(.*|_drive_sync_own_repo=/|' "$HELPER" > "$ROOTED"
cmp -s "$HELPER" "$ROOTED" && bad "AC-42 setup — the rooted copy is identical to the helper, so the probe proves nothing"
J4=$( . "$ROOTED"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" 2>&1 ); JRC=$?
same "AC-42 an unresolvable own repository fails closed"         "$JRC" "64"
has  "AC-42b …and says why"                                      "$J4" "cannot resolve the repository"

# ================================================================= G. sabotage arms
#
# Each arm breaks ONE branch in a COPY of the helper and requires this file's own check to redden.
# An arm that stays green means the assertion above it is decorative.

echo
echo "=== G. sabotage — break one branch at a time, require red ==="
ARMS=0; ARMS_RED=0
# WHAT AN ARM ACTUALLY PROVES, corrected after the first draft got it wrong.
#
# The first version asked "with this check removed, does the call still get refused?" and five of
# ten arms stayed green — not because those checks are dead, but because the checks are LAYERED.
# Delete "sandbox is empty" and the empty string falls through to the relative-path branch; delete
# "does not exist" and the is-a-directory test catches it. Defence in depth is the right shape for
# the code and the wrong shape for that probe, which could only ever have measured the outermost
# check of each chain.
#
# So an arm asks the question that matters instead: with this check removed, is the caller still
# told THE SPECIFIC THING THAT IS WRONG? A refusal that survives but whose diagnosis degrades to a
# neighbouring check's message is a real loss — a caller who passed a relative path and is told
# "does not exist" will go looking in the wrong place. An arm is red when the rc changes OR the
# specific message disappears. It is only green — i.e. a failure of this harness — when removing
# the line changes nothing observable at all, which is what "dead check" means.
# ARM_SCRIPT overrides which "sync" the probe points at, for the one arm whose subject IS the
# script check and which therefore needs a path that is not there.
arm() {  # arm <label> <sed-expression> <expected-substring> <probe…>   [ARM_SCRIPT=… as a prefix]
  _l="$1"; _sed="$2"; _sub="$3"; shift 3
  ARMS=$((ARMS + 1))
  cp "$HELPER" "$TMP/sabotaged.sh"
  sed -i.bak "$_sed" "$TMP/sabotaged.sh" 2>/dev/null || { bad "G:$_l (sed failed)"; return; }
  if cmp -s "$HELPER" "$TMP/sabotaged.sh"; then
    bad "G:$_l — the sabotage changed nothing, so the arm proves nothing"
    return
  fi
  # Sanity: the intact helper must give this diagnosis, or the arm is testing a message nobody emits.
  _base=$( . "$HELPER"; DRIVE_SYNC_SCRIPT="${ARM_SCRIPT:-$STUB}" "$@" 2>&1 )
  case "$_base" in
    *"$_sub"*) : ;;
    *) bad "G:$_l — the INTACT helper never says '$_sub', so this arm asserts nothing"; return ;;
  esac
  _out=$( . "$TMP/sabotaged.sh"; DRIVE_SYNC_SCRIPT="${ARM_SCRIPT:-$STUB}" "$@" 2>&1 ); _rc=$?
  case "$_out" in
    *"$_sub"*)
      if [ "$_rc" -eq "$EBADARG" ]; then
        bad "G:$_l — removing the line changed neither the code nor the message; it is dead"
      else
        ARMS_RED=$((ARMS_RED + 1)); ok "G:$_l — removing it stops the refusal"
      fi ;;
    *)
      ARMS_RED=$((ARMS_RED + 1))
      if [ "$_rc" -eq "$EBADARG" ]; then
        ok "G:$_l — removing it costs the specific diagnosis (a neighbour still refuses)"
      else
        ok "G:$_l — removing it lets the call through entirely"
      fi ;;
  esac
}
arm "empty sandbox"     '/sandbox is empty/s/\[ -n "\$1" \]/[ -n "${1:-x}" ]/'  "no declaration at all" drive_sync "$P" ""
arm "root sandbox"      '/constrains nothing/d'                          "constrains nothing"    drive_sync "$P" "/"
arm "relative sandbox"  '/sandbox is relative/d'                         "is relative"           drive_sync "$P" "sbx"
arm "sandbox missing"   '/a caller naming a sandbox that is not there/d' "sandbox does not exist" drive_sync "$P" "$TMP/nope"
arm "sandbox not a dir" '/sandbox is not a directory/d'                  "sandbox is not a directory" drive_sync "$P" "$STUB"
arm "project missing"   '/project does not exist/d'                      "project does not exist" drive_sync "$TMP/nope" "$SBX"
arm "project not a dir" '/project is not a directory/d'                  "project is not a directory" drive_sync "$STUB" "$SBX"
ARM_SCRIPT="$TMP/not-here.sh" \
arm "script missing"    '/sync script not found/d'                       "sync script not found" drive_sync "$P" "$SBX"
arm "readonly gate"     '/is for the query modes only/d'                       "none is in these arguments" drive_sync_readonly "$P" --force
# Not armed in consultpilot: the contains-this-repository refusal (added after its arms were written)
# and the template's widened mode list. Deleting the refusal line leaves an empty, valid `case`.
arm "contains repo"     '/contains this repository/d'                    "contains this repository" drive_sync "$P" "$HOME"
# Spec 011's review added three checks; each gets an arm, or it is a claim.
ARM_SCRIPT=scripts/stub.sh \
arm "relative script"   '/sync script is relative/d'                     "sync script is relative" drive_sync "$P" "$SBX"
DRIVE_SYNC_TIMEOUT=abc \
arm "timeout value"     '/is not a whole number of seconds/d'            "not a whole number of seconds" drive_sync "$P" "$SBX"
HELPER="$ROOTED" \
arm "fail closed"       '/cannot resolve the repository this helper/d'   "cannot resolve the repository" drive_sync "$P" "$SBX"

# The mode-list arm is shaped differently too: dropping a mode causes a refusal where AC-28b expects
# a run, so it is checked by running the probe AC-28b runs and requiring it to stop answering.
ARMS=$((ARMS + 1))
sed 's/|--template-dir)/)/' "$HELPER" > "$TMP/fewer-modes.sh"
if cmp -s "$HELPER" "$TMP/fewer-modes.sh"; then
  bad "G:mode list — the sabotage changed nothing, so the arm proves nothing"
else
  FM=$( . "$TMP/fewer-modes.sh"; DRIVE_SYNC_SCRIPT="$STUB" drive_sync_readonly "$P" --template-dir 2>&1 )
  case "$FM" in
    *"SBX=none"*) bad "G:mode list — a helper without --template-dir still ran it, so AC-28b is not what catches it" ;;
    *) ARMS_RED=$((ARMS_RED + 1)); ok "G:mode list — dropping --template-dir makes the read-only probe refuse, so AC-28b bites" ;;
  esac
fi

# The leak arm is shaped differently: removing the subshell does not cause a refusal, it causes a
# leak, so it is checked by looking at the caller afterwards rather than at an exit code.
ARMS=$((ARMS + 1))
sed 's/^  ($/  {/; s/^  )$/  }/' "$HELPER" > "$TMP/leaky.sh"
if cmp -s "$HELPER" "$TMP/leaky.sh"; then
  bad "G:subshell — the sabotage changed nothing, so the arm proves nothing"
else
  # Same before/after shape as AC-07, and for the same reason: under a gate runner the ambient
  # CLAUDE_PROJECT_DIR is already set, so "is it unset afterwards" would report this arm red
  # whether or not removing the subshell changed anything.
  LK=$( . "$TMP/leaky.sh"; P0="${CLAUDE_PROJECT_DIR-<unset>}"
        DRIVE_SYNC_SCRIPT="$STUB" drive_sync "$P" "$SBX" >/dev/null 2>&1
        [ "${CLAUDE_PROJECT_DIR-<unset>}" = "$P0" ] && printf 'same' || printf 'CHANGED' )
  if [ "$LK" = "same" ]; then
    bad "G:subshell — removing it leaked nothing, so AC-07 is not what catches a leak"
  else
    ARMS_RED=$((ARMS_RED + 1)); ok "G:subshell — removing it leaks CLAUDE_PROJECT_DIR, so AC-07 bites"
  fi
fi

printf '\n%s\n' "----------------------------------------"
printf 'sabotage arms: %s of %s red (the mutation gate stand-in for bash)\n' "$ARMS_RED" "$ARMS"
printf 'pass: %s   fail: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
[ "$ARMS_RED" -eq "$ARMS" ] || { echo "an arm stayed green — a check that cannot fail is not a check"; exit 1; }
exit 0
