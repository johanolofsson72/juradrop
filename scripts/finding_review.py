#!/usr/bin/env python3
"""finding_review.py — present open findings with the evidence for their need, checked (row 077).

A proposal to add a register row used to arrive as one line of text. The developer then had to work
out for themselves whether the need was real, whether a row already covered it, and whether the file
it complained about still existed. This does that groundwork before the question is asked. It does
not decide anything: approve and decline are the developer's (`finding.sh --approve / --decline`).

Three checks per finding, each one reported and none of them a gate:
  overlap  the open register row with the most shared distinctive words (Jaccard >= 0.25). A cheap
           lexical signal; semantic search stays with register-similarity.sh, which needs Ollama.
  cited    every path-like token (contains '/', ends in a known extension) that does not exist under
           the repo root. A citation that is gone means the evidence needs re-checking. Tokens with
           '..', or starting with '/' or '~', are refused rather than resolved, so a finding cannot
           probe outside the repo.
  verdict  for a proposal: evidenced · no evidence · possible duplicate of <id> · cites a missing file.

Env: ROOT, LEDGER, REG. Arg: --proposals limits the output to proposals.
"""
import datetime
import os
import re
import sys

CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def clean(s, limit=600):
    # Ledger text is data another lane wrote: no terminal escapes, and bounded before it is printed.
    return CONTROL.sub("?", s)[:limit]

FINDING = re.compile(r"^- \[ \] (F\d{3,}) — (\w+) — (\d{4}-\d{2}-\d{2})(?: · from spec (\S+))? — (.*)$")
OPEN_ROW = re.compile(r"^- \[[ /!]\] (\S+) — (.*)$")
PATHLIKE = re.compile(r"[\w.\-]*/[\w./\-]*\.(?:sh|py|md|json|mjs|js|ts|tsx|cs|yml|yaml|dart)\b")
WORD = re.compile(r"[a-zåäö][a-zåäö\-]{4,}")
STOP = {"which", "their", "there", "these", "those", "would", "could", "should", "about", "after",
        "before", "every", "never", "still", "where", "while", "being", "other", "until", "because",
        "spec", "specs", "register", "finding", "findings", "diagnosis", "diagnos", "track", "only"}
OVERLAP_AT = 0.25


def words(text):
    return {w for w in WORD.findall(text.lower()) if w not in STOP}


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    root = os.environ.get("ROOT", ".")
    ledger = os.environ.get("LEDGER", os.path.join(root, "specs", "FINDINGS.md"))
    reg = os.environ.get("REG", os.path.join(root, "specs", "INDEX.md"))
    only_proposals = "--proposals" in sys.argv[1:]

    if not os.path.isfile(ledger):
        print("no findings recorded")
        return 0
    rows = []
    if os.path.isfile(reg):
        for l in open(reg, encoding="utf-8", errors="replace"):
            m = OPEN_ROW.match(l.rstrip("\n"))
            if m:
                rows.append((m.group(1), words(m.group(2))))

    today = datetime.date.today()
    shown = 0
    for l in open(ledger, encoding="utf-8", errors="replace"):
        m = FINDING.match(l.rstrip("\n"))
        if not m:
            continue
        fid, kind, date, spec, rest = m.groups()
        if only_proposals and kind != "proposal":
            continue
        text, _, need = rest.rpartition(" — need: ") if " — need: " in rest else (rest, "", "")
        shown += 1
        try:
            age = (today - datetime.date.fromisoformat(date)).days
        except ValueError:
            age = -1

        fw = words(text + " " + need)
        best, best_j = None, 0.0
        for rid, rw in rows:
            if not fw or not rw:
                continue
            j = len(fw & rw) / len(fw | rw)
            if j > best_j:
                best, best_j = rid, j

        missing, refused = [], []
        for p in sorted(set(PATHLIKE.findall(text + " " + need))):
            if ".." in p.split("/") or p.startswith(("/", "~")):
                refused.append(p)
            elif not os.path.realpath(os.path.join(root, p)).startswith(os.path.realpath(root) + os.sep):
                refused.append(p)  # a committed symlink pointing out of the repo
            elif not os.path.exists(os.path.join(root, p)):
                missing.append(p)

        if kind == "proposal":
            if not need.strip():
                verdict = "no evidence — ask for it before deciding"
            elif best_j >= OVERLAP_AT:
                verdict = "possible duplicate of %s — check before approving" % best
            elif missing:
                verdict = "cites a missing file — re-check the evidence"
            else:
                verdict = "evidenced"
        else:
            verdict = "finding (decided at the 5-spec review)"

        print("%s  %s  %s d old%s" % (fid, kind, age, " · spec %s" % spec if spec else ""))
        print("    what:    %s" % clean(text))
        if kind == "proposal":
            print("    need:    %s" % (clean(need) or "(none given)"))
        if best is not None and best_j >= OVERLAP_AT:
            print("    overlap: row %s (%.2f)" % (best, best_j))
        if missing:
            print("    cited but missing here: %s" % clean(", ".join(missing)))
        if refused:
            print("    cited paths refused (outside the repo): %s" % clean(", ".join(refused)))
        print("    verdict: %s" % verdict)
    if shown == 0:
        print("no open proposals" if only_proposals else "no open findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
