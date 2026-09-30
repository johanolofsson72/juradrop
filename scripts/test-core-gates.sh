#!/bin/bash
# test-core-gates.sh — core-gates.sh partitions the gate-shaped CORE scripts, and says so or refuses.
#
# core-gates.sh is the CORE half of a project's gate registry (row 014). Two ways it can lie, both
# quiet: an exclusion that names nothing any more (the file was renamed, the line stays, and a new
# gate is silently excluded under the old reason), and a gate-shaped template-only script left out
# of the table (a project holding a stale copy runs it; F004's hook hangs on stdin). This pins the
# partition against the real template-autosync.sh, then plants each defect in a copy and requires a
# refusal that names it.
#
# Scenario ids: none. Offline, no network, writes only under mktemp.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SD/core-gates.sh"
P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
bad(){ echo "  FAIL  $1"; F=$((F+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Read from core-gates.sh, not restated: two copies of the shape are how two runners come to disagree.
SHAPE=$(sed -n "s/^GATE_SHAPE='\(.*\)'\$/\1/p" "$SUT")
[ -n "$SHAPE" ] || { echo "  FAIL  GATE_SHAPE could not be read from core-gates.sh"; exit 1; }
CORE=$(bash "$SD/template-autosync.sh" --list-core-scripts) || { echo "FAIL  cannot list CORE"; exit 1; }
# TEMPLATE_ONLY_SCRIPTS has no query mode (the query-mode list is capped at four), so it is read from
# the assignment itself: the lines from its opening quote to its closing one.
TONLY=$(awk '/^TEMPLATE_ONLY_SCRIPTS="/{on=1} on{print} on && /"$/{exit}' "$SD/template-autosync.sh" \
  | sed 's/^TEMPLATE_ONLY_SCRIPTS="//; s/"$//' | tr ' ' '\n' | grep -v '^$')
[ -n "$TONLY" ] && ok "TEMPLATE_ONLY_SCRIPTS read ($(printf '%s\n' "$TONLY" | wc -l | tr -d ' ') names)" \
  || bad "TEMPLATE_ONLY_SCRIPTS could not be read from template-autosync.sh"

GATES=$(bash "$SUT"); rc=$?
[ "$rc" -eq 0 ] && [ -n "$GATES" ] && ok "core-gates.sh answers ($(printf '%s\n' "$GATES" | wc -l | tr -d ' ') gates)" \
  || bad "core-gates.sh exit $rc, gates='$GATES'"
NON=$(bash "$SUT" --non-gates | cut -d'|' -f1); rc=$?
[ "$rc" -eq 0 ] && [ -n "$NON" ] && ok "--non-gates answers" || bad "--non-gates exit $rc"

in_set(){ grep -qxF -- "$1" <<< "$2"; }

# a. Every table name is a script the template knows. A stale exclusion is the quiet one: it keeps a
#    reason for a file that is gone, and nothing reads it again.
stale=""
for n in $NON; do in_set "$n" "$CORE" || in_set "$n" "$TONLY" || stale="$stale $n"; done
[ -z "$stale" ] && ok "a: every non-gate is in CORE_SCRIPTS or TEMPLATE_ONLY_SCRIPTS" \
  || bad "a: stale non-gate(s), in neither list:$stale"

# b. Every gate-shaped template-only script is excluded, so a stale downstream copy is never run.
miss=""
for n in $(printf '%s\n' "$TONLY" | grep -E "$SHAPE"); do in_set "$n" "$NON" || miss="$miss $n"; done
[ -z "$miss" ] && ok "b: every gate-shaped template-only script is a non-gate" \
  || bad "b: gate-shaped template-only script(s) not excluded:$miss"

# c. Gates and CORE non-gates partition the gate-shaped CORE set exactly.
SHAPED=$(printf '%s\n' "$CORE" | grep -E "$SHAPE" | sort -u)
UNION=$( { printf '%s\n' "$GATES"; for n in $NON; do in_set "$n" "$CORE" && echo "$n"; done; } | sort -u)
[ "$SHAPED" = "$UNION" ] && ok "c: gates + CORE non-gates = the gate-shaped CORE set ($(printf '%s\n' "$SHAPED" | wc -l | tr -d ' '))" \
  || bad "c: partition differs: $(diff <(echo "$SHAPED") <(echo "$UNION") | grep '^[<>]' | tr '\n' ' ')"
both=""
for n in $NON; do in_set "$n" "$GATES" && both="$both $n"; done
[ -z "$both" ] && ok "c: no name is both a gate and a non-gate" || bad "c: in both:$both"

# d. A gate with no bytes cannot be run (rocky F041: a CORE name the template never held).
absent=""
for n in $GATES; do [ -f "$SD/$n" ] || absent="$absent $n"; done
[ -z "$absent" ] && ok "d: every gate exists in scripts/" || bad "d: listed gate(s) with no file:$absent"

# e. Both files ship, or no project ever sees the list.
in_set core-gates.sh "$CORE" && in_set test-core-gates.sh "$CORE" \
  && ok "e: core-gates.sh and test-core-gates.sh are CORE" || bad "e: core-gates.sh or its test is not in CORE_SCRIPTS"
in_set test-core-gates.sh "$GATES" && ok "e: this self-test is itself a gate (R3)" || bad "e: test-core-gates.sh is not listed as a gate"

# f. Sabotage. A copy of core-gates.sh beside a stub template-autosync.sh; each arm PLANTS its own
#    table line at the head of NON_GATES rather than editing a real one, so the arms do not go stale
#    when the table changes. A refusal must be exit 2 AND name its cause, or nobody can act on it.
STUB_CORE='test-a.sh validate-b.sh test-scenario-map-fixtures.sh validate-scenario-traceability.sh hook.sh'
arm(){  # arm <name> <planted table line(s), may be empty> <stub core names> <stub exit> <want-exit> <want-text>
  local d="$T/arm$P$F"; mkdir -p "$d"
  if [ -n "$2" ]; then
    # Through ENVIRON, not -v: BSD awk refuses a newline in a -v value, and the duplicate arm has one.
    PLANT="$2" awk '!done && index($0, "NON_GATES='"'"'") == 1 { sub(/^NON_GATES='"'"'/, "NON_GATES='"'"'" ENVIRON["PLANT"] "\n"); done = 1 } { print } END { exit !done }' "$SUT" > "$d/core-gates.sh"
  else cp "$SUT" "$d/core-gates.sh"; fi || { bad "f: $1 — could not plant the line; the arm did not run"; return; }
  printf '#!/bin/bash\n[ "$1" = --list-core-scripts ] || exit 9\nprintf "%%s\\n" %s\nexit %s\n' "$3" "$4" > "$d/template-autosync.sh"
  local out rc; out=$(bash "$d/core-gates.sh" 2>&1); rc=$?
  if [ "$rc" -eq "$5" ] && grep -qF -- "$6" <<< "$out"; then ok "f: $1"
  else bad "f: $1 — exit $rc (want $5), output: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"; fi
}
arm "control: the unmodified copy answers"          ""                                      "$STUB_CORE" 0 0 "test-a.sh"
arm "control: a well-formed planted line is accepted" "test-z.sh|a reason"                  "$STUB_CORE" 0 0 "validate-b.sh"
arm "a line with no | is refused"                   "test-z.sh a reason"                    "$STUB_CORE" 0 2 "no | in line: test-z.sh a reason"
arm "an empty reason is refused"                    "test-z.sh|  "                          "$STUB_CORE" 0 2 "empty reason for test-z.sh"
arm "a duplicate name is refused"                   "$(printf 'test-z.sh|r\ntest-z.sh|r')" "$STUB_CORE" 0 2 "test-z.sh is listed twice"
arm "a non-gate-shaped name is refused"             "runner-z.sh|r"                         "$STUB_CORE" 0 2 "runner-z.sh is not gate-shaped"
arm "a failing CORE query is refused"               ""                                      "$STUB_CORE" 1 2 "--list-core-scripts failed"
arm "an empty gate set is refused"                  ""                                      "hook.sh test-scenario-map-fixtures.sh" 0 2 "no CORE gate at all"
# R3, gate by default: a name written only into the stub CORE list comes out as a gate.
arm "a new gate-shaped CORE name is a gate unasked" ""                                      "$STUB_CORE check-new.sh" 0 0 "check-new.sh"
# And a planted exclusion takes a CORE gate out.
arm "a planted exclusion removes that gate"         "test-a.sh|r"                           "$STUB_CORE" 0 0 "validate-b.sh"
# The two non-gates in the stub CORE list must NOT come out as gates.
d="$T/excl"; mkdir -p "$d"; cp "$SUT" "$d/core-gates.sh"
printf '#!/bin/bash\nprintf "%%s\\n" %s\n' "$STUB_CORE" > "$d/template-autosync.sh"
out=$(bash "$d/core-gates.sh")
[ "$out" = "$(printf 'test-a.sh\nvalidate-b.sh')" ] && ok "f: non-gates and non-gate-shaped names are left out" \
  || bad "f: expected exactly test-a.sh + validate-b.sh, got: $(echo $out)"
rm -f "$d/template-autosync.sh"
out=$(bash "$d/core-gates.sh" 2>&1); rc=$?
[ "$rc" -eq 2 ] && grep -qF "template-autosync.sh is missing" <<< "$out" \
  && ok "f: a missing template-autosync.sh is refused" || bad "f: missing template-autosync.sh — exit $rc: $out"

echo
echo "test-core-gates.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
