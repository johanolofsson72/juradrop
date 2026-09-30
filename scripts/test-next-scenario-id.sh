#!/bin/bash
# test-next-scenario-id.sh — two specs in two lanes never take the same scenario ids (row 060).
#
# agentcrm 2026-09-21: 47 colliding ids, 26 of them specs 052 and 055 both taking SC-1625..1650.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SD/next-scenario-id.sh"
P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
bad(){ echo "  FAIL  $1"; F=$((F+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
g(){ git -C "$1" -c user.email=t@t -c user.name=t "${@:2}" >/dev/null 2>&1; }
nx(){ bash "$SUT" --dir "$1" "${@:2}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
HDR='| ID | Kind | Scenario | Expected outcome | Status |
|----|------|----------|------------------|--------|'

mkdir -p "$T/plain/specs"
[ "$(nx "$T/plain")" = "SC-001" ] && ok "an empty project starts at SC-001" || bad "empty: $(nx "$T/plain")"

printf '%s\n| SC-001 | happy | a | b | ✓ |\n| ~~SC-007~~ | happy | retired | b | ✓ |\n' "$HDR" > "$T/plain/specs/SCENARIOS.md"
[ "$(nx "$T/plain")" = "SC-008" ] && ok "a struck (retired) id is taken" || bad "struck: $(nx "$T/plain")"

# Prose and flowchart mentions are not rows and must not move the allocator.
printf 'See SC-500 in prose.\n  A --> B[done SC-600]\n' >> "$T/plain/specs/SCENARIOS.md"
[ "$(nx "$T/plain")" = "SC-008" ] && ok "prose and flowchart mentions are ignored" || bad "prose: $(nx "$T/plain")"

# Split layout: per-feature files count, and the history archive counts.
mkdir -p "$T/plain/specs/scenarios"
printf '%s\n| SC-040 | error | a | b | ☐ |\n' "$HDR" > "$T/plain/specs/scenarios/login.md"
printf '%s\n| SC-120 | happy | a | b | ✓ |\n' "$HDR" > "$T/plain/specs/SCENARIOS.history.md"
[ "$(nx "$T/plain")" = "SC-121" ] && ok "feature files and SCENARIOS.history.md count" || bad "split: $(nx "$T/plain")"

[ "$(nx "$T/plain" --count 3)" = "SC-121 SC-122 SC-123" ] && ok "--count returns a consecutive block" || bad "--count: $(nx "$T/plain" --count 3)"

# Past three digits it grows instead of refusing (row 048's allocation half).
printf '| SC-999 | happy | a | b | ✓ |\n' >> "$T/plain/specs/scenarios/login.md"
[ "$(nx "$T/plain" --count 2)" = "SC-1000 SC-1001" ] && ok "SC-999 is followed by SC-1000" || bad "width: $(nx "$T/plain" --count 2)"

printf '%s\n| UC-0042 | happy | a | b | ✓ |\n' "$HDR" > "$T/plain/specs/scenarios/uc.md"
[ "$(nx "$T/plain" --prefix UC)" = "UC-0043" ] && ok "--prefix and the map's padding are honoured" || bad "prefix: $(nx "$T/plain" --prefix UC)"

# The agentcrm case: lane A pushes its spec branch with SC-1625..1650; lane B, fetched but not
# merged, must be handed ids past them.
git init -q --bare "$T/origin.git"
git init -q "$T/a"; mkdir -p "$T/a/specs/scenarios"
printf '%s\n| SC-1624 | happy | a | b | ✓ |\n' "$HDR" > "$T/a/specs/SCENARIOS.md"
g "$T/a" add -A; g "$T/a" commit -qm seed; g "$T/a" branch -M main
g "$T/a" remote add origin "$T/origin.git"; g "$T/a" push -q origin main
git clone -q -b main "$T/origin.git" "$T/b" 2>/dev/null
[ "$(nx "$T/a")" = "SC-1625" ] && ok "lane A gets SC-1625" || bad "lane A: $(nx "$T/a")"
g "$T/a" checkout -q -b 052-spec
{ printf '%s\n' "$HDR"
  for n in $(seq 1625 1650); do printf '| SC-%d | happy | a | b | ☐ |\n' "$n"; done
} > "$T/a/specs/scenarios/052.md"
g "$T/a" add -A; g "$T/a" commit -qm 052; g "$T/a" push -q origin 052-spec
[ "$(nx "$T/b")" = "SC-1625" ] && ok "before a fetch lane B cannot know (the documented residual)" || bad "pre-fetch: $(nx "$T/b")"
g "$T/b" fetch -q origin
[ "$(nx "$T/b")" = "SC-1651" ] && ok "after a fetch lane B skips lane A's pushed block (SC-1651)" || bad "cross-lane: $(nx "$T/b")"

# Uncommitted rows in this worktree are taken too. (git keeps no empty directory, so make it.)
mkdir -p "$T/b/specs/scenarios"
printf '%s\n| SC-1700 | happy | a | b | ☐ |\n' "$HDR" > "$T/b/specs/scenarios/055.md"
[ "$(nx "$T/b")" = "SC-1701" ] && ok "an untracked feature file is read" || bad "untracked: $(nx "$T/b")"

bash "$SUT" --count 0 >/dev/null 2>&1; [ $? -eq 2 ] && ok "--count 0 is a usage error" || bad "count 0"
bash "$SUT" --prefix 'S.C' >/dev/null 2>&1; [ $? -eq 2 ] && ok "a non-letter prefix is refused" || bad "prefix regex"

echo; echo "test-next-scenario-id: $P passed, $F failed"
[ "$F" -eq 0 ]
