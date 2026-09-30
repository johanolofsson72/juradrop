#!/bin/bash
# test-max-id-in-refs.sh — two lanes never mint the same finding id (row 054).
#
# The defect: finding.sh numbered by COUNTING local ledger rows. agentcrm 2026-09-17: origin/main
# and a spec branch each held a different F141–F143, and merge=union joined them without a marker.
set -uo pipefail
export LC_ALL=C
SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$SD/max-id-in-refs.sh"
P=0; F=0
ok(){ echo "  PASS  $1"; P=$((P+1)); }
bad(){ echo "  FAIL  $1"; F=$((F+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
g(){ git -C "$1" -c user.email=t@t -c user.name=t "${@:2}" >/dev/null 2>&1; }
RE='^- \[[ xX]\] F[0-9]+'
max(){ bash "$SUT" --dir "$1" --regex "$RE" -- 'specs/FINDINGS*.md' 2>/dev/null; }

# A lane: a repository with scripts/ and a ledger, and a bare "origin" both lanes push to.
git init -q --bare "$T/origin.git"
git init -q "$T/a"; mkdir -p "$T/a/specs" "$T/a/scripts"
cp "$SD/finding.sh" "$SD/max-id-in-refs.sh" "$T/a/scripts/"
printf '# Findings\n\n## Open\n\n' > "$T/a/specs/FINDINGS.md"
g "$T/a" add -A; g "$T/a" commit -qm seed; g "$T/a" branch -M main
g "$T/a" remote add origin "$T/origin.git"; g "$T/a" push -q origin main
git clone -q -b main "$T/origin.git" "$T/b" 2>/dev/null

got=$(max "$T/a"); [ -z "$got" ] && ok "an empty ledger has no id" || bad "empty: got '$got'"
bash "$SUT" --dir "$T/a" --regex "$RE" -- 'specs/FINDINGS*.md' >/dev/null 2>&1
[ $? -eq 0 ] && ok "no id is exit 0, not a failure" || bad "empty exit code"

# Lane A records three findings and pushes its spec branch.
g "$T/a" checkout -q -b spec/044
for t in one two three; do ( cd "$T/a" && bash scripts/finding.sh --add "$t" >/dev/null 2>&1 ); done
g "$T/a" add -A; g "$T/a" commit -qm a; g "$T/a" push -q origin spec/044
[ "$(max "$T/a")" = "003" ] && ok "the local ledger counts (F003)" || bad "local: got $(max "$T/a")"

# Lane B has not merged it — only fetched. The count-based allocator said F001 here.
g "$T/b" fetch -q origin
OUT=$( cd "$T/b" && bash scripts/finding.sh --add "lane b" 2>&1 )
case "$OUT" in *F004*) ok "lane B skips lane A's pushed F001–F003 (F004)" ;; *) bad "cross-lane: $OUT" ;; esac

# Uncommitted edits count: the id minted a minute ago is the likeliest to be reused.
OUT=$( cd "$T/b" && bash scripts/finding.sh --add "again" 2>&1 )
case "$OUT" in *F005*) ok "an uncommitted ledger line is taken (F005)" ;; *) bad "uncommitted: $OUT" ;; esac

# A deleted line does not free its number (the second half of 054).
sed -i.bak '/F005/d' "$T/b/specs/FINDINGS.md"; rm -f "$T/b/specs/FINDINGS.md.bak"
g "$T/b" add -A; g "$T/b" commit -qm b
OUT=$( cd "$T/b" && bash scripts/finding.sh --add "after delete" 2>&1 )
# F005 was never committed or pushed, so it is genuinely free; F004 is committed and must not be reused.
case "$OUT" in *F005*) ok "the next id is past every committed id, not the row count" ;; *) bad "delete: $OUT" ;; esac
sed -i.bak '/F004/d' "$T/b/specs/FINDINGS.md"; rm -f "$T/b/specs/FINDINGS.md.bak"
g "$T/b" add -A; g "$T/b" commit -qm del
OUT=$( cd "$T/b" && bash scripts/finding.sh --add "count would say F004" 2>&1 )
case "$OUT" in *F004*) bad "a deleted committed id was reused: $OUT" ;; *F006*) ok "a deleted id stays taken while any ref holds it (F006)" ;; *) bad "reuse: $OUT" ;; esac

# Decided rows and archives count.
printf -- '- [x] F090 — gap — 2026-01-01 — old  →  dropped\n' > "$T/b/specs/FINDINGS.archive.md"
[ "$(max "$T/b")" = "090" ] && ok "a decided id in a FINDINGS*.md archive is taken" || bad "archive: $(max "$T/b")"

# Numeric, not lexical: F1000 beats F999.
printf -- '- [ ] F999 — gap — x\n- [ ] F1000 — gap — y\n' >> "$T/b/specs/FINDINGS.archive.md"
[ "$(max "$T/b")" = "1000" ] && ok "compares numerically (1000 > 999)" || bad "numeric: $(max "$T/b")"

# Not a repository: the files are all there is, and it still works.
mkdir -p "$T/plain/specs"; printf -- '- [ ] F007 — gap — x\n' > "$T/plain/specs/FINDINGS.md"
[ "$(max "$T/plain")" = "007" ] && ok "works outside a git repository" || bad "plain: $(max "$T/plain")"

# Usage errors are exit 2.
bash "$SUT" --regex x >/dev/null 2>&1; [ $? -eq 2 ] && ok "no pathspec is a usage error" || bad "usage pathspec"
bash "$SUT" -- x >/dev/null 2>&1; [ $? -eq 2 ] && ok "no regex is a usage error" || bad "usage regex"

echo; echo "test-max-id-in-refs: $P passed, $F failed"
[ "$F" -eq 0 ]
