#!/usr/bin/env bash
#
# test-portability-audit.sh — the portability gate's own gate.
#
# WHY THIS EXISTS. portability_audit.py had no test, and for its first three
# weeks it RECOMMENDED a bug. Its advice for an unpaired `stat -f` was
# `stat -f %m f || stat -c %Y f` — BSD first. On GNU coreutils `stat -f` is
# --file-system: it prints a filesystem block for the file, complains that '%m'
# is not a file, and the capture holds that block whatever the fallback does.
# project-maintenance.sh followed the advice, so on David's Linux machine every
# worktree age was silently dropped as "not a number". Both halves were present,
# so the pairing rule called the line clean; nothing looked at the order.
#
# This pins three things: the wrong order is flagged (single line and across a
# `\` continuation), the right order is not, and the advice text itself names
# the right order. The last case runs the real `stat` on whatever platform this
# is, so the premise is re-proved on Linux rather than remembered from a Mac.

set -uo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$SELF_DIR/portability_audit.py"
TMP="${TMPDIR:-/tmp}/portability-audit-selftest.$$"
PASS=0; FAIL=0
mkdir -p "$TMP"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"; }

# $1 name · stdin script body — prints the audit output, sets RC.
# Fixtures spell the command ST@T so that this file does not trip the very gate
# it tests (C6 runs the gate over scripts/*.sh, this file included); the real
# word is substituted only in the copy the audit reads.
audit_of() {
  sed 's/ST@T/stat/g' > "$TMP/$1.sh"
  OUT=$(PORT_ROOT="$TMP" python3 "$ENGINE" "$TMP/$1.sh" 2>&1); RC=$?
}
expect_flag() {  # $1 label · $2 needle expected in the output
  if [ "$RC" -eq 1 ] && case "$OUT" in *"$2"*) true ;; *) false ;; esac; then ok "$1"
  else bad "$1" "exit 1 and '$2'" "rc=$RC $OUT"; fi
}
expect_clean() {  # $1 label
  if [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1" "exit 0 (clean)" "rc=$RC $OUT"; fi
}

ORDER_LABEL='[stat -f || stat -c]'  # portability-ok — the audit's label, not a command
printf 'portability_audit.py self-test\n'

# ------------------------------------------------ C1 — the order the audit got wrong
printf '\n  -- C1  BSD-first stat is flagged even though both halves are present\n'
# Verbatim the line project-maintenance.sh carried until 2026-09-28.
audit_of pm_regression <<'EOF'
      WT_MT=$(ST@T -f %m "$wt" 2>/dev/null || ST@T -c %Y "$wt" 2>/dev/null)
EOF
expect_flag "project-maintenance.sh's old line" "$ORDER_LABEL"

audit_of continued <<'EOF'
MT=$(ST@T -f %m "$f" 2>/dev/null \
     || ST@T -c %Y "$f" 2>/dev/null \
     || echo 0)
EOF
expect_flag "…and across a backslash continuation" "$ORDER_LABEL"

audit_of date_r <<'EOF'
MT=$(ST@T -f %m "$f" 2>/dev/null || date -r "$f" +%s)
EOF
expect_flag "…and with date -r as the fallback" "$ORDER_LABEL"

# ------------------------------------------------ C2 — the right order stays silent
printf '\n  -- C2  GNU-first stat is clean\n'
audit_of right_one <<'EOF'
MT=$(ST@T -c %Y "$f" 2>/dev/null || ST@T -f %m "$f" 2>/dev/null || echo 0)
EOF
expect_clean "one line"

# The second half sits alone on its own line; the order check looks forward
# only, so `|| stat -f` with nothing after it must not be read as a first form.
audit_of right_multi <<'EOF'
MTIME=$(ST@T -c %Y "$CACHE" 2>/dev/null \
     || ST@T -f %m "$CACHE" 2>/dev/null \
     || echo 0)
EOF
expect_clean "across a continuation"

audit_of two_statements <<'EOF'
A=$(ST@T -c %Y "$a" 2>/dev/null || ST@T -f %m "$a" 2>/dev/null)
B=$(ST@T -c %Y "$b" 2>/dev/null || ST@T -f %m "$b" 2>/dev/null)
EOF
expect_clean "two correct pairs on adjacent lines"

# ------------------------------------------------ C3 — date order is NOT a finding
printf '\n  -- C3  date pairs are order-free (each form fails cleanly on the other platform)\n'
audit_of date_bsd_first <<'EOF'
E=$(date -j -f "%Y-%m-%d" "$S" +%s 2>/dev/null || date -d "$S" +%s 2>/dev/null)
EOF
expect_clean "date -j || date -d"
audit_of date_gnu_first <<'EOF'
E=$(date -d "$S" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$S" +%s 2>/dev/null)
EOF
expect_clean "date -d || date -j"

# ------------------------------------------------ C4 — the older checks still bite
printf '\n  -- C4  unpaired forms, and the advice text\n'
audit_of unpaired_f <<'EOF'
MT=$(ST@T -f %m "$f")
EOF
expect_flag "unpaired stat -f is flagged" "[stat -f]"  # portability-ok — a label
case "$OUT" in
  *'stat -c %Y f 2>/dev/null || stat -f %m f'*) ok "…and the advice puts GNU first" ;;
  *) bad "…and the advice puts GNU first" "stat -c … || stat -f …" "$OUT" ;;
esac
audit_of unpaired_c <<'EOF'
MT=$(ST@T -c %Y "$f")
EOF
expect_flag "unpaired stat -c is flagged" "[stat -c]"  # portability-ok — a label
audit_of exempt <<'EOF'
MT=$(ST@T -f %m "$f" || ST@T -c %Y "$f")  # portability-ok
EOF
expect_clean "a '# portability-ok' line is exempt"

# ------------------------------------------------ C5 — the real stat, this platform
printf '\n  -- C5  the recommended order yields an epoch on this platform\n'
: > "$TMP/probe"
GOOD=$(stat -c %Y "$TMP/probe" 2>/dev/null || stat -f %m "$TMP/probe" 2>/dev/null)
case "$GOOD" in
  ''|*[!0-9]*) bad "stat -c || stat -f gives a number" "digits" "$GOOD" ;;
  *) ok "stat -c || stat -f gives a number ($GOOD)" ;;
esac
if stat --version >/dev/null 2>&1; then
  # GNU only: prove the premise, so the rule is re-checked where it matters.
  BAD=$(stat -f %m "$TMP/probe" 2>/dev/null || stat -c %Y "$TMP/probe" 2>/dev/null)  # portability-ok — the wrong order, on purpose
  case "$BAD" in
    ''|*[!0-9]*) ok "GNU: the BSD-first chain does NOT give a clean number (premise holds)" ;;
    *) bad "GNU: the BSD-first chain is polluted" "non-numeric" "$BAD" ;;
  esac
else
  printf '  skip GNU premise check (BSD stat here)\n'
fi

# ------------------------------------------------ C6 — the repo passes its own gate
printf '\n  -- C6  every scripts/*.sh passes\n'
OUT=$(bash "$SELF_DIR/validate-portability.sh" --all 2>&1); RC=$?
expect_clean "validate-portability.sh --all"

printf '\n%s\n' "----------------------------------------------------------"
printf 'portability_audit.py self-test: %d passed, %d failed\n' "$PASS" "$FAIL"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
