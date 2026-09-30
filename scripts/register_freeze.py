#!/usr/bin/env python3
"""register_freeze.py — is the register frozen, and has anything slipped in? (row 077)

On 2026-09-29 the developer answered a convergence stop (ratio 3.80) with a FREEZE: no new rows until
open rows fall below a target, and a new row only when the developer approved a proposal for it. The
freeze is one header line in specs/INDEX.md, so both lanes and every hook read the same thing:

    Freeze: since 2026-09-29 · last row 077 · lifts below 40 open · ...

WHAT COUNTS AS "ADDED DURING THE FREEZE". Every row id that was not in the register when the freeze
line was committed. The baseline comes from git (the commit that introduced the line), so a carved
suffix (077b), a hand-typed id or an oddly shaped row are all caught, not only ids numerically above
`last row`. Outside git, or before the freeze line is committed, it falls back to the number:
a numeric head above `last row`, or any suffix on `last row` itself. H rows are exempt: the
checkpoint cadence mandates them.

A new row is legitimate only when it carries `approved F<nnn>`, FINDINGS.md resolves F<nnn> as an
approved PROPOSAL, and no other new row already used that approval. The tag alone is not trusted.

Called as `register-convergence.sh --freeze` (env REG, FINDINGS). Kept out of that script because
three test harnesses read it through heredocs.

Exit: 0 frozen and clean · 1 no freeze · 2 frozen with unapproved rows · 3 frozen, below target (can lift)
      4 unreadable register, malformed or duplicated freeze line, or an internal error. It never exits 1
      by accident: an error here must not read as "no freeze", which would silently lift it.
"""
import os
import re
import subprocess
import sys

ANY_ROW = re.compile(r"^- \[(.)\] (\S+)")
OPEN_ROW = re.compile(r"^- \[[ /!]\] ")
FREEZE_ANY = re.compile(r"(?i)^\W*freeze\W")
FREEZE = re.compile(r"^Freeze: since (\d{4}-\d{2}-\d{2}) · last row (\d{1,6}) · lifts below (\d{1,6}) open")
APPROVED_TAG = re.compile(r"approved (F\d{3,6})")
APPROVED_FINDING = re.compile(r"^- \[x\] (F\d{3,6}) — proposal — .*→\s*approved as a register row\s*$")
CHECKPOINT = re.compile(r"^H\d+[a-z]*$")
NUMERIC_HEAD = re.compile(r"^(\d{1,6})(.*)$")


def read(path):
    return open(path, encoding="utf-8", errors="replace").read().split("\n")


def ids(lines):
    return [m.group(2) for m in (ANY_ROW.match(l) for l in lines) if m]


def baseline_ids(reg, since):
    """Row ids in the register as of the OLDEST commit carrying `Freeze: since <since>`, or None.

    Searched on the date, never on the whole line: editing the target (40 -> 35) or `last row` must
    not move the baseline forward and silently legitimise every row added in between."""
    d = os.path.dirname(os.path.abspath(reg)) or "."
    try:
        top = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        if not top:
            return None
        rel = os.path.relpath(os.path.abspath(reg), top)
        shas = subprocess.run(["git", "-C", top, "log", "--format=%H", "-G", "^Freeze: since %s " % re.escape(since), "--", rel],
                              capture_output=True, text=True, timeout=30).stdout.split()
        if not shas:
            return None
        blob = subprocess.run(["git", "-C", top, "show", "%s:%s" % (shas[-1], rel)],
                              capture_output=True, timeout=10)
        if blob.returncode != 0:
            return None
        return set(ids(blob.stdout.decode("utf-8", "replace").split("\n")))
    except (OSError, subprocess.SubprocessError):
        return None


def added_by_number(rid, last):
    m = NUMERIC_HEAD.match(rid)
    if not m:
        return True  # an id this rule cannot place is reported, never waved through
    n, suffix = int(m.group(1)), m.group(2)
    return n > last or (n == last and suffix != "")


def main():
    try:  # Git Bash on a cp1252 console cannot print every character a register holds
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    reg = os.environ.get("REG", "specs/INDEX.md")
    findings = os.environ.get("FINDINGS", os.path.join(os.path.dirname(reg), "FINDINGS.md"))
    try:
        lines = read(reg)
    except OSError as e:
        print("register-freeze: cannot read %s (%s)" % (reg, e.__class__.__name__))
        return 4

    freeze_at = [i for i, l in enumerate(lines) if FREEZE_ANY.match(l)]
    if not freeze_at:
        print("register-freeze: off")
        return 1
    # Exactly one canonical line: a second one (or a near-miss like `**Freeze:**`) could override the
    # real one. The line text is never echoed -- this output reaches the model through the SessionStart
    # banner, and register text another lane wrote is data, not something to quote into context.
    if len(freeze_at) > 1:
        print("register-freeze: MALFORMED — %d freeze lines (specs/INDEX.md:%s); keep exactly one"
              % (len(freeze_at), ",".join(str(i + 1) for i in freeze_at)))
        return 4
    m = FREEZE.match(lines[freeze_at[0]])
    if not m:
        print("register-freeze: MALFORMED freeze line at specs/INDEX.md:%d — expected "
              "'Freeze: since YYYY-MM-DD · last row NNN · lifts below N open'" % (freeze_at[0] + 1))
        return 4
    since, last, target = m.group(1), int(m.group(2)), int(m.group(3))

    approved = set()
    try:
        for l in read(findings):
            a = APPROVED_FINDING.match(l)
            if a:
                approved.add(a.group(1))
    except OSError:
        pass

    base = baseline_ids(reg, since)
    open_rows = sum(1 for l in lines if OPEN_ROW.match(l))
    unapproved, used = [], set()
    for l in lines:
        r = ANY_ROW.match(l)
        if not r:
            continue
        rid = r.group(2)
        if CHECKPOINT.match(rid):
            continue
        new = (rid not in base) if base is not None else added_by_number(rid, last)
        if not new:
            continue
        ok = [t for t in APPROVED_TAG.findall(l) if t in approved and t not in used]
        if ok:
            used.add(ok[0])  # one approval admits one row
        else:
            unapproved.append(re.sub(r"[^0-9A-Za-z.\-]", "?", rid)[:20])

    head = "register-freeze: ON since %s — %d open, lifts below %d" % (since, open_rows, target)
    if unapproved:
        print("%s · %d row(s) added without an approved proposal: %s" % (head, len(unapproved), ", ".join(unapproved)))
        return 2
    if open_rows < target:
        print("%s · %d open is below %d: the freeze can lift (delete the Freeze line in specs/INDEX.md)"
              % (head, open_rows, target))
        return 3
    print("%s · no unapproved rows since %03d" % (head, last))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 — any crash must read as "unknown", never as "off" (exit 1)
        print("register-freeze: ERROR %s — freeze state unknown, treat as frozen" % e.__class__.__name__)
        sys.exit(4)
