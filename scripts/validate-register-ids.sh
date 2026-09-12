#!/usr/bin/env bash
# Gate: every id in specs/INDEX.md must be one the resolver can classify (row H7b), and must name
# exactly one row and at most one spec directory (row 007ch).
#
# WHY THIS EXISTS
# ---------------
# scripts/spec_active.py's id grammar drifted away from the register's own naming convention and nothing
# noticed for 18 days. 69 of 114 rows classified "unparseable", both PreToolUse guards answer that with
# deny, and 56 of those rows shipped anyway — through Bash, which was not gated. The drift was invisible
# because nothing ever compared the grammar to the register.
#
# That comparison is one loop, and it is this file. A grammar that narrows, or a register row that adopts a
# shape the grammar has not learned, is now a red gate at the next stop instead of a silent denial.
#
# WHY UNIQUENESS IS IN THE SAME LOOP (row 007ch)
# ----------------------------------------------
# An id is a handle: it is what spec_active.py resolves, what the spec directory is named after, and what
# the orientation banner points at. Three ids each named two rows in August 2026 (007cb, 007cc, 007cd),
# and the cost is not untidiness. Both BLOCKING PreToolUse guards resolve the active row's id, glob
# specs/<id>-*, and check what they find — so when the ticked row of a colliding pair owns a complete
# artifact set, the ACTIVE row inherits it. Measured against a control (007ch research.md M4): both
# guards ALLOW a source edit for a spec with zero artifacts and zero interview answers, where the same
# guards on the same fixture without the duplicate DENY it. That is verbatim the bypass spec_active.py's
# own docstring describes for a mis-parsed id, reached with no parser bug at all.
#
# Nor is the row you get "the first one". resolve() sorts the glob and takes the first isdir hit, so which
# spec answers to the id is decided by the alphabet of the SLUG — a field the collision has nothing to do
# with. Hence two checks and not one: duplicate ROWS, and one id matching two DIRECTORIES.
#
# It also PRINTS THE HISTOGRAM every run, pass or fail. The spec's acceptance criteria claim "zero
# unparseable, exactly five checkpoints"; a gate that only says "ok" turns those numbers back into claims.
# The directory count is in there for a sharper reason: a scan that read nothing is otherwise
# indistinguishable from a clean one, which is the failure row 007cd added a per-root file floor for.
#
# Usage:  bash scripts/validate-register-ids.sh
# Env:    REGISTER  override the register path (for scripts/test-register-ids.sh only — the production
#                   callers, scripts/project-maintenance.sh here and scripts/run-gates.sh downstream,
#                   pass nothing, so the gate that gates gates the real file)
#
# Exit: 0 every id classified, unique, and unambiguous · 1 the register is bad — a malformed id, an id on
#         two rows, or an id on two directories (each named, with its lines and paths) ·
#       2 the register could not be read — a DIFFERENT fact from "the register is bad", and the two must
#         not share an exit code (the H6y/H6s lesson, and the defect this row's own guards had)
#
# Covers: SC-1428 SC-1429 SC-1430 SC-1443

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTER_PATH="${REGISTER:-$REPO_ROOT/specs/INDEX.md}"

if [ ! -f "$REGISTER_PATH" ]; then
  echo "validate-register-ids: register not found: $REGISTER_PATH" >&2
  exit 2
fi

REGISTER_PATH="$REGISTER_PATH" HOOK_DIR="$SCRIPT_DIR" python3 <<'PY'
import glob
import os
import sys

sys.path.insert(0, os.environ["HOOK_DIR"])
try:
    from spec_active import ROW_RE, classify_id, _kind_for
except Exception as exc:                                    # noqa: BLE001
    print("validate-register-ids: cannot import the resolver: %s" % exc, file=sys.stderr)
    sys.exit(2)

path = os.environ["REGISTER_PATH"]
try:
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        lines = fh.readlines()
except OSError as exc:
    print("validate-register-ids: cannot read %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(2)

counts = {"spec": 0, "checkpoint": 0, "unparseable": 0}
bad = []
lines_by_id = {}
rows = 0

for lineno, line in enumerate(lines, 1):
    m = ROW_RE.match(line.rstrip())
    if not m:
        continue
    rows += 1
    _status, raw_id, _slug, track_field = m.groups()
    parts = raw_id.strip().split()
    token = parts[0] if parts else ""
    ident, shape = classify_id(token)
    kind = _kind_for(shape, track_field)
    counts[kind] = counts.get(kind, 0) + 1
    if kind == "unparseable":
        bad.append((lineno, token))
    else:
        # Malformed ids are deliberately NOT compared for uniqueness. They have no usable glob, so
        # "two rows share it" names no consequence to act on, and stacking a second complaint onto a
        # row that already has one buries the actionable half.
        lines_by_id.setdefault(ident, []).append(lineno)

# A register with no rows at all is not "clean" — it is a register this gate cannot speak about, which is
# the same class of answer as an unreadable file.
if rows == 0:
    print("validate-register-ids: %s parsed, but it holds ZERO register rows." % path, file=sys.stderr)
    print("  Nothing was checked. That is not a pass.", file=sys.stderr)
    sys.exit(2)

duplicate_rows = sorted((ident, nums) for ident, nums in lines_by_id.items() if len(nums) > 1)

# The tree root is derived from the register, not from this script's location, so REGISTER= points the
# WHOLE gate at a fixture rather than half of it. It is only claimed when the register sits in a
# directory actually named `specs`: anywhere else there is no tree to speak about, and guessing one
# would let a bare fixture file glob against whatever happens to sit two levels up.
register_dir = os.path.dirname(os.path.abspath(path))
tree_root = os.path.dirname(register_dir) if os.path.basename(register_dir) == "specs" else None

dirs_by_id = {}
dirs_matched = 0
if tree_root is not None:
    # Both roots, because resolve() globs both. Checking one would leave the other silently ambiguous,
    # which is this gate's own failure mode in miniature.
    for ident in lines_by_id:
        hits = sorted(
            candidate
            for root in (os.path.join(tree_root, "specs"), os.path.join(tree_root, ".specify", "specs"))
            for candidate in glob.glob(os.path.join(root, "%s-*" % ident))
            if os.path.isdir(candidate))
        if hits:
            dirs_by_id[ident] = hits
            dirs_matched += len(hits)

ambiguous_dirs = sorted((ident, hits) for ident, hits in dirs_by_id.items() if len(hits) > 1)

tree_note = "" if tree_root is not None else " (no specs/ tree beside the register)"

print("Register: %s" % path)
print("Rows: %d  |  spec: %d  checkpoint: %d  unparseable: %d"
      % (rows, counts["spec"], counts["checkpoint"], counts["unparseable"]))
print("Ids: %d distinct  |  duplicate ids: %d  |  spec dirs matched: %d%s  ambiguous dirs: %d"
      % (len(lines_by_id), len(duplicate_rows), dirs_matched, tree_note, len(ambiguous_dirs)))

if not bad and not duplicate_rows and not ambiguous_dirs:
    print("PASS — every row id is classifiable, names one row, and names at most one directory.")
    sys.exit(0)

say = lambda text="": print(text, file=sys.stderr)          # noqa: E731

if bad:
    say()
    say("FAIL — %d row id(s) the resolver cannot classify:" % len(bad))
    for lineno, token in bad:
        say("  %s:%d   id token: %r" % (path, lineno, token))
    say()
    say("Both PreToolUse pipeline guards answer an unclassifiable ACTIVE row with deny, and the deny is")
    say("correct — without a usable id there is no way to tell whether the row owes artifacts. So this is")
    say("not a cosmetic complaint: any of the rows above becomes a total edit block the moment it goes")
    say("active.")
    say()
    say("The grammar is in scripts/spec_active.py:")
    say("  NUMERIC_ID_RE  ^[0-9]+[a-z]*$              007, 007m, 007ab")
    say("  ALPHA_ID_RE    ^[A-Za-z]+[0-9]+[A-Za-z0-9]*$   H1, H6a, H6s2, F2b")
    say()
    say("Fix the row, or — if the token IS the house convention and the grammar is what is behind —")
    say("widen the grammar and add the case to scripts/test-register-ids.sh so it cannot narrow again.")

if duplicate_rows:
    say()
    say("FAIL — %d id(s) name more than one register row:" % len(duplicate_rows))
    for ident, nums in duplicate_rows:
        say("  %s   rows at %s" % (ident, ", ".join("%s:%d" % (path, n) for n in nums)))
    say()
    say("An id is a handle, not a label. Both BLOCKING PreToolUse guards resolve the ACTIVE row's id and")
    say("then check the artifacts of whatever directory it globs. So when one row of a colliding pair is")
    say("ticked and owns a full artifact set, the other row inherits it — and both guards then")
    say("approve a source edit for a spec with no spec.md, no plan.md and no interview at all.")
    say()
    say("Fix: renumber the LATER row of each pair. Ids are handles, so moving the later one keeps the")
    say("ordered block's numbering intact — which is what row 007cb did for 007cb/007cc/007cd.")

if ambiguous_dirs:
    say()
    say("FAIL — %d id(s) match more than one spec directory:" % len(ambiguous_dirs))
    for ident, hits in ambiguous_dirs:
        say("  %s" % ident)
        for hit in hits:
            say("      %s" % os.path.relpath(hit, tree_root))
    say()
    say("spec_active.resolve() sorts this glob and takes the first directory that exists, so which spec")
    say("answers to the id is decided by the alphabet of the SLUG — not by register order, and not by")
    say("anything a reader would predict. Everything downstream inherits that pick: .specify/feature.json,")
    say("the orientation banner, and both artifact guards.")
    say()
    say("Fix: renumber the later row and rename its directory to match, so one id names one directory.")

sys.exit(1)
PY
