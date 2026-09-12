#!/bin/bash
# archive-completed-rows.sh — keep specs/INDEX.md's SPEC ROWS small, without
# losing what they say.
#
# WHY: spec 007bt fixed this defect one level down — a HISTORY entry that is "one
# line" by the letter and a paragraph by every other measure — and then measured
# where the bytes in specs/INDEX.md actually are. They are not in the history
# section that archive-spec-history.sh was built to control. Measured 2026-08-29:
# 36,521 of 39,950 bytes (91.4%) are the 106 spec rows, against 1,918 for the
# whole history section. The file is read on essentially every spec.
#
# The rows split into three populations, and only one of them is a new problem:
#
#   70 completed rows archived to INDEX.completed.md    14,484 B   mean 207, max 293
#   20 completed rows never archived                    13,878 B   mean 694, max 1488
#   16 rows not started                                  8,159 B   mean 510, max 1121
#
# Not one archived row exceeds 293 bytes. The mechanism works, and INDEX.md's own
# header already promises it: "Completed rows carry a one-line goal. Their full
# retrospectives are archived verbatim in specs/INDEX.completed.md." That archive
# says how it was built — "Archived 2026-08-22 from 48 completed rows; extended
# 2026-08-25 with 22 more" — two hand-runs, and then nothing. It ends at 007bi.
# Every row ticked since is still inline at full length, because there was no
# script: archive-spec-history.sh archives the history section and has never
# touched a spec row. 35% of the file is debt the project already knew how to pay
# and left to memory. This script is that missing half.
#
# The unstarted rows are a different fault with a legitimate cause. Every
# over-budget one is a defect surfaced by a completed spec, and it is long because
# the finding was understood at the moment it was surfaced, the spec directory
# that would hold it does not exist yet, and the row is the only writable surface
# in reach. So the row absorbs the measurement, the falsified hypothesis, the .trx
# path. That is the correct instinct meeting a missing container. The container is
# specs/INDEX.pending.md, and a pending entry moves to INDEX.completed.md when the
# spec is ticked.
#
# WHAT THIS SCRIPT WILL NOT DO: rewrite an inline row. The archived form of 007bi
# is not a substring of the original — 1,606 bytes of diagnosis became a rewritten
# 191-byte goal, and that is judgment, not string manipulation. A script that
# truncated instead would produce rows ending mid-clause, which read as damage. So
# the division is: this script PRESERVES and REPORTS, the author REWRITES.
#
# ORDERING IS THE SAFETY PROPERTY. Preserve first, shorten second. A row may only
# be shortened once its long form is in an archive. Shortening an unarchived row
# is the one operation here that destroys understanding, and it is precisely what
# a careless run would do — so the report labels every over-budget row either
# "shortenable" (its diagnosis is preserved) or "archive first" (it is not).
#
# BYTE BUDGET: 300, calibrated the way 007bt calibrated its own. The compliant
# population is the 70 archived completed rows plus the 8 planned-feature rows —
# 78 rows written the way both the header and the rule ask for. p50 200, p75 229,
# p90 253, p95 265, max 293. 300 is the smallest round number above p95 and admits
# 78 of 78; 250 would flag 8 rows that were written correctly, 400 admits 4 of the
# rows this exists to catch. That it lands on the same 300 as 007bt's history
# budget is a coincidence of two independent measurements, not a number copied
# across — a welcome one, because one number for "a line in the register" is
# teachable in a way two nearby numbers are not.
#
# Bytes rather than sentences, for 007bt's reason: sentence-splitting over prose
# holding "007bi:", file paths, "e.g." and "0.04 s" is a heuristic, and a gate
# whose verdict rests on a heuristic is one people argue with instead of obeying.
#
# Safe by construction:
#   - Archived VERBATIM, including the "- [x]" marker, under a "## <id> — <slug>"
#     heading. That heading is the idempotency key: a row already present is
#     re-confirmed, never duplicated.
#   - Never rewrites INDEX.md. The only file this script writes is the archive.
#   - Reversible — everything is git-tracked; `git diff` shows what moved.
#
# Exit codes:
#   0  clean (nothing to archive, no row over budget)
#   1  no specs/ directory found
#   2  usage error (unknown arg, non-numeric --max-bytes)
#   3  REFUSED — INDEX.md has no "## Specs" heading, or a row's id does not parse.
#      Nothing was written. A malformed archive entry is worse than no entry, and
#      this is distinct from 1/2 so a test asserting the refusal cannot pass by
#      the script dying of an unrelated fault.
#   4  OVER BUDGET — rows exceed --max-bytes. The writes still happened: refusing
#      to archive because a row is too long would leave MORE bytes inline than
#      completing the run does, which is the opposite of the point. Same
#      deliberate 3-versus-4 split as archive-spec-history.sh.
#
#   Precedence: 3 BEATS 4. A refused file wrote nothing, so any byte figure would
#   describe a register the caller does not have.
#
# Usage:
#   scripts/archive-completed-rows.sh                  # archive + report, budget 300
#   scripts/archive-completed-rows.sh --dry-run        # report only, write nothing
#   scripts/archive-completed-rows.sh --max-bytes 400  # loosen the budget
#   scripts/archive-completed-rows.sh --max-bytes 0    # disable the budget check
#   scripts/archive-completed-rows.sh --pending        # report only unstarted rows
#   scripts/archive-completed-rows.sh --completed      # report only completed rows
#   scripts/archive-completed-rows.sh --dir path/to/specs
#
# Requires python3, as scripts/spec_active.py already does for the same machinery.

set -eu

MAX_BYTES=300
SPECS_DIR=""
DRY_RUN=0
WRITE_PENDING=0
SCOPE="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --max-bytes) MAX_BYTES="${2:?--max-bytes needs a number}"; shift 2 ;;
    --dir) SPECS_DIR="${2:?--dir needs a path}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    # Row 009. Opt-in, so the default stays hands-off and FR-10 still holds.
    --write-pending) WRITE_PENDING=1; shift ;;
    --pending) SCOPE="pending"; shift ;;
    --completed) SCOPE="completed"; shift ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Same shape as archive-spec-history.sh's check, deliberately: a leading '-' lands
# in the [!0-9] class, so a negative budget is rejected here rather than silently
# flagging every row.
case "$MAX_BYTES" in ''|*[!0-9]*) echo "--max-bytes must be a non-negative integer (0 disables the check)" >&2; exit 2 ;; esac

# Locate the specs dir: explicit --dir, else ./specs, else walk up to a repo root.
if [ -z "$SPECS_DIR" ]; then
  if [ -d "./specs" ]; then
    SPECS_DIR="./specs"
  else
    d="$PWD"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
      if [ -d "$d/specs" ]; then SPECS_DIR="$d/specs"; break; fi
      [ -d "$d/.git" ] && break
      d=$(dirname "$d")
    done
  fi
fi
[ -n "$SPECS_DIR" ] && [ -d "$SPECS_DIR" ] || { echo "no specs/ dir found (use --dir)" >&2; exit 1; }

SPECS_DIR="$SPECS_DIR" MAX_BYTES="$MAX_BYTES" DRY_RUN="$DRY_RUN" SCOPE="$SCOPE" WRITE_PENDING="$WRITE_PENDING" python3 - <<'PY'
import os, re, sys

specs = os.environ["SPECS_DIR"]
max_bytes = int(os.environ["MAX_BYTES"])
dry_run = os.environ["DRY_RUN"] == "1"
write_pending = os.environ.get("WRITE_PENDING") == "1"
scope = os.environ["SCOPE"]

index = os.path.join(specs, "INDEX.md")
completed = os.path.join(specs, "INDEX.completed.md")
pending = os.path.join(specs, "INDEX.pending.md")

if not os.path.isfile(index):
    print(f"no {index}", file=sys.stderr); sys.exit(1)

text = open(index, encoding="utf-8").read()
lines = text.split("\n")

# The row region is everything below the "## Specs" heading. Without it we cannot
# tell a spec row from a bullet in the prose header, and guessing produces archive
# entries for things that are not rows — worse than not running.
start = None
for i, l in enumerate(lines):
    if re.match(r"^##\s+Specs\s*$", l):
        start = i + 1
        break

if start is not None:
    # The region ends at the next "## " heading (the history section), or EOF.
    end = len(lines)
    for i in range(start, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    regions = [(start, end)]
else:
    # No "## Specs" heading. A register may legitimately group its rows under
    # milestone headings instead of one flat list -- rocky has done so since its
    # first commit, and this script refused it on every invocation for as long as
    # it has been synced there, while that register grew to 359 KB with 62 of its
    # 123 rows sitting in an INLINE "## Archives" section. Refusing was the safe
    # default when the alternative was guessing, but it is not the only safe
    # option: ROW_RE below already discriminates a row from a prose bullet by
    # shape, which is the job the heading was standing in for. On rocky, 193
    # bullets, 123 rows -- the regex tells them apart without help.
    #
    # So: take the whole file as row region, minus the history section, which is
    # the one place a bullet can look enough like a row to matter and the one
    # section that must never be archived by THIS script (archive-spec-history.sh
    # owns it). An "## Archives" section is deliberately NOT excluded -- rows
    # parked there are precisely what this script exists to move out of the file.
    hist = len(lines)
    for i, l in enumerate(lines):
        if re.match(r"^##\s+(Register history|Scenario history)\b", l):
            hist = i
            break
    regions = [(0, hist)]

start, end = regions[0]

# One regex for a row. This script only reads ids, it never resolves them, so it
# does not import spec_active; but it must not DISAGREE with it about what an id
# looks like, which is why the shapes are pinned rather than left as \S+.
#
# The comment that stood here claimed these WERE spec_active.py's shapes. It was
# wrong in both directions, and each error cost a project its archiver outright:
#
#   * the numeric form read \d{3}[a-z]* and so rejected rocky's dotted sub-specs
#     (501.1, 450.7) -- 22 of 123 rows;
#   * the letter-led form read H\d+[a-z]*, i.e. checkpoints ONLY, while
#     spec_active.py's ALPHA_ID_RE reads [A-Za-z]+[0-9]+[A-Za-z0-9]* -- any
#     letter-led id. agentcrm's S-rows are well-formed by that grammar and
#     validate-register-ids.sh passes them, yet this script refused the whole
#     register on the first one, so nothing had ever been archived there.
#
# Both are the same mistake: a copy of a grammar that then drifted from it in
# silence. The shapes below are transcribed from spec_active.py directly, and
# scripts/test-archive-completed-rows.sh now asserts a letter-led id is accepted,
# so the next divergence is a red test rather than an inert archiver.
ROW = re.compile(r"^- \[([ x/!])\] (\S+) — (.*)$")
ID_OK = re.compile(r"^(?:[0-9]+(?:\.[0-9]+)*[a-z]*|[A-Za-z]+[0-9]+[A-Za-z0-9]*)$")

rows = []
for i in range(start, end):
    l = lines[i]
    if not l.startswith("- ["):
        # A blank line or a note among the rows. Ignored, not refused: unlike the
        # history region — where a foreign line means a ledger block was swept
        # into an archive — a note among rows costs nothing, and refusing would be
        # brittle for no gain.
        continue
    m = ROW.match(l)
    if not m:
        print(f"REFUSED: {index}:{i+1} looks like a row but does not parse: {l[:80]!r}", file=sys.stderr)
        sys.exit(3)
    status, rid, rest = m.group(1), m.group(2), m.group(3)
    # A register may bold its id (`- [/] **404e — ...`). spec_active.py's patterns
    # strip the markers with a leading `\**`; this one captured them into the id
    # and then refused the row. Same class as the two grammar mismatches above:
    # a second reader of the same field, normalising it differently.
    rid = rid.strip("*")
    if not ID_OK.match(rid):
        print(f"REFUSED: {index}:{i+1} id {rid!r} is not a spec id (NNN[a-z]* or HN[a-z]*)", file=sys.stderr)
        sys.exit(3)
    slug = rest.split(" — ")[0].strip()
    rows.append({"line": i + 1, "status": status, "id": rid, "slug": slug,
                 "text": l, "bytes": len(l.encode("utf-8"))})

def sections(path):
    """Ids that already have a '## <id> — ...' section in an archive."""
    if not os.path.isfile(path):
        return set()
    return set(re.findall(r"^##\s+(\S+)\s+—", open(path, encoding="utf-8").read(), re.M))

in_completed = sections(completed)
in_pending = sections(pending)

# --- archive completed rows -------------------------------------------------
# Idempotent by '## <id>' membership. An archived row that was later EDITED
# inline is reported, never re-archived: the archive is the record of what the
# row said when it was ticked, and silently updating it loses the thing it exists
# to hold. Inline drift afterwards (a typo fix, a cross-reference) is legitimate,
# which is why membership is on presence, not on text equality.
to_archive = [r for r in rows if r["status"] == "x" and r["id"] not in in_completed]

if to_archive and not dry_run:
    if not os.path.isfile(completed):
        print(f"REFUSED: {completed} does not exist — create it before archiving", file=sys.stderr)
        sys.exit(3)
    body = open(completed, encoding="utf-8").read().rstrip("\n")
    for r in to_archive:
        body += f"\n\n## {r['id']} — {r['slug']}\n\n{r['text']}"
    open(completed, "w", encoding="utf-8").write(body + "\n")
    in_completed |= {r["id"] for r in to_archive}

if to_archive:
    verb = "would archive" if dry_run else "archived"
    print(f"{verb} {len(to_archive)} completed row(s) to {os.path.basename(completed)}: "
          + ", ".join(r["id"] for r in to_archive))
else:
    print(f"{os.path.basename(completed)}: up to date "
          f"({sum(1 for r in rows if r['status'] == 'x')} completed rows, all archived)")

# --- budget report ----------------------------------------------------------
over = []
if max_bytes > 0:
    for r in rows:
        if r["bytes"] <= max_bytes:
            continue
        if scope == "pending" and r["status"] == "x":
            continue
        if scope == "completed" and r["status"] != "x":
            continue
        over.append(r)

# Row 009. The archiver wrote INDEX.completed.md and never INDEX.pending.md, by
# design (FR-10) -- and the consequence is that an OPEN row over budget is told
# "write a pending entry by hand before shortening", which nobody does. rocky ran
# 47 such rows and a 127 KB register that is read on every spec. The default is
# unchanged, so FR-10's test still holds; --write-pending is the opt-in that
# makes the advice executable.
if write_pending and not dry_run:
    need = [r for r in rows
            if r["status"] in (" ", "!") and r["id"] not in in_pending
            and r["bytes"] > max_bytes]
    if need:
        if not os.path.isfile(pending):
            print(f"REFUSED: {pending} does not exist — create it before archiving", file=sys.stderr)
            sys.exit(3)
        body = open(pending, encoding="utf-8").read().rstrip("\n")
        add = ""
        for r in need:
            # '## <id> — <slug>', the shape sections() indexes on. Writing the id
            # alone makes the entry invisible to the membership check, so the next
            # run archives it again -- caught by the idempotence assertion.
            add += (f"\n\n## {r['id']} — {r['slug']}\n\n_Diagnosis moved here; the register "
                    f"row is now a pointer. Verbatim:_\n\n{r['text']}\n")
        open(pending, "w", encoding="utf-8").write(body + add + "\n")
        print(f"archived {len(need)} open row(s) to {os.path.basename(pending)}: "
              + ", ".join(r["id"] for r in need))
        for r in need:
            in_pending.add(r["id"])

if over:
    print(f"\n{len(over)} row(s) over {max_bytes} bytes in {os.path.basename(index)}:")
    for r in over:
        preserved = r["id"] in in_completed or r["id"] in in_pending
        where = "INDEX.completed.md" if r["id"] in in_completed else "INDEX.pending.md"
        if preserved:
            note = f"shortenable — diagnosis is in {where}"
        elif r["status"] == "x":
            # Only reachable under --dry-run: a live run archives it above.
            note = "archive first — run without --dry-run"
        else:
            note = "archive first — no INDEX.pending.md entry; write one before shortening"
        print(f"  {index}:{r['line']}  {r['bytes']:5d} B  [{r['status']}] {r['id']:<7} {note}")
    print("\nPreserve first, shorten second. A row is only safe to rewrite once its long form is archived.")
    sys.exit(4)

if max_bytes > 0:
    scoped = "" if scope == "all" else f" ({scope} rows)"
    print(f"{os.path.basename(index)}: no row over {max_bytes} bytes{scoped}")
PY
