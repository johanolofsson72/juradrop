#!/usr/bin/env bash
# Self-test for scripts/validate-register-ids.sh and the id grammar it gates (row H7b).
#
# WHY THIS EXISTS. A gate whose failing arm has never been observed is not known to work — spec 007f's
# rule, and this row is the proof of it: the id grammar was wrong for 18 days while every artifact around
# it was green, because nothing ever ran the comparison. Shipping the comparison without an executable
# check ON the comparison would be the same mistake wearing a shell script.
#
# WHAT IT PINS
#   * the three-state exit contract — 0 clean, 1 malformed id, 2 the register could not be read — and
#     specifically that 2 is DISTINCT from 1. "exit != 0" would conflate "this register is bad" with
#     "I could not look", which is the exact conflation that cost this row 56 register rows.
#   * that the grammar accepts the house convention, INCLUDING H6s2 (letters-digits-letter-digit). The
#     first fix attempt for this row was `[a-z]?`, which fells H6s2 — the same defect one carve later.
#   * that H6s2 comes back WHOLE. "H6s" is another real register row, so a truncating match would resolve
#     to a different spec. Same property 007ab pinned on the numeric side.
#   * that kind comes from the TRACK FIELD, not the id shape — a letter-led id on a `full`/`spec-only`
#     track is a spec that owes its artifacts, not an exempt checkpoint. 14 of 19 rows were exempt on the
#     strength of a letter before this row.
#   * that a register with zero rows is not a pass.
#   * that narrowing the grammar back to ANY shape it has already shipped turns the real gate red —
#     all three of them (pre-007m, pre-007ab, pre-H7b), because the grammar has been too narrow three
#     times and each fix was made without falsifying the one before it (row 007br).
#
# Scenario map: SC-1428, SC-1429, SC-1430, SC-1443, SC-1445 (specs/SCENARIOS.md, row H7b).
#
# Exit: 0 all expectations met · 1 an expectation failed · 2 the harness itself broke, OR a precondition
#       could not be met — SC-1683. There are TWO such preconditions and they are the same fact: no
#       register at all, and a register whose ids exercise none of the historical narrowings. Neither
#       is a pass, and neither is evidence against the gate — reporting the second as a FAIL is the
#       defect row 007br was opened for.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/validate-register-ids.sh"
[ -f "$GATE" ] || { echo "HARNESS ERROR: gate not found: $GATE" >&2; exit 2; }

WORK=$(mktemp -d 2>/dev/null) || { echo "HARNESS ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ok    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

check_rc() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then ok "$label (rc=$actual)"; else bad "$label — expected rc=$expected, got rc=$actual"; fi
}

check_says() {
  local label="$1" needle="$2" text="$3"
  case "$text" in *"$needle"*) ok "$label (names \"$needle\")" ;; *) bad "$label — output never names \"$needle\"" ;; esac
}

make_register() {
  local name="$1"; shift
  local f="$WORK/$name.md"
  { echo "# Spec register"; echo; echo "## Specs"; echo; printf '%s\n' "$@"; } > "$f"
  printf '%s' "$f"
}

echo "== the grammar itself (unit level) =="
GRAMMAR=$(HOOK_DIR="$ROOT/scripts" python3 <<'PY' 2>&1
import os, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from spec_active import classify_id, _kind_for
cases = [
    # token,        expected ident, expected shape
    ("007",         "007",   "numeric"),
    ("007m",        "007m",  "numeric"),
    ("007ab",       "007ab", "numeric"),
    ("**364",       "364",   "numeric"),
    ("H1",          "H1",    "alpha"),
    ("H6a",         "H6a",   "alpha"),
    ("H6s2",        "H6s2",  "alpha"),      # letters-digits-letter-digit: the case `[a-z]?` would miss
    ("**H7b**",     "H7b",   "alpha"),
    ("F2b",         "F2b",   "alpha"),
    ("7-x",         "7-x",   "malformed"),  # a character outside [A-Za-z0-9]
    ("H",           "H",     "malformed"),  # letters, no digit
    ("checkpoint",  "checkpoint", "malformed"),
]
bad = 0
for token, want_id, want_shape in cases:
    got_id, got_shape = classify_id(token)
    if (got_id, got_shape) != (want_id, want_shape):
        print("SHAPE-MISMATCH %r -> %r/%s, wanted %r/%s" % (token, got_id, got_shape, want_id, want_shape))
        bad += 1

# H6s2 must never come back as H6s — that is a different real register row.
ident, _ = classify_id("H6s2")
if ident != "H6s2":
    print("TRUNCATION H6s2 -> %r" % ident); bad += 1

# kind comes from the TRACK FIELD.
kind_cases = [
    ("alpha", "checkpoint",           "checkpoint"),
    ("alpha", "full track",           "spec"),
    ("alpha", "spec-only",            "spec"),
    ("alpha", "full track [hardened]", "spec"),
    ("numeric", "checkpoint",         "checkpoint"),
    ("numeric", "light track",        "spec"),
    ("malformed", "checkpoint",       "unparseable"),   # no id => no exemption, whatever the track says
    ("malformed", "full track",       "unparseable"),
]
for shape, track, want in kind_cases:
    got = _kind_for(shape, track)
    if got != want:
        print("KIND-MISMATCH %s + %r -> %s, wanted %s" % (shape, track, got, want)); bad += 1
print("GRAMMAR-OK" if bad == 0 else "GRAMMAR-BAD %d" % bad)
PY
)
case "$GRAMMAR" in
  *GRAMMAR-OK*) ok "id grammar + kind derivation (20 cases)" ;;
  *) bad "id grammar / kind derivation:"; printf '%s\n' "$GRAMMAR" | sed 's/^/        /' ;;
esac

echo "== the gate, green arm =="
REG=$(make_register clean \
  '- [x] 007 — preview — full track — done' \
  '- [x] 007ab — later-suffix — full track — done' \
  '- [x] H1 — integration-hardening — checkpoint — regression sweep' \
  '- [/] H6s2 — carved-from-a-carve — spec-only — in progress' \
  '- [ ] H7b — next — spec-only — later')
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc  "clean register" 0 "$RC"
check_says "clean register reports the histogram" "unparseable: 0" "$OUT"
check_says "clean register counts the ONE checkpoint-track row" "checkpoint: 1" "$OUT"
check_says "clean register counts duplicate ids" "duplicate ids: 0" "$OUT"
# A bare register file in $WORK has no specs/ tree beside it, so the directory half legitimately reads
# nothing. Asserted rather than left implicit: "0 matched" is a fact about this fixture, and a reader
# who finds it in a real run is looking at a gate pointed somewhere wrong.
check_says "a bare register file matches no directories" "spec dirs matched: 0" "$OUT"

echo "== the gate, red arm (this is the arm that had never been observed) =="
REG=$(make_register broken \
  '- [x] 007 — preview — full track — done' \
  '- [/] 7-x — malformed-id — spec-only — in progress' \
  '- [ ] H — no-digit — full track — later')
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc   "malformed ids" 1 "$RC"
check_says "names the first offender"  "7-x" "$OUT"
check_says "names the second offender" "'H'" "$OUT"
check_says "names the line number"     ":6"  "$OUT"
check_says "points at the grammar"     "spec_active.py" "$OUT"

echo "== the gate, cannot-look arm (must NOT share an exit code with the red arm) =="
OUT=$(REGISTER="$WORK/does-not-exist.md" bash "$GATE" 2>&1); RC=$?
check_rc "missing register" 2 "$RC"

REG=$(make_register norows)   # header only, zero rows
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc   "register with zero rows is not a pass" 2 "$RC"
check_says "and says so"     "ZERO register rows" "$OUT"

echo "== uniqueness: an id names one row, and one directory (row 007ch) =="
# WHY THIS IS NOT TIDINESS. Both BLOCKING PreToolUse guards resolve the active row's id, glob
# specs/<id>-*, and check what they find. So when the ticked row of a colliding pair owns a complete
# artifact set, the ACTIVE row inherits it: 007ch research.md M4 measured both guards ALLOWING a
# source edit for a spec with zero artifacts and zero interview answers, against a control in which
# the same guards on the same fixture DENIED it. That is verbatim the bypass spec_active.py's own
# docstring describes for a mis-parsed id, reached with no parser bug at all.
#
# Which row you get is not even "the first one": resolve() sorts the glob and takes the first isdir
# hit, so the answer is decided by the alphabet of the SLUG (M3). The directory half is therefore the
# half with consequences, and it is checked separately from the row half.
#
# THREE ARMS, and the third is the one that matters most. A check that never executes passes both red
# arms' absence forever, so the green arm asserts the gate's own COUNTS rather than its silence — and
# the counts include how many directories the glob actually matched, because a scan that read nothing
# is otherwise indistinguishable from a clean one (the lesson row 007cd wrote a per-root file floor for).

REG=$(make_register dup-rows \
  '- [x] 007ca — first — spec-only track — done' \
  '- [x] 007cc — alpha-first — spec-only track — done, and it owns the directory' \
  '- [ ] 007cc — zulu-second — spec-only track — active, and it owns nothing')
OUT=$(REGISTER="$REG" bash "$GATE" 2>&1); RC=$?
check_rc   "one id on two rows" 1 "$RC"
check_says "names the duplicated id"      "007cc" "$OUT"
check_says "names the earlier row's line" ":6"    "$OUT"
check_says "names the later row's line"   ":7"    "$OUT"
check_says "says what a duplicate costs"  "approve a source edit" "$OUT"

# The directory half needs a TREE, not a bare file: the gate globs specs/<id>-* from the register's
# own tree root, which is what lets REGISTER= point the WHOLE check at a fixture rather than half of it.
DUPTREE="$WORK/duptree"
mkdir -p "$DUPTREE/specs/007cc-alpha" "$DUPTREE/specs/007cc-zulu"
{ echo "# Spec register"; echo; echo "## Specs"; echo
  echo '- [/] 007cc — one-row-two-dirs — spec-only track — the register is fine; the tree is not'
} > "$DUPTREE/specs/INDEX.md"
OUT=$(REGISTER="$DUPTREE/specs/INDEX.md" bash "$GATE" 2>&1); RC=$?
check_rc   "one id, two directories" 1 "$RC"
check_says "names the first directory"      "007cc-alpha" "$OUT"
check_says "names the second directory"     "007cc-zulu"  "$OUT"
# The glob found something. Without this the arm above could pass on a gate whose root is wrong in
# some OTHER way that still yields two hits, and the green arms below could pass on one that finds
# nothing at all, forever.
check_says "counts the directories it read" "spec dirs matched: 2" "$OUT"

# The quiet control. A clean tree, one directory per id, and the counts say the check RAN.
CLEANTREE="$WORK/cleantree"
mkdir -p "$CLEANTREE/specs/007cc-only-one" "$CLEANTREE/specs/H1-integration-hardening"
{ echo "# Spec register"; echo; echo "## Specs"; echo
  echo '- [x] 007cc — only-one — spec-only track — one row, one directory'
  echo '- [ ] H1 — integration-hardening — checkpoint — one row, one directory'
} > "$CLEANTREE/specs/INDEX.md"
OUT=$(REGISTER="$CLEANTREE/specs/INDEX.md" bash "$GATE" 2>&1); RC=$?
check_rc   "clean tree" 0 "$RC"
check_says "clean tree reports zero duplicate ids"  "duplicate ids: 0"  "$OUT"
check_says "clean tree reports zero ambiguous dirs" "ambiguous dirs: 0" "$OUT"
check_says "clean tree read both directories"       "spec dirs matched: 2" "$OUT"

echo "== SC-1445: the directory is resolved for every well-formed id, not only for kind==spec =="
DIRCHECK=$(HOOK_DIR="$ROOT/scripts" WORKDIR="$WORK" python3 <<'DIRPY' 2>&1
import os, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from spec_active import resolve

work = os.environ["WORKDIR"]
root = os.path.join(work, "dircheck")
os.makedirs(os.path.join(root, "specs", "H1-integration-hardening"), exist_ok=True)
with open(os.path.join(root, "specs", "INDEX.md"), "w", encoding="utf-8") as fh:
    fh.write("# Spec register\n\n## Specs\n\n")
    fh.write("- [/] H1 - integration-hardening - checkpoint - full-system regression\n".replace(" - ", " — "))

info = resolve(root)
bad = 0
# The exemption still holds...
if info["kind"] != "checkpoint":
    print("KIND %r, wanted checkpoint" % info["kind"]); bad += 1
# ...and the directory is resolved anyway, so .specify/feature.json and
# check-prerequisites.sh can answer for this row. Before H7b the glob ran only
# under `if kind == "spec"`, which is why check-prerequisites.sh failed outright
# on H7b itself.
if info["dir"] != os.path.join("specs", "H1-integration-hardening"):
    print("DIR %r, wanted specs/H1-integration-hardening" % info["dir"]); bad += 1
if not info["found"]:
    print("FOUND false for a directory that exists"); bad += 1
if info["slug"] != "integration-hardening":
    print("SLUG %r" % info["slug"]); bad += 1
# A malformed id has no usable glob and must stay empty rather than guess.
root2 = os.path.join(work, "dircheck2")
os.makedirs(os.path.join(root2, "specs"), exist_ok=True)
with open(os.path.join(root2, "specs", "INDEX.md"), "w", encoding="utf-8") as fh:
    fh.write("# Spec register\n\n## Specs\n\n- [/] 7-x - broken - spec-only - x\n".replace(" - ", " — "))
info2 = resolve(root2)
if info2["kind"] != "unparseable" or info2["dir"] is not None:
    print("MALFORMED %r / %r" % (info2["kind"], info2["dir"])); bad += 1
print("DIR-OK" if bad == 0 else "DIR-BAD %d" % bad)
DIRPY
)
case "$DIRCHECK" in
  *DIR-OK*) ok "a checkpoint-track row resolves its directory, a malformed id resolves nothing" ;;
  *) bad "directory resolution:"; printf '%s\n' "$DIRCHECK" | sed 's/^/        /' ;;
esac


echo "== falsification: a narrowed grammar must turn this gate red =="
# The point of the whole row. If narrowing the grammar back to a shape it has already shipped leaves
# this gate green, the gate is decorative.
#
# THREE narrowings, not one — the grammar has been too narrow THREE times, and each fix was made
# without ever falsifying the one before it (row 007br):
#
#   pre-007m   NUMERIC ^[0-9]+$            never knew a letter suffix   (004a, 007a..007o went dark)
#   pre-007ab  NUMERIC ^[0-9]+[a-z]?$      never knew a SECOND letter   (007aa onward went dark)
#   pre-H7b    ALPHA   ^[A-Za-z]+[0-9]+$   never knew H6a, never H6s2   (69 of 114 rows went dark)
#
# The arm this replaces tested only the third, and on a register whose alpha ids are H1 and H2 — both
# of which the narrowed alpha grammar still accepts — it fells 0 rows and concluded "this gate cannot
# detect the defect it was built for". A false accusation against a healthy gate, and the whole
# self-test exited 1 on it. The numeric column, which fells 80 rows and 53 rows on the same register,
# was never looked at. Label each entry with the spec it re-creates: a FOURTH widening added without
# a fourth entry here is then visible to a reader, not only to a counter.
#
# TWO PRECONDITIONS, and both are the THIRD state rather than a failure (rows H7t, 007br):
#
#   * no register at all — a synthetic one would only re-prove SC-1430, asserted above;
#   * a register whose ids exercise no historical narrowing — it can tell you nothing about the
#     gate, and saying "the gate is broken" on that evidence is the exact wrong-diagnosis failure
#     the H7b row spent 18 days inside.
#
# Neither is PASS and neither is FAIL: both are "I cannot tell you", which this harness's own header
# already promises is a distinct fact (exit 2).
#
# WHAT MAKES IT NOT DECORATIVE, beyond the extra rows: each entry runs the REAL GATE end to end
# against the REAL REGISTER. `validate-register-ids.sh` pins HOOK_DIR to its own directory, so the
# narrowing reaches it by copying both files into a temp dir and rebinding the regex in the COPY —
# after which what exits 1 is the shipped gate, not an assertion about classify_id() made by this
# harness. The count comes from the gate's own `unparseable: N` histogram line for the same reason:
# a number this script computed itself would be a second opinion about the thing under test.
PRECOND_UNMET=0
PRECOND_WHY=""
if [ ! -f "$ROOT/specs/INDEX.md" ]; then
  echo "  ----  no register at $ROOT/specs/INDEX.md — the falsification needs real rows, so it did not run"
  PRECOND_UNMET=1
  PRECOND_WHY="no register in this repo"
else

# label | module attribute | narrowed pattern | canary the CURRENT grammar accepts and this one must not
NARROWINGS='pre-007m|NUMERIC_ID_RE|^\**\s*([0-9]+)\**\s*$|007m
pre-007ab|NUMERIC_ID_RE|^\**\s*([0-9]+[a-z]?)\**\s*$|007ab
pre-H7b|ALPHA_ID_RE|^\**\s*([A-Za-z]+[0-9]+)\**\s*$|H6s2'

# BASELINE FIRST, and it is not ceremony. "Narrowing turns the gate red" is a claim about a CHANGE,
# and a change needs a starting point: if the shipped grammar is ALREADY red on this register, every
# narrowing fells rows and this arm reports itself live on breakage it did not cause. Measured while
# building row 007br — sabotaging spec_active.py to `[a-z]?` made all three entries "pass", including
# the ALPHA one, which had felled nothing a moment earlier. Attribution, not decoration: with no green
# baseline the honest answer is that this arm cannot tell you anything, and it says so.
BOUT=$(REGISTER="$ROOT/specs/INDEX.md" bash "$GATE" 2>&1); BRC=$?
if [ "$BRC" -ne 0 ]; then
  bad "the gate is already rc=$BRC on the real register — with no green baseline a narrowing's effect
        cannot be attributed to the narrowing. Fix the grammar or the register first; this arm is
        deliberately silent rather than confidently wrong."
  # `| head -3` is an early-exit consumer: head leaves after three lines, grep -v keeps writing into a
  # reader-less pipe and takes SIGPIPE (row H7x). Harmless here — the status is discarded — but the shape
  # is the one scripts/validate-no-sigpipe-assertions.sh refuses, and it cannot tell a diagnostic from an
  # assertion on a line that stands alone after a multi-line `bad`, so it says UNDECIDED rather than
  # guessing. `sed -n '1,3p'` reads to EOF and orphans nobody: same three lines, no early exit.
  grep -v '^[[:space:]]*$' <<< "$BOUT" | sed -n '1,3s/^/        /p'
  NARROWINGS=""
fi

LIVE=0
LIVE_DESC=""
APPLIED_DESC=""
while IFS='|' read -r LABEL ATTR PATTERN CANARY; do
  [ -n "$LABEL" ] || continue
  NDIR="$WORK/narrow-$LABEL"
  mkdir -p "$NDIR" || { bad "$LABEL: could not create $NDIR"; continue; }
  cp "$ROOT/scripts/spec_active.py" "$ROOT/scripts/validate-register-ids.sh" "$NDIR/" 2>/dev/null \
    || { bad "$LABEL: could not copy the gate and its grammar into $NDIR"; continue; }

  # Appended, not sed'd into the regex literal. classify_id() resolves these as module globals at
  # call time, so a rebinding after the definition takes effect — and an append either lands whole
  # or not at all, where an in-place rewrite of a regex literal can half-match and look like a
  # no-op that the row below would then have to guess about.
  {
    echo ""
    echo "# --- narrowed to the $LABEL shape by scripts/test-register-ids.sh ---"
    echo "${ATTR} = re.compile(r\"${PATTERN}\")"
  } >> "$NDIR/spec_active.py"

  # CANARY FIRST. A narrowing that did not apply proves nothing, and its zero would otherwise be
  # indistinguishable from "this register has no rows of that shape" — which is this row's own bug,
  # one level down. So it is a harness FAILURE, never an inconclusive.
  CANARY_SHAPE=$(HOOK_DIR="$NDIR" CANARY="$CANARY" python3 - <<'PY' 2>&1
import os, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from spec_active import classify_id
print(classify_id(os.environ["CANARY"])[1])
PY
)
  if [ "$CANARY_SHAPE" != "malformed" ]; then
    bad "$LABEL: the narrowing did not apply — canary '$CANARY' still classifies as '$CANARY_SHAPE'"
    continue
  fi

  GOUT=$(REGISTER="$ROOT/specs/INDEX.md" bash "$NDIR/validate-register-ids.sh" 2>&1); GRC=$?
  # The gate prints its histogram on EVERY run, pass or fail. Its number, not ours.
  GN=$(printf '%s\n' "$GOUT" | sed -n 's/.*unparseable: \([0-9]*\).*/\1/p' | head -1)
  [ -n "$GN" ] || GN=-1

  APPLIED_DESC="$APPLIED_DESC $LABEL"
  if [ "$GRC" -eq 1 ] && [ "$GN" -gt 0 ]; then
    LIVE=$((LIVE + 1))
    LIVE_DESC="$LIVE_DESC $LABEL($GN)"
    ok "$LABEL: the shipped gate goes red on the real register — $GN row(s) unparseable"
  elif [ "$GRC" -eq 0 ] && [ "$GN" -eq 0 ]; then
    echo "  ----  $LABEL: narrowing applied (canary '$CANARY' fell) but this register holds no id of that"
    echo "        shape, so it fells nothing. Inconclusive for this narrowing — not a pass, not a fail."
  else
    bad "$LABEL: the gate and its own histogram disagree — rc=$GRC with unparseable=$GN"
  fi
done <<NARROWEOF
$NARROWINGS
NARROWEOF

# SECOND PASS, on a SYNTHETIC register, and only when the real one fell nothing.
#
# The arm was written to run against the real register on purpose: a synthetic one proves the
# grammar rejects what it was told to reject, which is what the unit block above already proves.
# That reasoning holds, and it has an expiry date. This repo's register was rewritten on
# 2026-09-03 to 001..025 plus H1 — no letter suffix, no letters-digits-letter-digit — so no
# narrowing can ever fell a row here again, and the arm went permanently INCONCLUSIVE. A verdict
# that can never change is a verdict nobody reads, which is the failure this whole file is about
# one level down.
#
# So the fallback runs the SAME shipped gate over a register holding exactly the shapes each
# narrowing removes, and says out loud that it is synthetic. That is strictly more than silence:
# it still cannot claim the live register exercises the grammar — it does not, and the line below
# says so — but it does establish that a narrowed grammar turns the shipped gate red.
if [ "$LIVE" -eq 0 ] && [ "$fail" -eq 0 ] && [ -n "$NARROWINGS" ]; then
  SYNTH=$(make_register falsification-synthetic \
    "- [x] 007m — numeric-with-one-letter — spec-only — the pre-007m shape" \
    "- [ ] 007ab — numeric-with-two-letters — spec-only — the pre-007ab shape" \
    "- [ ] H6s2 — letters-digits-letter-digit — checkpoint — the pre-H7b shape")
  while IFS='|' read -r LABEL ATTR PATTERN CANARY; do
    [ -n "$LABEL" ] || continue
    NDIR="$WORK/narrow-$LABEL"
    [ -f "$NDIR/validate-register-ids.sh" ] || continue
    GOUT=$(REGISTER="$SYNTH" bash "$NDIR/validate-register-ids.sh" 2>&1); GRC=$?
    GN=$(printf '%s\n' "$GOUT" | sed -n 's/.*unparseable: \([0-9]*\).*/\1/p' | head -1)
    [ -n "$GN" ] || GN=-1
    if [ "$GRC" -eq 1 ] && [ "$GN" -gt 0 ]; then
      SLIVE=$((${SLIVE:-0} + 1))
      ok "$LABEL (synthetic register): the shipped gate goes red — $GN row(s) unparseable"
    else
      bad "$LABEL (synthetic register): a register built to hold this shape did not fell it — rc=$GRC unparseable=$GN"
    fi
  done <<SNAREOF
$NARROWINGS
SNAREOF
fi

if [ "$LIVE" -gt 0 ]; then
  ok "the falsification arm is live —$LIVE_DESC"
elif [ "${SLIVE:-0}" -gt 0 ] && [ "$fail" -eq 0 ]; then
  # The gate is proven to catch a narrowed grammar. What is NOT proven is that this repo's own
  # register exercises it — it does not, and that stays on the record rather than being rounded up.
  echo "  ----  every narrowing applied and none fells a row of THIS register (001..025, H1);"
  echo "        falsified against a synthetic register instead — $SLIVE of 3 narrowings caught."
elif [ "$fail" -eq 0 ]; then
  # Every narrowing applied and none of them found anything to fell. That is a fact about THIS
  # register, not about the gate, and the two must not share a verdict.
  echo "  ----  every narrowing applied and none fells a row of this register"
  PRECOND_UNMET=1
  PRECOND_WHY="the register exercises none of the historical narrowings ($(echo $APPLIED_DESC))"
fi
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — $fail of $((pass + fail)) expectations missed"
  exit 1
fi
if [ "$PRECOND_UNMET" -ne 0 ]; then
  echo "INCONCLUSIVE — $pass expectations met, but the falsification could not run:"
  echo "  $PRECOND_WHY"
  echo "The grammar's own cases passed; what is unproven here is that the gate would catch a narrowed"
  echo "grammar, because that check needs a register holding ids the narrowing can fell. Not a pass —"
  echo "and, equally, not the accusation 'this gate cannot detect the defect it was built for'. Those"
  echo "are two different facts and this harness reports them as two (row 007br)."
  exit 2
fi
echo "PASS — $pass/$pass expectations met"
exit 0
