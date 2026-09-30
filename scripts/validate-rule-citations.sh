#!/bin/bash
# validate-rule-citations.sh — every cited rule and doc exists, and every cited trap is defined.
#
# Usage: bash scripts/validate-rule-citations.sh [root]      (root defaults to .)
#
# WHY THIS EXISTS (spec 041). Ten files cited .claude/rules/mutation-timeouts.md, most of them for its
# "trap 4", and the file never existed: no commit added it, none removed it. It was cited into
# existence. Two rationale docs and eight scripts reasoned with a principle nobody could read, and
# nothing noticed, because nothing checked that a cited rule is there.
#
# WHAT IT READS. Every file in the git index under <root>, except specs/. Specs are history: a
# diagnosis legitimately names the file that was missing when it was written.
#
# WHAT IT REPORTS, one `path:line: reason` per problem:
#   - a cited .claude/rules/<name>.md or .claude/docs/<name>.md that does not exist;
#   - a `trap N` beside a citation (same line, or the line before it) that the cited file does not
#     define as a `Trap N` heading;
#   - a bare `<name>.md` beside a `trap N` that names no tracked file at all.
#
# A TEST FIXTURE IS NOT A CITATION. A test that builds `$T/.claude/rules/demo-rule.md` in a temporary
# root and then asserts on the bare path is naming its own fixture. A path the same file builds under
# a variable root (`$VAR/` or `${VAR}/`) is exempt in that file, and only in that file.
#
# Exit codes:
#   0  every citation resolves; prints how many were checked
#   1  at least one does not; each is listed
#   2  usage or environment error (not a git work tree, no python3)
#   3  no citation found at all. That is unmeasurable, not clean: a scan that finds nothing and a
#      repo with nothing wrong must not print the same thing (.claude/rules/mutation-timeouts.md,
#      trap 4).

set -u
ROOT="${1:-.}"
case "$ROOT" in -h|--help) sed -n '2,30p' "$0"; exit 0 ;; esac

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "validate-rule-citations: $ROOT is not a git work tree — the scan reads the index" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "validate-rule-citations: python3 is required" >&2; exit 2; }
TOP=$(git -C "$ROOT" rev-parse --show-toplevel) || exit 2

TOP="$TOP" python3 - <<'PY'
import os, re, subprocess, sys

top = os.environ["TOP"]
listed = subprocess.run(["git", "-C", top, "ls-files", "-z"], capture_output=True).stdout
files = [p for p in listed.decode("utf-8", "replace").split("\0") if p]
tracked = set(files)
tracked_names = {os.path.basename(p) for p in files}

CITE = re.compile(r"(?<![\w$/.-])(\.claude/(?:rules|docs)/[A-Za-z0-9._-]+\.md)")
BUILT = re.compile(r"\$\{?\w+\}?/(\.claude/(?:rules|docs)/[A-Za-z0-9._-]+\.md)")
BARE = re.compile(r"(?<![\w/.-])([A-Za-z0-9_-]+\.md)\b")
TRAP = re.compile(r"\btrap (\d+)\b", re.I)
HEADING = re.compile(r"^#{1,6}\s+Trap\s+(\d+)\b", re.I | re.M)

traps_cache = {}
def traps_of(rel):
    if rel not in traps_cache:
        try:
            with open(os.path.join(top, rel), encoding="utf-8", errors="replace") as f:
                traps_cache[rel] = set(HEADING.findall(f.read()))
        except OSError:
            traps_cache[rel] = None
    return traps_cache[rel]

def resolve_bare(name):
    for d in (".claude/rules/", ".claude/docs/"):
        if os.path.isfile(os.path.join(top, d + name)):
            return d + name
    return None

problems, checked, citing_files = [], 0, set()
for rel in files:
    if rel.startswith("specs/"):
        continue
    path = os.path.join(top, rel)
    try:
        if os.path.getsize(path) > 2_000_000:
            continue
        with open(path, "rb") as f:
            raw = f.read()
    except OSError:
        continue
    if b"\0" in raw:
        continue
    lines = raw.decode("utf-8", "replace").split("\n")
    built = set(BUILT.findall("\n".join(lines)))
    for i, line in enumerate(lines):
        window = (lines[i - 1] + "\n" if i else "") + line
        cited_traps = set(TRAP.findall(window))
        full = [c for c in CITE.findall(line) if c not in built]
        for c in full:
            checked += 1; citing_files.add(rel)
            if not os.path.isfile(os.path.join(top, c)):
                problems.append(f"{rel}:{i+1}: {c} does not exist")
                continue
            defined = traps_of(c) or set()
            for n in sorted(cited_traps - defined, key=int):
                problems.append(f"{rel}:{i+1}: trap {n} is not defined in {c}")
        if not cited_traps or full:
            continue
        # No full path on this line, but a trap is cited: a bare basename is the citation.
        for name in BARE.findall(line):
            target = resolve_bare(name)
            if target is None:
                if name not in tracked_names:
                    checked += 1; citing_files.add(rel)
                    problems.append(f"{rel}:{i+1}: {name} (cited for trap {', '.join(sorted(cited_traps, key=int))}) does not exist")
                continue
            checked += 1; citing_files.add(rel)
            defined = traps_of(target) or set()
            for n in sorted(cited_traps - defined, key=int):
                problems.append(f"{rel}:{i+1}: trap {n} is not defined in {target}")

if problems:
    print("\n".join(problems))
    print(f"validate-rule-citations: {len(problems)} dangling citation(s) of {checked} checked")
    sys.exit(1)
if checked == 0:
    print("validate-rule-citations: unmeasurable — no rule or doc citation found in the index; "
          "a scan that reads nothing cannot say the citations are clean")
    sys.exit(3)
print(f"validate-rule-citations: {checked} citation(s) in {len(citing_files)} file(s), all resolve")
PY
