#!/usr/bin/env bash
# test-pipeline-state-merge.sh — the pipeline-state guard while a merge is in flight (row 059).
#
# From agentcrm F094. Ticking a row moves "the active spec" on, and the merge closing the previous
# row finishes after the tick — so a one-line fix to a file the other lane had just landed was judged
# against a spec with no artifacts and denied. The guard now lets a file through while MERGE_HEAD
# exists IF either side of the merge changed it since the merge base, and only then.
#
# Four assertions, and the last two are the ones that keep the fix from being a door:
#   1. mid-merge, a file the merge brings in            → allow
#   2. mid-merge, a file our side changed               → allow
#   3. mid-merge, a file neither side touched           → deny   (an open merge is not a pass)
#   4. merge aborted, the same file as in 1             → deny   (the pass ends with the merge)
#
# Exit 0 = every assertion held. Exit 1 = a real failure. Exit 2 = the fixture could not be built.

set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/hook-verdict.sh"
STATE="$SELF_DIR/pipeline-state-guard-hook.sh"

FAILURES=0
PASSES=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { printf '  ✓ %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

# expect <label> <file> <deny|allow>
expect() {
  local label="$1" file="$2" want="$3" verdict
  verdict=$(hook_verdict "$(jq -n --arg p "$file" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' \
    | bash "$STATE" 2>/dev/null)")
  case "$want:$verdict" in
    allow:none|allow:allow|deny:deny) ok "$label — $want" ;;
    *) fail "$label — expected $want, got $verdict" ;;
  esac
}

ROOT="$TMP/proj"
mkdir -p "$ROOT/specs" "$ROOT/src"
g() { git -C "$ROOT" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
{
  g init -q -b main &&
  echo '{}' > "$ROOT/package.json" &&
  echo 'class Untouched {}' > "$ROOT/src/Untouched.cs" &&
  echo 'class Ours {}'      > "$ROOT/src/Ours.cs" &&
  printf '# Spec register\n\n## Specs\n\n- [/] 041 — previous — spec-only track — being merged\n' > "$ROOT/specs/INDEX.md" &&
  g add -A && g commit -q -m base &&
  g checkout -q -b other &&
  echo 'class Migration {}' > "$ROOT/src/Migration.cs" && g add -A && g commit -q -m theirs &&
  g checkout -q main &&
  echo 'class Ours { int x; }' > "$ROOT/src/Ours.cs" &&
  # The tick that moves the active spec to a row with no artifacts at all.
  printf '# Spec register\n\n## Specs\n\n- [x] 041 — previous — spec-only track — done\n- [/] 042 — next — full track — not started\n' > "$ROOT/specs/INDEX.md" &&
  g add -A && g commit -q -m 'ours + tick' &&
  g merge --no-commit --no-ff other &&
  git -C "$ROOT" rev-parse -q --verify MERGE_HEAD >/dev/null
} || { echo "FIXTURE ERROR: could not build a repository with a merge in flight" >&2; exit 2; }

echo "row 059 — a merge in flight after the tick:"
expect "a file the merge brings in    src/Migration.cs" "$ROOT/src/Migration.cs" allow
expect "a file our side changed       src/Ours.cs"      "$ROOT/src/Ours.cs"      allow
expect "a file neither side touched   src/Untouched.cs" "$ROOT/src/Untouched.cs" deny

g merge --abort
echo "row 059 — the same file once the merge is gone:"
expect "no merge in flight            src/Migration.cs" "$ROOT/src/Migration.cs" deny

echo
echo "test-pipeline-state-merge: $PASSES passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
