#!/usr/bin/env bash
# Tests for scripts/lane-orientation-hook.sh and scripts/lane_status.py.
#
# Two cases carry more weight than the rest.
#
# Case 5 is the template's blast radius. Most projects this ships to have one developer,
# and a hook that prints on every session start there is noise on a screen the CORE
# orientation hook is already using. Silence on a single-lane register is the contract,
# not an accident, so it gets a test.
#
# Case 4 is a known positive. `.claude/rules/mutation-timeouts.md` names the trap: an
# enumeration is only believable once it has found a case you already know is there. A
# question with no Blocks line must be named, because a regex that silently matches
# nothing reports a clean project and a broken one identically.

set -u

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lane-orientation-hook.sh"
STATUS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lane-status.sh"
PASS=0
FAIL=0

fixture() {
  # $1 = register rows, $2 = questions file body (optional)
  ROOT=$(mktemp -d)
  mkdir -p "$ROOT/.git" "$ROOT/specs"
  printf '# Spec register\n\n## Specs\n\n%s\n\n## Register history\n\n- 2026-01-01 — x\n' "$1" \
    > "$ROOT/specs/INDEX.md"
  [ $# -ge 2 ] && printf '# Questions\n\n%s\n' "$2" > "$ROOT/QUESTIONS.md"
}

run() { CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER="$1" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // .systemMessage // ""'; }

check() {
  # $1 = label, $2 = haystack, $3 = needle, $4 = present|absent
  case "$4" in
    present) if grep -qF -- "$3" <<< "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL %s — missing "%s"\n' "$1" "$3"; fi ;;
    absent)  if grep -qF -- "$3" <<< "$2"; then FAIL=$((FAIL+1)); printf 'FAIL %s — should not contain "%s"\n' "$1" "$3"; else PASS=$((PASS+1)); fi ;;
  esac
}

# 1. The other lane is reported; my own row is not (the CORE orientation hook owns that).
fixture '- [/] 010 — office365 — full track — @alex
- [ ] 011 — commission — full track — @sam'
OUT=$(run alex)
check "1a other lane shown"  "$OUT" "@sam: 011 — commission (next up)" present
check "1b own row not shown" "$OUT" "010" absent

# 2. An unowned row whose needs are not all ticked is not offered.
#    011 is a real open row: a `needs` entry naming no row at all is case 7, not this one.
fixture '- [x] 007 — contracts — full track — @alex
- [ ] 011 — ledger — full track — @sam
- [ ] 012 — reporting — full track — needs 011
- [ ] 013 — kyc — full track — needs 007'
OUT=$(run alex)
check "2a runnable row offered"   "$OUT" "unclaimed and runnable: 013" present
check "2b blocked row withheld"   "$OUT" "012" absent

# 3. A question blocking an unticked row is reported; one blocking a ticked row is not.
fixture '- [x] 004 — properties — full track — @alex
- [ ] 020 — search — full track' \
'## 6. Contract terms?

**Blocks:** register row 004.

body

## 12. API key?

**Blocks:** register row 020.

body'
OUT=$(run alex)
check "3a open row reported"  "$OUT" "question 12 → 020" present
check "3b ticked row silent"  "$OUT" "question 6" absent

# 3c. The Swedish alternates parse identically — the project this came from writes its
#     question file in Swedish, and a one-language parser would report it as empty.
fixture '- [ ] 020 — search — full track — @alex' \
'## 12. Nyckeln?

**Blockerar:** registerrad 020.

body'
OUT=$(run sam)
check "3c swedish alternates parse" "$OUT" "question 12 → 020" present

# 4. KNOWN POSITIVE — a question with no Blocks line must be named, not skipped.
fixture '- [ ] 020 — search — full track — @alex' \
'## 7. Nobody mapped this one?

Body text, no Blocks line.'
OUT=$(run alex)
check "4 unmapped question named" "$OUT" "no Blocks line: question 7" present

# 5. CONTRACT — a single-lane register (no owner tag anywhere) prints nothing at all.
fixture '- [x] 001 — foundation — full track
- [ ] 002 — search — full track
- [ ] 003 — admin — full track — needs 002'
OUT=$(run alex)
check "5a single lane is silent" "$OUT" "LANE" absent
check "5b single lane is silent" "$OUT" "002" absent

# 5c. ...but the full report still answers on that same single-lane project.
OUT=$(CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER=alex bash "$STATUS" --root "$ROOT" 2>/dev/null)
check "5c full report still answers" "$OUT" "002 — search" present

# 7. KNOWN POSITIVE (row 042) — a `needs` entry with no digit is prose, not a dependency.
#    agentcrm writes `needs inget`; reading it as an id withheld six of nine runnable rows, two
#    of them carved security rows. An id-shaped entry still resolves: a real open row blocks,
#    and one that names no row blocks AND is named, so a typo (`needs 04` for 004) can neither
#    free a row nor hold it silently.
fixture '- [x] 007 — contracts — full track — @alex
- [ ] 011 — ledger — full track — @sam
- [ ] 031 — csrf — full track — needs inget
- [ ] 032 — rate-limit — full track — needs nothing — carved by H3
- [ ] 033 — audit — full track — needs none, 007
- [ ] 034 — export — full track — needs 011, inget
- [ ] 035 — import — full track — needs 007
- [ ] 004 — base — full track — @sam
- [ ] 036 — typo — full track — needs 04
- [ ] 038 — ghost — full track — needs R9, ingenting
- [x] 037 — done — full track — needs 09'
OUT=$(run alex)
check "7a brief offers exactly these"  "$OUT" "unclaimed and runnable: 031, 032, 033, 035" present
check "7b typo named in brief"         "$OUT" "needs names no row, held until fixed: 036 → 04; 038 → R9" present
FULL=$(CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER=alex bash "$STATUS" --root "$ROOT" 2>/dev/null)
check "7c none + ticked offered"       "$FULL" "    033 — audit" present
check "7d open need still blocks"      "$FULL" "    034 — export" absent
check "7e typo still blocks"           "$FULL" "    036 — typo" absent
check "7f unknown id still blocks"     "$FULL" "    038 — ghost" absent
check "7g typo named in full"          "$FULL" "036 → 04" present
check "7h prose not reported"          "$FULL" "→ inget" absent
check "7i prose not reported"          "$FULL" "→ nothing" absent
check "7j prose not reported"          "$FULL" "→ ingenting" absent
check "7k ticked row not reported"     "$FULL" "037 →" absent
check "7l resolved id not reported"    "$FULL" "→ 007" absent

# 7m. Single-lane brief stays silent even with an unresolved id (case 5's contract).
fixture '- [ ] 001 — a — full track — needs 09'
OUT=$(run alex)
check "7m single lane brief silent" "$OUT" "needs names no row" absent

# 8. A capped list says it is capped. After 042 agentcrm's own 2026-09-08 register has nine
#    runnable rows; the full report shows eight and the brief six, and a list cut short without
#    saying so is the same withheld row this case exists to catch.
fixture "$(for i in 01 02 03 04 05 06 07 08 09 10; do printf -- '- [ ] 1%s — r%s — full track\n' "$i" "$i"; done)
- [ ] 200 — mine — full track — @alex"
OUT=$(run sam)
check "8a brief says how many more" "$OUT" "101, 102, 103, 104, 105, 106 (+4 more)" present
FULL=$(CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER=alex bash "$STATUS" --root "$ROOT" 2>/dev/null)
check "8b full names the rest"      "$FULL" "… and 2 more: 109, 110" present
fixture "$(for i in 01 02 03 04 05 06 07 08; do printf -- '- [ ] 1%s — r%s — full track\n' "$i" "$i"; done)
- [ ] 200 — mine — full track — @alex"
FULL=$(CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER=alex bash "$STATUS" --root "$ROOT" 2>/dev/null)
check "8c exactly eight: no tail"   "$FULL" "more:" absent
OUT=$(run sam)
check "8d brief over six by two"    "$OUT" "(+2 more)" present
fixture "$(for i in 01 02 03 04 05 06; do printf -- '- [ ] 1%s — r%s — full track\n' "$i" "$i"; done)
- [ ] 200 — mine — full track — @alex"
OUT=$(run sam)
check "8e exactly six: no brief tail" "$OUT" "more)" absent

# 6. No register at all → silent, exit 0.
ROOT=$(mktemp -d); mkdir -p "$ROOT/.git"
OUT=$(CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER=alex bash "$HOOK" 2>/dev/null); RC=$?
check "6a silent with no register" "$OUT" "LANE" absent
if [ "$RC" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL 6b exit $RC"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
