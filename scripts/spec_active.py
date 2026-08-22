#!/usr/bin/env python3
"""THE canonical answer to "which spec is active?" — one implementation.

WHY THIS EXISTS (spec 007m)
---------------------------
Four call sites each derived the active spec independently, and at HEAD they
gave THREE different answers about the same register:

  spec-register-orientation-hook.sh   -> 007m   (correct: first whitespace token)
  pipeline-state-guard-hook.sh        -> 008    (numeric-only regex skipped 007m)
  spec-interview-guard-hook.sh        -> 008    (same regex, same skip)
  .specify/.../check-prerequisites.sh -> 007l   (stale .specify/feature.json)

The guards' disagreement was not cosmetic. Skipping a letter-suffixed row and
landing on a LATER numeric row means that when that later spec's artifacts
happen to exist, both BLOCKING guards approve a source edit for a spec that has
none. Proven by fixture in scripts/test-active-spec-resolution.sh: pre-fix, both
guards ALLOW an edit for a spec with zero artifacts and zero interview answers.

The register (specs/INDEX.md) is the source of truth per
.claude/rules/spec-register.md. This module is its single reader, and
.specify/feature.json becomes a CACHE of this answer rather than a fourth
independent opinion.

WHY A MODULE AND NOT JUST A SCRIPT
----------------------------------
The two guards are the hot path — they fire on EVERY source-code edit — and they
already run a python3 interpreter of their own. Shelling out to a separate
resolver process would add a second interpreter startup, and on this machine
`python3 -c pass` alone costs 50 ms: the resolution work is ~2 ms, the
interpreter is everything else. So the guards import this module into the
process they were already paying for, and the bash wrapper
(resolve-active-spec.sh) exists only for callers that are shell to begin with.
One implementation, no duplicated regex, no extra process on the hot path.

ID GRAMMAR — the whole defect in one table
  007      -> spec        (plain numeric)
  007m     -> spec        (letter-suffixed; the case that was silently dropped)
  **364    -> spec        (bold markdown stripped)
  H1       -> checkpoint  (integration-hardening; no pipeline artifacts required)
  007ab    -> spec        (MULTI-letter suffix, returned WHOLE. Truncating it to
                           "007a" would resolve to a DIFFERENT REAL SPEC, which
                           is this module's own failure mode in miniature. Spec
                           007m refused the id to guarantee that; spec 007ab
                           widened the grammar instead, which honours the same
                           property AND lets the register use the ids it uses.)
  7-x      -> unparseable (REPORTED, never dropped - silent dropping is the
                           defect this module exists to fix)

EXIT CODES (CLI) — callers MUST distinguish these (FR-007m-04)
  0  resolved an active row (see kind/found)
  3  no active row - every row ticked. An ANSWER, not a failure: callers ALLOW.
     Denying here would block all work on a finished project.
  4  cannot answer - register unreadable/malformed. Callers DENY.
"""

from __future__ import annotations

import glob
import json
import os
import re
import sys

# Tolerant row parser. Accepts the canonical
#   "- [x] 003 — search — full track — short goal"
# and heavily-formatted real-world rows like
#   "- [ ] **364 — inbound-reply (mail / Slack)** — full [hardened] — NOT STARTED"
ROW_RE = re.compile(r"^-\s+\[([ xX/!])\]\s+(.+?)\s+—\s+(.+?)\s+—\s+(.+?)\s+—.*$")

# NOTE the suffix letters. Their absence WAS the defect (007m), and allowing
# only ONE of them was the same defect one register-generation later (007ab):
# single-letter 007 suffixes ran out at 007z, so the register continued 007aa,
# 007ab, 007ac — and every one of those classified as unparseable, which made
# both PreToolUse guards fail closed and deny EVERY source edit for the whole
# remaining register. `*` rather than `?`, and the anchors are what keep the
# promise that matters: "007ab" is returned whole or not at all, never quietly
# truncated to "007a", which is a different real spec.
#
# No collision with CHECKPOINT_ID_RE: spec ids are digits-then-letters,
# checkpoints letters-then-digits.
SPEC_ID_RE = re.compile(r"^\**\s*([0-9]+[a-z]*)\**\s*$")
CHECKPOINT_ID_RE = re.compile(r"^\**\s*([A-Za-z]+[0-9]+)\**\s*$")

# Lane ownership. Two developers can work the register at once, so "the active
# spec" is per-lane, not global: without this the first "- [/]" row anywhere
# decides what BOTH developers may edit, and whoever is not working that row is
# blocked on artifacts belonging to somebody else's spec.
#
# A row's owner is a trailing "@name" tag. SPEC_OWNER (set per machine in
# .claude/settings.local.json, which is gitignored) names this machine's lane.
#   unset SPEC_OWNER -> every row is eligible: exactly the single-lane behaviour
#   set              -> rows tagged for somebody else are skipped; untagged rows
#                       stay eligible, so an untagged register works unchanged
OWNER_RE = re.compile(r"—\s*@([A-Za-z0-9._-]+)\s*$")

VALID_TRACKS = ("full", "light", "spec-only")


class RegisterUnreadable(Exception):
    """The register could not be read or parsed — callers must DENY."""


def classify_id(token: str) -> tuple[str, str]:
    """Return (identifier, kind) for a raw register-row id token."""
    m = SPEC_ID_RE.match(token)
    if m:
        return m.group(1), "spec"
    m = CHECKPOINT_ID_RE.match(token)
    if m:
        return m.group(1), "checkpoint"
    # Reported, never dropped. Silent dropping is the defect this module fixes.
    return re.sub(r"^\**|\**$", "", token), "unparseable"


def _rows(register_path: str):
    try:
        with open(register_path, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                stripped = line.rstrip()
                m = ROW_RE.match(stripped)
                if not m:
                    continue
                status, raw_id, _slug_field, track_field = m.groups()
                parts = raw_id.strip().split()
                token = parts[0] if parts else ""
                ident, kind = classify_id(token)
                om = OWNER_RE.search(stripped)
                owner = om.group(1).lower() if om else ""
                yield status, ident, kind, track_field.strip(), owner
    except OSError as exc:
        raise RegisterUnreadable(str(exc)) from exc


def resolve(root: str, sync_feature_json: bool = False, owner: str | None = None) -> dict:
    """Resolve the active spec for the project rooted at *root*.

    Selection: the ``- [/]`` in-progress row if one exists, otherwise the first
    ``- [ ]`` row — mirroring .claude/rules/spec-register.md and what the
    orientation hook always did correctly.

    With a lane set (*owner*, defaulting to ``$SPEC_OWNER``) the four buckets
    below apply. With no lane, nothing is "mine" and this collapses to
    first-``[/]``-else-first-``[ ]`` — byte-for-byte the single-lane behaviour.
    """
    register_path = os.path.join(root, "specs", "INDEX.md")
    if not os.path.isfile(register_path):
        raise RegisterUnreadable("no register at %s" % register_path)

    lane = (owner if owner is not None else os.environ.get("SPEC_OWNER", "")).strip().lower()

    # Four buckets, resolved in this priority: my in-progress row, my next row,
    # an unowned in-progress row, the next unowned row. A row assigned to me
    # beats an unowned one even when the unowned one comes first in the
    # register — otherwise a lane with work of its own gets pointed at the top
    # of the shared tail, which on a dependency-ordered register is usually a
    # spec blocked behind the OTHER lane's current row.
    own_active = own_pending = free_active = free_pending = None
    duplicate_active = False

    for status, ident, kind, track_field, row_owner in _rows(register_path):
        if lane and row_owner and row_owner != lane:
            continue  # somebody else's lane
        mine = bool(lane) and row_owner == lane
        entry = (ident, kind, track_field, status)
        if status == "/":
            if mine:
                if own_active is None:
                    own_active = entry
                else:
                    duplicate_active = True
            elif free_active is None:
                free_active = entry
            else:
                # The rule says exactly one row carries this. Report the
                # violation rather than pretending it is invisible.
                duplicate_active = True
        elif status == " ":
            if mine:
                if own_pending is None:
                    own_pending = entry
            elif free_pending is None:
                free_pending = entry

    active = own_active or own_pending or free_active or free_pending

    if active is None:
        result = {"id": None, "slug": "", "track": None, "status": None,
                  "kind": "none", "dir": None, "found": False,
                  "lane": lane, "duplicate_active": duplicate_active}
        # Spec 007q. "Every row ticked" is an ANSWER (exit 3), and the answer is
        # "no active spec" — so the cache must name nothing rather than keep
        # pointing at the last spec that happened to be worked.
        if sync_feature_json:
            result["feature_json_synced"] = _sync_feature_json(root, None)
        return result

    ident, kind, track_field, status = active

    # Track = first token of the track field: "full track" / "full [hardened]" -> "full".
    track = (track_field.split() or ["full"])[0].lower().strip()
    if track not in VALID_TRACKS:
        track = "full"  # most conservative

    spec_dir = None
    slug = ""
    if kind == "spec":
        candidates = sorted(glob.glob(os.path.join(root, "specs", "%s-*" % ident)))
        candidates += sorted(glob.glob(os.path.join(root, ".specify", "specs", "%s-*" % ident)))
        spec_dir = next((c for c in candidates if os.path.isdir(c)), None)
        if spec_dir:
            slug = os.path.basename(spec_dir)[len(ident) + 1:]

    rel_dir = os.path.relpath(spec_dir, root) if spec_dir else None

    result = {
        "id": ident,
        "slug": slug,
        "track": track,
        "status": status,
        "kind": kind,
        "dir": rel_dir,
        "found": spec_dir is not None,
        "lane": lane,
        "duplicate_active": duplicate_active,
    }

    # Spec 007q — no `and rel_dir` guard. A spec whose directory does not exist
    # yet must CLEAR the cache, not leave it naming the previous spec.
    if sync_feature_json:
        result["feature_json_synced"] = _sync_feature_json(root, rel_dir)

    return result


def _sync_feature_json(root: str, rel_dir: str | None) -> bool:
    """Point .specify/feature.json at *rel_dir*, writing only on disagreement.

    check-prerequisites.sh is deliberately NOT patched — `specify init --force`
    regenerates it, so a patch there is the same clobber trap that reverted spec
    004a's fix. Instead we satisfy spec-kit's own documented second-priority
    input, turning feature.json from a competing source into a cache.

    SPEC 007q — rel_dir=None means "name nothing", NOT "do nothing".
    ---------------------------------------------------------------
    This function used to be called only `if sync_feature_json and rel_dir`, so
    when the active spec had no directory yet — every spec, between the register
    row going active and /speckit-specify creating the directory — it was never
    entered, and the cache went on naming the PREVIOUS spec. That is verbatim
    the defect 007m was opened for, surviving inside 007m's own fix.

    The property this file must have is not freshness (no set of triggers can
    guarantee that) but: it names the active spec, or it names nothing. Never a
    different spec. A missed refresh then costs a loud "no feature context" from
    common.sh instead of a silent, confident pointer at another spec's spec.md.

    "Nothing" is the ABSENT key, not null and not "". common.sh reads this file
    three different ways depending on what is installed — jq, then python3, then
    a grep/sed fallback — and an omitted key is the only representation all
    three agree reads as empty. `null` survives the first two and can leak
    through the third as a literal.
    """
    path = os.path.join(root, ".specify", "feature.json")

    # Nothing to clear. Creating a file just to say "no answer" would add a
    # working-tree change on scratch repos that never had one.
    if rel_dir is None and not os.path.isfile(path):
        return False

    try:
        with open(path, "r", encoding="utf-8") as fh:
            if json.load(fh).get("feature_directory") == rel_dir:
                return False  # already correct — idempotent, no write
    except (OSError, ValueError):
        pass  # unreadable or corrupt: treat as disagreement and rewrite

    payload = {} if rel_dir is None else {"feature_directory": rel_dir}
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
            fh.write("\n")
        return True
    except OSError:
        return False


def find_root(start: str | None = None) -> str | None:
    """Walk up to the first directory holding specs/INDEX.md, stopping at .git.

    The .git stop matters: without it a parent directory's stray register could
    leak into an unrelated repo, which is the same class of wrong-answer bug
    this module exists to eliminate.
    """
    d = os.path.abspath(start or os.getcwd())
    while d and d != "/":
        if os.path.isfile(os.path.join(d, "specs", "INDEX.md")):
            return d
        if os.path.isdir(os.path.join(d, ".git")):
            return None
        d = os.path.dirname(d)
    return None


def main(argv: list[str]) -> int:
    root = None
    sync = False
    owner = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--root":
            i += 1
            if i >= len(argv):
                print("ERROR: --root needs a value", file=sys.stderr)
                return 2
            root = argv[i]
        elif arg == "--sync-feature-json":
            sync = True
        elif arg == "--owner":
            i += 1
            if i >= len(argv):
                print("ERROR: --owner needs a value", file=sys.stderr)
                return 2
            owner = argv[i]
        elif arg in ("--help", "-h"):
            print(__doc__)
            return 0
        else:
            print("ERROR: unknown option '%s'" % arg, file=sys.stderr)
            return 2
        i += 1

    if root is None:
        root = find_root()
    if not root:
        print(json.dumps({"error": "no register found"}))
        return 4

    try:
        result = resolve(root, sync_feature_json=sync, owner=owner)
    except RegisterUnreadable as exc:
        print(json.dumps({"error": "register unreadable: %s" % exc}))
        return 4

    print(json.dumps(result))
    return 3 if result["kind"] == "none" else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
