"""Flag constructs that run on one developer's platform and not the other's.

Two developers, two platforms: Johan on macOS (BSD userland, bash 3.2), David on Linux (GNU, bash 5).
A construct that works on one is a script the other never successfully runs -- and it fails quietly,
because the usual symptom is an empty result rather than an error. On 2026-09-04 agentcrm's
test-order-varied.sh was found enumerating 0 of 135 test classes on macOS because of `find -printf`.
It had worked since the day it was written and had never once run on the other machine.

THE HARD PART IS NOT FINDING TOKENS, IT IS NOT CRYING WOLF. This template is full of CORRECT uses of
platform-specific commands, because the established idiom is to pair them:

    stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0
    date -j -f "%Y-%m-%d" "$S" +%s 2>/dev/null || date -d "$S" +%s 2>/dev/null

Both are portable, and a token matcher flags both. So a hit is a finding only when its counterpart is
absent from a small window -- the line itself plus the next two, which is how every correct pair in
this repo is written. A line ending in `# portability-ok` is a recorded exception.
"""
import os, re, sys

# (label, pattern, counterpart-or-None, advice)
CHECKS = [
    ("mapfile",      re.compile(r"\bmapfile\b"),                    None, "bash 4+; macOS ships bash 3.2. Use a while-read loop."),
    ("readarray",    re.compile(r"\breadarray\b"),                  None, "bash 4+; macOS ships bash 3.2. Use a while-read loop."),
    ("declare -A",   re.compile(r"declare\s+-A\b"),                 None, "bash 4+ associative arrays; macOS ships bash 3.2."),
    ("${v,,}",       re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*,,"),   None, "bash 4+ case conversion. Use tr '[:upper:]' '[:lower:]'."),
    ("${v^^}",       re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*\^\^"), None, "bash 4+ case conversion. Use tr '[:lower:]' '[:upper:]'."),
    ("find -printf", re.compile(r"\bfind\b[^|;]*\s-printf\b"),      None, "GNU find only; BSD find errors and prints nothing. Pipe through sed 's|.*/||'."),
    ("readlink -f",  re.compile(r"\breadlink\s+-f\b"),              None, "GNU only without coreutils on macOS. Use (cd dir && pwd -P)."),
    ("grep -P",      re.compile(r"\bgrep\b[^|;]*\s-[A-Za-z]*P\b"),  None, "GNU grep only. Use grep -E."),
    ("xargs -r",     re.compile(r"\bxargs\b[^|;]*\s-r\b"),          None, "GNU xargs only; BSD xargs already skips an empty list."),
    ("head -n -N",   re.compile(r"\bhead\s+-n\s+-[0-9]"),           None, "GNU head only. Use sed."),
    ("sort -V",      re.compile(r"\bsort\b[^|;]*\s-V\b"),           None, "GNU sort only on older macOS."),
    # `date -r <file>` reads an mtime on BOTH platforms, so it is a legitimate counterpart to either
    # stat form and not merely a second GNU-ism. Accepting it stops the gate flagging a fix that is
    # already correct -- which is how a gate loses its reader.
    ("stat -c",      re.compile(r"\bstat\s+-c\b"),        re.compile(r"stat\s+-f|date\s+-r\b"), "pair it: stat -c %Y f 2>/dev/null || stat -f %m f 2>/dev/null (or date -r f)"),
    ("stat -f",      re.compile(r"\bstat\s+-f\b"),        re.compile(r"stat\s+-c|date\s+-r\b"), "pair it: stat -f %m f 2>/dev/null || stat -c %Y f 2>/dev/null (or date -r f)"),
    ("date -d",      re.compile(r"\bdate\s+-d\b"),        re.compile(r"date\s+-[vj]"), "pair it with the BSD form (date -v / date -j) first"),
    ("date -v",      re.compile(r"\bdate\s+-v\b"),        re.compile(r"date\s+-d"), "pair it with the GNU form (date -d) as the fallback"),
    ("date -j",      re.compile(r"\bdate\s+-j\b"),        re.compile(r"date\s+-d"), "pair it with the GNU form (date -d) as the fallback"),
]

def audit(paths, root):
    findings = 0
    for path in paths:
        try:
            lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        except OSError:
            continue
        rel = os.path.relpath(path, root)
        for i, line in enumerate(lines):
            stripped = line.lstrip()
            if stripped.startswith("#") or "# portability-ok" in line:
                continue
            # BACKWARD AS WELL AS FORWARD. The first draft looked only at lines i..i+2 and so
            # flagged the SECOND half of every correct pair -- `|| stat -f ...` on the line after
            # `stat -c ...`, `|| date -d ...` after `date -j -f ...`. That is five false positives
            # per project on code that is already right, and a gate that cries wolf is a gate that
            # gets skipped, which is precisely what the pairing rule exists to prevent.
            window = "\n".join(lines[max(0, i - 2):i + 3])
            for label, pat, pair, why in CHECKS:
                if not pat.search(line):
                    continue
                if pair is not None and pair.search(window):
                    continue
                findings += 1
                print(f"  {rel}:{i+1}  [{label}]")
                print(f"      {stripped[:104]}")
                print(f"      -> {why}")
    return findings

if __name__ == "__main__":
    root = os.environ.get("PORT_ROOT", ".")
    paths = sys.argv[1:]
    n = audit(paths, root)
    if n == 0:
        print(f"portability: clean — {len(paths)} script(s), no unpaired GNU-only, BSD-only or bash-4 construct.")
        sys.exit(0)
    print()
    print(f"portability: {n} finding(s) across {len(paths)} script(s).")
    print("Two developers, two platforms: a construct that works on one is a script the other never runs.")
    print("A deliberate exception takes a trailing '# portability-ok' comment on the line.")
    sys.exit(1)
