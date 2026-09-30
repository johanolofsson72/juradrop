#!/usr/bin/env bash
# test-spec-dir-absent.sh — an active row with no spec directory, and the files that slipped past.
#
# Spec 032, from fundit F001. fundit's 016a (a static holding page) shipped with no spec directory
# at all, and the finding blamed `found: false` in spec_active.py. Measured, that is not the hole:
# both pipeline guards DENY a directory-less row and always did. What let 016a through was
#   (1) the pre-046 deny carrying no hookEventName, so the CLI dropped it (closed by 046), and
#   (2) the product itself — index.html, a stylesheet — sitting outside SOURCE_EXTS, so no guard
#       asked at all (closed here).
#
# No other test has an active row with NO directory: test-pipeline-hooks.sh always creates
# specs/003-search, and test-active-spec-resolution.sh creates its 007z directory empty. So the
# verdict the finding worried about was never pinned. It is now, read through hook_verdict so a
# deny the CLI would drop counts as a failure, which is the exact way 016a got through.
#
# Exit 0 = every assertion held. Exit 1 = a real failure.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
STATE="$SELF_DIR/pipeline-state-guard-hook.sh"
INTERVIEW="$SELF_DIR/spec-interview-guard-hook.sh"
REGISTER_GUARD="$SELF_DIR/spec-register-guard-hook.sh"

FAILURES=0
PASSES=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { printf '  ✓ %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# run_guard <guard> <file> -> raw hook output
run_guard() {
  jq -n --arg p "$2" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' \
    | SPEC_INTERVIEW_MODE=auto bash "$1" 2>/dev/null
}

# expect <label> <guard> <file> <deny|allow> [needle]
expect() {
  local label="$1" guard="$2" file="$3" want="$4" needle="${5:-}" out verdict
  out=$(run_guard "$guard" "$file")
  verdict=$(hook_verdict "$out")
  if [ "$want" = allow ]; then
    case "$verdict" in none|allow) ok "$label — allow" ;; *) fail "$label — expected allow, got $verdict" ;; esac
    return
  fi
  if [ "$verdict" != deny ]; then
    fail "$label — expected deny, got $verdict"
    return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | jq -e --arg n "$needle" \
      '.hookSpecificOutput.permissionDecisionReason | contains($n)' >/dev/null 2>&1; then
    fail "$label — denied, but the reason does not name \"$needle\""
    return
  fi
  ok "$label — deny${needle:+ (names $needle)}"
}

# The 016a fixture: a marker repo, a register whose active row owns no directory.
ROOT="$TMP/fundit"
mkdir -p "$ROOT/.git" "$ROOT/specs" "$ROOT/src" "$ROOT/site" "$ROOT/deploy" "$ROOT/scripts"
echo '{}' > "$ROOT/package.json"
cat > "$ROOT/specs/INDEX.md" <<'REG'
# Spec register

## Specs

- [x] 015 — earlier — spec-only track — done
- [/] 016a — holding-page — spec-only track — a static page so the address answers
- [ ] 016 — site — full track — the marketing site
REG

echo "SC-032-01 — active row, no spec directory, a source file:"
expect "pipeline-state  src/app.ts" "$STATE"     "$ROOT/src/app.ts" deny 016a
expect "interview       src/app.ts" "$INTERVIEW" "$ROOT/src/app.ts" deny 016a

echo "SC-032-02 — the product 016a actually shipped (markup + stylesheets):"
for f in site/index.html site/INDEX.HTM site/style.css site/app.min.css site/theme.scss site/theme.sass site/theme.less; do
  expect "pipeline-state  $f" "$STATE"     "$ROOT/$f" deny 016a
  expect "interview       $f" "$INTERVIEW" "$ROOT/$f" deny 016a
done

echo "SC-032-03 — the deliberate exemptions still hold:"
for f in deploy/stack.yml deploy/nginx-site.conf site/favicon.svg site/Dockerfile scripts/deploy-site.sh specs/mockup.html; do
  expect "pipeline-state  $f" "$STATE"     "$ROOT/$f" allow
  expect "interview       $f" "$INTERVIEW" "$ROOT/$f" allow
done

echo "SC-032-04 — no register yet, a marker repo, markup:"
BARE="$TMP/bare"
mkdir -p "$BARE/.git" "$BARE/site"
echo '{}' > "$BARE/package.json"
expect "spec-register   site/index.html" "$REGISTER_GUARD" "$BARE/site/index.html" deny
expect "spec-register   site/style.css"  "$REGISTER_GUARD" "$BARE/site/style.css"  deny
expect "spec-register   deploy.yml"      "$REGISTER_GUARD" "$BARE/deploy.yml"      allow

echo "SC-032-05 — one list of source extensions, not three:"
lists=$(for g in "$STATE" "$INTERVIEW" "$REGISTER_GUARD"; do grep -m1 '^SOURCE_EXTS=' "$g"; done | sort -u)
count=$(printf '%s\n' "$lists" | grep -c .)
if [ "$count" -eq 1 ]; then
  ok "SOURCE_EXTS is byte-identical in the three path guards"
else
  fail "SOURCE_EXTS differs between the three path guards ($count variants)"
fi

echo "SC-032-06 — a spec that did its pipeline can still edit markup:"
DIR="$ROOT/specs/016a-holding-page"
mkdir -p "$DIR"
printf '# 016a\n\n## Clarifications\n\n- Q: x → A: y\n' > "$DIR/spec.md"
echo '# plan'  > "$DIR/plan.md"
echo '# tasks' > "$DIR/tasks.md"
{ echo '# Spec interview — 016a'; for i in $(seq 1 15); do printf '\n## Q%s\n**Q:** q?\n**A (auto):** answer %s\n' "$i" "$i"; done; } > "$DIR/interview.md"
expect "pipeline-state  site/index.html" "$STATE"     "$ROOT/site/index.html" allow
expect "interview       site/index.html" "$INTERVIEW" "$ROOT/site/index.html" allow

echo
echo "$PASSES passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
