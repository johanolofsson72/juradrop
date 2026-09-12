#!/usr/bin/env python3
"""Extract candidate write targets from a shell command string (row H7b).

WHY A MODULE AND NOT A HEREDOC
------------------------------
The first cut of scripts/bash-write-guard-hook.sh embedded this as
``TARGETS=$(... python3 <<'PY' ... PY)``. Bash parses quotes *inside* a heredoc
that sits inside a command substitution, and this code is nothing but quotes and
regex — the hook failed to parse at all, silently allowing every write it was
written to stop. A guard that cannot be loaded is a guard that allows, which is
the exact failure this row exists to remove, so the parser lives in its own file
where the shell never reads it.

THREE MODES
  extract   CMD_TEXT + CWD_PATH in the environment -> absolute write targets
  --opaque  CMD_TEXT + CWD_PATH in the environment -> paths named inside an
            interpreter's program (see OPAQUE REGIONS below)
  --group   newline-separated paths on stdin       -> one representative per group

GROUPING — exact for THREE guards, and the premise expired (row S5)
-------------------------------------------------------------------
The three PIPELINE guards decide from the path alone: a glob allowlist, an
extension test, and a walk up to the .git boundary. Two files that share a
directory AND an extension are guaranteed identical verdicts from all three, so
collapsing them to one representative is an identity there, not an
approximation — which is what lets the callers' caps be honest about coverage.

**It stopped being true of the delegate list when row H7t added a fourth guard
and spec 007ca a fifth, and nothing here was updated.** core-machinery decides
from the BASENAME (is this name in CORE_SCRIPTS?) and core-owed-tick from the
exact filename (is this specs/INDEX.md?). Two .sh files in scripts/ share a
directory and an extension and can have opposite verdicts, so the representative
decided the answer for both. Measured 2026-09-02, and it is a one-command bypass
rather than a theoretical one:

    sed -i 's/a/b/' scripts/template-autosync.sh                    -> deny
    sed -i 's/a/b/' scripts/template-autosync.sh scripts/other.sh   -> deny
    sed -i 's/a/b/' scripts/other.sh scripts/template-autosync.sh   -> ALLOW

Order of operands decided whether a CORE file could be rewritten. So the callers
now ask the two basename-sensitive guards about EVERY distinct path (--all) and
the three path-only guards about one per group (the default). One question, two
granularities, and the grouping identity is claimed only where it holds.

This is the shape .claude/rules/mutation-timeouts.md calls trap 4: the conclusion
("collapsing is exact") was verified for years while its premise ("all guards
decide from the path alone") quietly stopped being true underneath it.

COVERAGE BOUND
--------------
Six forms: redirection > and >> (also how a heredoc writes), sed -i, tee, cp, mv.
This is a string parser; it cannot see a write done by an interpreter, behind
eval, through xargs, or via a runtime-assembled path. Those are caught by
scripts/bash-write-detect-hook.sh, which watches the filesystem instead.

OPAQUE REGIONS — the shape, never the program (row S5)
------------------------------------------------------
The bound above was a working bypass, and it was used: a register tick written as
``python3 - <<'PY' … PY`` met none of the five guards, while the same write spelled
``sed -i`` is denied. ``perl -e``, ``node -e`` and ``python3 -c`` are the same defect
in different syntax.

The fix is NOT to read the programs. A guard that tries to parse every interpreter
keeps losing, one interpreter at a time. What is recognisable without reading
anything is the SHAPE: an interpreter invoked with **no script path** — a heredoc
fed to one, an inline program flag (-c/-e/-E/-r/--eval), or bare ``eval``. The text
it would read as its program is an OPAQUE REGION.

Inside a region this module scans for path-shaped tokens and nothing else. It
cannot tell a read from a write there, and it does not pretend to: the caller
answers about the PATH and says so in its refusal. That is the same trade
core-owed-tick-guard-hook.sh already documents for the shell route — with no bytes
to read it answers about the file, because the alternative is that the shell is the
silent way past a gate the Edit tool enforces.

Still uncovered, and deliberately not claimed: a path assembled at runtime inside
the region (nothing here evaluates anything), and ``xargs`` / ``find -exec``, which
carry a COMMAND rather than a program — a different shape, with no fixture behind
it. Both remain the post-layer's business.

Covers: SC-1437 SC-1439 SC-913 SC-914 SC-915 SC-916 SC-917 SC-919
"""

from __future__ import annotations

import os
import re
import sys

# A shell word: double-quoted, single-quoted, or bare. The bare form deliberately
# stops at the metacharacters that end a word, so `>f;ls` yields "f" and not "f;ls".
QUOTED = r"""(?:"([^"]+)"|'([^']+)'|([^\s;|&<>()]+))"""

# Paths that are writes in form only. /dev/null is the single most common redirect
# target in this repo's own scripts.
NON_FILES = ("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty", "/dev/fd")

# An interpreter that will read a program from stdin or from an argument. `sh`,
# `bash` and `zsh` are here for `-c`: a shell given a program string is as opaque
# to this parser as python is, and it is the cheapest of all these to reach for.
INTERPRETERS = (
    "python", "python3", "perl", "ruby", "node", "php", "sh", "bash", "zsh",
)

# The flags that carry a program instead of naming a script file.
INLINE_FLAGS = ("-c", "-e", "-E", "-r", "--eval")

# A token is path-shaped if it holds a separator or carries a short extension.
# Deliberately loose: a false candidate costs one delegate call that answers
# "allow", while a missed one is the defect this whole row is about.
_EXT = re.compile(r"\.[A-Za-z0-9]{1,6}$")


def _pick(match: re.Match, base: int) -> str | None:
    for g in (base, base + 1, base + 2):
        if match.group(g):
            return match.group(g)
    return None


def strip_heredoc_bodies(cmd: str) -> str:
    """Remove heredoc BODIES, keeping the opening line.

    A body is arbitrary text; a line inside it that happens to read ``> foo.cs``
    is not a redirection this command performs. The opening line stays, so
    ``cat > src/App.cs <<'EOF'`` is still seen as a redirection to src/App.cs —
    which is the whole reason heredoc counts as one of the six covered forms.
    """
    lines = cmd.split("\n")
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        i += 1
        if m:
            term = m.group(2)
            while i < len(lines) and lines[i].strip() != term:
                i += 1
            i += 1  # drop the terminator line too
    return "\n".join(out)


def _split_unquoted(text: str) -> list[str]:
    """Split on shell separators that are NOT inside quotes.

    ``extract`` splits on a plain ``[;&|\\n]+`` regex, which is fine there because
    it is looking for whole commands. It is wrong here: ``python3 -c "import sys;
    print(1)"`` would be cut at the semicolon INSIDE the program, and everything
    after it — including any path — would never be scanned. Truncating an opaque
    region is a miss, and a miss is the direction this row exists to remove.
    """
    parts: list[str] = []
    buf: list[str] = []
    quote = ""
    for ch in text:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = ""
            continue
        if ch in "\"'":
            quote = ch
            buf.append(ch)
            continue
        if ch in ";&|\n":
            parts.append("".join(buf))
            buf = []
            continue
        buf.append(ch)
    parts.append("".join(buf))
    return parts


def _names_interpreter(line: str) -> bool:
    for word in re.findall(r"[A-Za-z0-9_./-]+", line):
        if os.path.basename(word) in INTERPRETERS:
            return True
    return False


def opaque_regions(cmd: str) -> list[str]:
    """Text an interpreter would read as its program, in order of appearance.

    Three shapes, and none of them involves reading the program:

      * a heredoc whose OPENING LINE names an interpreter — the body is a program,
        not data. ``cat > f <<EOF`` is untouched: its body stays dropped and ``f``
        stays a target, which is what makes heredoc one of the six covered forms.
      * an interpreter followed by an inline program flag — the region runs to the
        end of the unquoted segment.
      * bare ``eval`` — same.
    """
    regions: list[str] = []

    lines = cmd.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.search(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        i += 1
        if not m:
            continue
        term = m.group(2)
        body: list[str] = []
        while i < len(lines) and lines[i].strip() != term:
            body.append(lines[i])
            i += 1
        i += 1  # the terminator line
        if _names_interpreter(line):
            regions.append("\n".join(body))

    for seg in _split_unquoted(strip_heredoc_bodies(cmd)):
        words = re.findall(r"[^\s]+", seg)
        for idx, word in enumerate(words):
            base = os.path.basename(word)
            if base == "eval":
                regions.append(" ".join(words[idx + 1:]))
                break
            if base in INTERPRETERS:
                rest = words[idx + 1:]
                for j, w in enumerate(rest):
                    if w in INLINE_FLAGS:
                        regions.append(" ".join(rest[j + 1:]))
                        break
                break

    return [r for r in regions if r.strip()]


def _path_shaped(tok: str) -> bool:
    if not tok or tok.startswith("-"):
        return False
    # A shell word cannot hold whitespace unquoted, and a path does not hold call
    # syntax. Without this, `python3 -c "import sys; open('x')"` yields the whole
    # program as ONE token: the region still carries its shell quotes, so the
    # double-quoted branch of QUOTED swallows everything between them.
    if any(c in tok for c in " \t\"'()=$"):
        return False
    if "/" in tok:
        return True
    # A bare extension only counts when it is not a leading dot, or `.write('x')`
    # in a python program reads as a file called `.write`.
    return bool(_EXT.search(tok)) and not tok.startswith(".")


def opaque_paths(cmd: str) -> list[str]:
    """Path-shaped tokens inside the opaque regions. Never the program text.

    Each region is scanned twice: as written, and with every quote character
    blanked. The second pass is what reaches a path nested one quoting level down
    — `perl -e 'open(F,">>","scripts/x.sh")'` — where the outer quotes otherwise
    make the whole program a single token. Blanking turns `(` and `)` into the word
    boundaries they already are for the bare branch of QUOTED, so the path falls
    out on its own. Duplicates cost nothing: `absolutize` dedupes.
    """
    out: list[str] = []
    for region in opaque_regions(cmd):
        unquoted = re.sub(r"[\"']", " ", region)
        for text in (region, unquoted):
            for m in re.finditer(QUOTED, text):
                t = _pick(m, 1)
                if t is None:
                    continue
                t = t.strip().strip(",")
                if _path_shaped(t):
                    out.append(t)
    return out


def extract(cmd: str) -> list[str]:
    """Return raw (possibly relative) write targets, in order of appearance."""
    text = strip_heredoc_bodies(cmd)
    targets: list[str] = []

    # (a) redirection. The negative lookbehind keeps file-descriptor work out:
    #     2>&1, 1>&2 and &> are not writes to a file called "1".
    for m in re.finditer(r"(?<![0-9&])>{1,2}\s*" + QUOTED, text):
        t = _pick(m, 1)
        if t and not t.startswith("&"):
            targets.append(t)

    segments = re.split(r"[;&|\n]+", text)

    # (b) sed -i / --in-place. GNU takes the file straight after the flag; BSD and
    #     macOS take a backup-suffix argument first (`sed -i '' 's/x/y/' f`).
    #     Rather than model two dialects, take every non-option word in the
    #     segment: the script word (`s/x/y/`) survives here but is dropped
    #     downstream, because it has no source-code extension and so every guard
    #     allows it.
    for seg in segments:
        if not re.search(r"\bsed\b", seg):
            continue
        if not re.search(r"\s-i\b|\s--in-place\b|\s-[a-hj-zA-Z]*i[a-zA-Z]*\b", seg):
            continue
        for m in re.finditer(QUOTED, seg):
            t = _pick(m, 1)
            if t and not t.startswith("-") and t != "sed":
                targets.append(t)

    # (c) tee [-a] FILE...
    for m in re.finditer(r"\btee\b((?:\s+-\w+)*)((?:\s+" + QUOTED + r")+)", text):
        for m2 in re.finditer(QUOTED, m.group(2)):
            t = _pick(m2, 1)
            if t and not t.startswith("-"):
                targets.append(t)

    # (d) cp / mv — the destination is the last operand of the segment.
    for seg in segments:
        if not re.match(r"\s*(sudo\s+)?(cp|mv)\b", seg):
            continue
        ops = [_pick(m, 1) for m in re.finditer(QUOTED, seg)]
        ops = [o for o in ops if o and not o.startswith("-")]
        if len(ops) >= 3:  # ["cp", src, ..., dst]
            targets.append(ops[-1])

    return targets


def absolutize(targets: list[str], cwd: str) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for t in targets:
        t = t.strip()
        if not t:
            continue
        # A path assembled at runtime. This is the declared bound, not an
        # oversight: guessing what $DIR expands to would invent a finding.
        if t.startswith("$") or t.startswith("`") or "$(" in t:
            continue
        if t in NON_FILES or t.startswith("/dev/fd/"):
            continue
        p = t if os.path.isabs(t) else os.path.normpath(os.path.join(cwd, t))
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def representatives(paths: list[str]) -> list[str]:
    groups: dict[tuple[str, str], str] = {}
    order: list[tuple[str, str]] = []
    for p in paths:
        key = (os.path.dirname(p), os.path.splitext(p)[1].lower())
        if key not in groups:
            groups[key] = p
            order.append(key)
    return [groups[k] for k in order]


def main(argv: list[str]) -> int:
    if "--group" in argv:
        paths = [ln.strip() for ln in sys.stdin.read().split("\n") if ln.strip()]
        for r in representatives(paths):
            print(r)
        return 0

    cmd = os.environ.get("CMD_TEXT", "")
    cwd = os.environ.get("CWD_PATH", "") or os.getcwd()
    if not cmd:
        return 0
    # Same output contract in both modes — count on line 1, representatives after —
    # so the hook parses one shape and not two.
    finder = opaque_paths if "--opaque" in argv else extract
    paths = absolutize(finder(cmd), cwd)
    if not paths:
        return 0
    # Line 1 is the total target count (so a caller can report it). The rest are
    # either every distinct path (--all, for the basename-sensitive guards) or one
    # representative per group (the default, for the three path-only guards).
    print(len(paths))
    for r in (paths if "--all" in argv else representatives(paths)):
        print(r)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
