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

run() { CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER="$1" bash "$HOOK" 2>/dev/null | jq -r '.systemMessage // ""'; }

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
fixture '- [x] 007 — contracts — full track — @alex
- [ ] 012 — reporting — full track — needs 011
- [ ] 013 — kyc — full track — needs 007'
OUT=$(run alex)
check "2a runnable row offered"   "$OUT" "013" present
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

# 6. No register at all → silent, exit 0.
ROOT=$(mktemp -d); mkdir -p "$ROOT/.git"
OUT=$(CLAUDE_PROJECT_DIR="$ROOT" SPEC_OWNER=alex bash "$HOOK" 2>/dev/null); RC=$?
check "6a silent with no register" "$OUT" "LANE" absent
if [ "$RC" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL 6b exit $RC"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
