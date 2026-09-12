#!/usr/bin/env python3
"""Who holds which register row, what is unclaimed, and what is waiting on an answer.

THE one implementation. `lane-orientation-hook.sh` renders `--brief` at session start;
`lane-status.sh` renders `--full` when somebody asks "is there anything for me to do?".
Two readers of one register that could disagree about who owns what is the failure
`.claude/rules/spec-register.md` names, so there is exactly one parser and both callers
go through it.

It deliberately does NOT answer "which spec is active" — `spec_active.py` owns that, and
its answer is what the PreToolUse guards enforce. This answers a different question: what
does the OTHER lane hold, what is unclaimed, and what is waiting on somebody outside the
repo.

WHY IT EXISTS. On a project with two developers on two machines, the only channel between
the sessions was a human pasting one session's output into the other's prompt. Git already
carries the register, the pending diagnoses and the open questions; nothing read the other
lane's half at session start, so a finding made on one machine stayed invisible on the
other until somebody quoted it by hand.

SINGLE-LANE PROJECTS PAY NOTHING. `--brief` prints only when the register actually carries
an owner tag — no tags, no output, and the session start looks exactly as it did before.
That mirrors the additive lane logic in `.claude/rules/spec-register.md`: with SPEC_OWNER
unset, everything behaves as it did with one developer. `--full` still answers on a
single-lane project, because "what should I work on" is a fair question with one developer
too.

Sources, all files git already carries between machines:

    specs/INDEX.md          rows, states, owner tags, `needs` dependencies
    <questions file>        open questions + the line naming the row each one blocks
    specs/PHASE-DEBT.md     deferrals owed later (only where a project keeps one)
    git log                 who committed what, and when

Exit 0 always. Nothing here may break a session start.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

ROW = re.compile(r"^- \[([ x/!])\] ([0-9]{3}[a-z]*|[A-Z][0-9]+[a-z]*) — ([^\s—]+)")
OWNER = re.compile(r"@([a-z][a-z0-9_-]*)\s*$")
NEEDS = re.compile(r"needs ([0-9A-Za-z, ]+?)(?: —|$)")

# The "what does this question hold up" line. English is the template's own spelling;
# the Swedish alternates are accepted because the project this was extracted from writes
# its customer-facing question file in Swedish, and a parser that only reads one language
# would silently report "no open questions" on a file full of them — the empty result that
# looks like good news (.claude/rules/mutation-timeouts.md, trap 4).
BLOCKS = re.compile(r"\*\*(?:Blocks|Blockerar):\*\*\s*(.+)")
BLOCK_ID = re.compile(r"(?:register row|registerrad) ([0-9]{3}[a-z]*|[A-Z][0-9]+[a-z]*)")

# A project keeps its open questions wherever it keeps them. First match wins; none of
# them existing is normal and silent.
QUESTION_FILES = (
    "QUESTIONS.md",
    "questions.md",
    "OPEN-QUESTIONS.md",
    "fragor.md",
    "specs/QUESTIONS.md",
)


def read(root: str, path: str) -> str:
    try:
        with open(os.path.join(root, path), encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def questions_text(root: str) -> str:
    for name in QUESTION_FILES:
        text = read(root, name)
        if text:
            return text
    return ""


def parse_rows(register: str) -> list[dict]:
    """Rows from the ## Specs list only.

    The history section is an audit trail and is never pipeline input — reading it here
    would put every archived line into every session's context, the cost
    `.claude/rules/spec-register.md` names under "Keep the register lean".
    """
    body = register.split("## Register history")[0]
    rows = []
    for line in body.splitlines():
        m = ROW.match(line)
        if not m:
            continue
        owner = OWNER.search(line)
        needs = NEEDS.search(line)
        rows.append(
            {
                "state": m.group(1),
                "id": m.group(2),
                "slug": m.group(3),
                "owner": owner.group(1) if owner else None,
                "needs": [d.strip() for d in needs.group(1).split(",") if d.strip()]
                if needs
                else [],
            }
        )
    return rows


def parse_questions(text: str, ticked: set[str]) -> tuple[list[tuple[str, str, str]], list[str]]:
    """(number, title, rows-still-open) per question, plus the unmapped question numbers.

    A question with no Blocks line is returned as unmapped rather than dropped. An
    enumeration that silently skips what it cannot parse reports a clean project and a
    broken one identically.
    """
    waiting, unmapped = [], []
    for block in re.split(r"^## ", text, flags=re.M)[1:]:
        title = block.splitlines()[0].strip()
        num = re.match(r"(\d+)\.\s*(.*)", title)
        if not num:
            continue
        line = BLOCKS.search(block)
        if not line:
            unmapped.append(num.group(1))
            continue
        live = [i for i in BLOCK_ID.findall(line.group(1)) if i not in ticked]
        if live:
            waiting.append((num.group(1), num.group(2), ", ".join(live)))
    return waiting, unmapped


def recent_commits(root: str, days: int) -> list[tuple[str, str, str]]:
    try:
        out = subprocess.run(
            ["git", "-C", root, "log", f"--since={days} days ago",
             "--format=%an\t%ar\t%s", "--no-merges", "-n", "40"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if out.returncode != 0:
        return []
    rows = []
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append((parts[0], parts[1], parts[2]))
    return rows


def behind_count(root: str) -> int:
    """Commits on the upstream default branch this machine does not have.

    Reads the ref already on disk — no fetch. `template-autosync-hook.sh` has been to the
    network this session already, and a stale ref reporting 0 says nothing false.
    """
    for ref in ("origin/main", "origin/master"):
        try:
            check = subprocess.run(["git", "-C", root, "rev-parse", "--verify", "-q", ref],
                                   capture_output=True, text=True, timeout=10)
            if check.returncode != 0:
                continue
            out = subprocess.run(["git", "-C", root, "rev-list", "--count", f"HEAD..{ref}"],
                                 capture_output=True, text=True, timeout=10)
            if out.returncode == 0:
                return int(out.stdout.strip() or 0)
        except (OSError, ValueError, subprocess.SubprocessError):
            return 0
    return 0


def phase_debt_open(root: str) -> int:
    """Rows in the ## Open table of specs/PHASE-DEBT.md, where a project keeps one."""
    text = read(root, "specs/PHASE-DEBT.md")
    if not text:
        return 0
    count, in_open = 0, False
    for line in text.splitlines():
        if line.startswith("## Open"):
            in_open = True
            continue
        if line.startswith("## "):
            in_open = False
        if in_open and line.startswith("|"):
            if re.match(r"\|\s*(Row|-{2,}|:?-)", line) or "none yet" in line:
                continue
            count += 1
    return count


def runnable(rows: list[dict], ticked: set[str]) -> list[dict]:
    return [
        r for r in rows
        if r["state"] == " " and not r["owner"]
        and all(d in ticked for d in r["needs"])
    ]


def render(root: str, me: str, full: bool) -> str:
    register = read(root, "specs/INDEX.md")
    if not register:
        return ""

    rows = parse_rows(register)
    if not rows:
        return ""

    # No owner tag anywhere means one developer. The brief then says nothing at all: the
    # CORE orientation hook already prints the next row, and repeating it under a second
    # heading is the noise that teaches people to skip both.
    multi_lane = any(r["owner"] for r in rows)
    if not full and not multi_lane:
        return ""

    ticked = {r["id"] for r in rows if r["state"] == "x"}
    open_rows = [r for r in rows if r["state"] in " /"]
    others = sorted({r["owner"] for r in rows if r["owner"] and r["owner"] != me})

    out: list[str] = []

    if full:
        mine = [r for r in open_rows if r["owner"] == me] if me else []
        if mine:
            r = mine[0]
            verb = "in progress" if r["state"] == "/" else "next up"
            out.append(f"  YOUR ROW: {r['id']} — {r['slug']} ({verb})")
            for extra in mine[1:]:
                out.append(f"            also assigned: {extra['id']} — {extra['slug']}")
        elif multi_lane:
            out.append("  YOUR ROW: none assigned — you are free")

    for who in others:
        theirs = [r for r in open_rows if r["owner"] == who]
        if theirs:
            r = theirs[0]
            verb = "in progress" if r["state"] == "/" else "next up"
            out.append(f"  @{who}: {r['id']} — {r['slug']} ({verb})")
        else:
            out.append(f"  @{who}: no open row assigned")

    free = runnable(rows, ticked)
    if free:
        if full:
            out.append("")
            out.append("  Unclaimed rows whose dependencies are all ticked:")
            for r in free[:8]:
                out.append(f"    {r['id']} — {r['slug']}")
        elif multi_lane:
            out.append("  unclaimed and runnable: " + ", ".join(r["id"] for r in free[:6]))

    if full:
        blocked = [r for r in rows if r["state"] == "!"]
        if blocked:
            out.append("")
            out.append("  Held rows (`- [!]`) — nobody starts one without a decision:")
            for r in blocked:
                who = f" @{r['owner']}" if r["owner"] else ""
                out.append(f"    {r['id']} — {r['slug']}{who}")

    waiting, unmapped = parse_questions(questions_text(root), ticked)
    if waiting:
        out.append("")
        out.append("  Waiting on an answer, and holding an unticked row:")
        for num, title, ids in waiting:
            out.append(f"    question {num} → {ids}" + (f" — {title}" if full else ""))
    if unmapped:
        out.append(f"    no Blocks line: question {', '.join(unmapped)}")

    if full:
        debt = phase_debt_open(root)
        if debt:
            out.append("")
            out.append(f"  Phase debt open: {debt} line(s) in specs/PHASE-DEBT.md.")

        commits = recent_commits(root, 7)
        if commits:
            out.append("")
            out.append("  Last seven days, by author:")
            seen: dict[str, list[tuple[str, str]]] = {}
            for author, when, subject in commits:
                seen.setdefault(author, []).append((when, subject))
            for author, items in seen.items():
                out.append(f"    {author} — {len(items)} commit(s), latest {items[0][0]}:")
                for when, subject in items[:3]:
                    out.append(f"      {subject[:96]}")

    behind = behind_count(root)
    if behind:
        out.append("")
        out.append(f"  upstream is {behind} commit(s) ahead of this machine — pull before you write.")

    if not out:
        return ""

    if me:
        lane = f"LANE: @{me}"
    elif multi_lane:
        lane = "LANE: no SPEC_OWNER set (.claude/settings.local.json)"
    else:
        lane = "REGISTER STATUS"
    return lane + "\n" + "\n".join(out)


def find_root(start: str) -> str:
    d = os.path.abspath(start)
    while d != "/":
        if os.path.exists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return ""


def main() -> int:
    ap = argparse.ArgumentParser(description="Lane status from the spec register.")
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--full", action="store_true",
                    help="the answer to 'is there anything for me to do?'")
    args = ap.parse_args()

    root = find_root(args.root)
    if not root:
        return 0
    me = os.environ.get("SPEC_OWNER", "").strip().lower()
    text = render(root, me, args.full)
    if text:
        print(text)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # a session start must never die on this
        sys.exit(0)
