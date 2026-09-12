#!/usr/bin/env python3
"""Engine for register-similarity.sh — see that file for why this exists.

Embeds every register row across the given projects and reports the pairs that
say the same thing. Two modes:

  corpus   every pair above the threshold, ranked      (the audit)
  query    one candidate row against the whole corpus  (the pre-carve check)

No third-party packages: urllib and a hand-rolled cosine over a few hundred
short vectors, which is milliseconds. Adding numpy here would make a check that
runs on six repos depend on an install that may not be there.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

HOST = os.environ.get("REGISTER_SIMILARITY_HOST", "http://127.0.0.1:11434")
MODEL = os.environ.get("REGISTER_SIMILARITY_MODEL", "paraphrase-multilingual")
THRESHOLD = float(os.environ.get("REGISTER_SIMILARITY_THRESHOLD", "0.82"))
TOP = int(os.environ.get("REGISTER_SIMILARITY_TOP", "25"))
QUERY = os.environ.get("REGISTER_SIMILARITY_QUERY", "").strip()
# paraphrase-multilingual is a sentence-transformer with a 128-token window and it
# does not truncate -- it returns HTTP 500. Measured on this box: 400 chars ok,
# 512 fails. So the cap is ours to enforce, and it is set below the cliff rather
# than at it. A row's subject is in its opening clause anyway; the tail is the
# diagnosis, which by the row-budget rule now lives in an archive.
TRUNC = int(os.environ.get("REGISTER_SIMILARITY_TRUNC", "400"))
OPEN_ONLY = os.environ.get("REGISTER_SIMILARITY_OPEN_ONLY") == "1"

ROW = re.compile(r"^- \[([ x/!])\] +\*{0,2}([^\s—*]+)\*{0,2} — (.+?) — (.+?) — (.+)$")


SKIPPED = []


def embed(texts):
    """One request per text. Ollama's /api/embeddings takes a single prompt, and a
    batch endpoint is not available on every version this has to run against.

    A failure on ONE row returns None for that row and keeps going. Aborting the
    whole pass on one bad row would mean a single unusual line makes the check
    report nothing at all -- which reads exactly like a clean project."""
    out = []
    for i, t in enumerate(texts):
        # Halve-and-retry. TRUNC is a CHARACTER cap and the model's limit is in
        # TOKENS, and the ratio is not constant: Swedish prose with code
        # identifiers and punctuation tokenises far denser than English, so a
        # fixed char cap that is safe for one row 500s on the next. Measured:
        # 400 chars cleared every agentcrm row and still failed 7 of
        # consultpilot's. Rather than tune a number that cannot be right for
        # both, shrink until it fits.
        v = None
        err = None
        for cap in (TRUNC, TRUNC // 2, TRUNC // 4):
            body = json.dumps({"model": MODEL, "prompt": t[:cap]}).encode()
            req = urllib.request.Request(
                f"{HOST}/api/embeddings", data=body,
                headers={"Content-Type": "application/json"},
            )
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    v = json.load(r).get("embedding")
                if v:
                    break
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError,
                    urllib.error.HTTPError) as e:
                err = str(e)
        if not v and err:
            SKIPPED.append((i, err))
        if not v:
            if not SKIPPED or SKIPPED[-1][0] != i:
                SKIPPED.append((i, "empty embedding"))
            out.append(None)
            continue
        # Normalise once so the comparison is a plain dot product.
        n = sum(x * x for x in v) ** 0.5 or 1.0
        out.append([x / n for x in v])
        if len(texts) > 40 and i and i % 50 == 0:
            print(f"  … embedded {i}/{len(texts)}", file=sys.stderr)
    return out


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def load_rows(dirs):
    rows = []
    for d in dirs:
        reg = Path(d) / "specs" / "INDEX.md"
        if not reg.is_file():
            continue
        project = Path(d).name
        for line in reg.read_text(encoding="utf-8", errors="replace").split("\n"):
            m = ROW.match(line)
            if not m:
                continue
            status, rid, slug, track, body = m.groups()
            if OPEN_ONLY and status not in (" ", "!"):
                continue
            # Structural rows, not work. The integration-hardening checkpoint and
            # the standing harness-defects pointer are written from the same
            # template text in every project, so they match each other at 1.000
            # and nothing else. On a 14-project pass they produced 208 of the 216
            # cross-project pairs -- a report that is almost entirely one
            # by-design coincidence is a report nobody reads twice.
            if re.search(r"\b(checkpoint|standing|st\u00e5ende)\b", track, re.I):
                continue
            # Embed slug + body, not the id or the track: the id is arbitrary and the
            # track is drawn from a tiny vocabulary, so both pull unrelated rows
            # together and drown the signal that matters.
            text = re.sub(r"[`*]", "", f"{slug.replace('-', ' ')}. {body}")
            text = re.sub(r"\s+", " ", text).strip()
            rows.append({"project": project, "id": rid, "status": status,
                         "slug": slug, "text": text})
    return rows


def main():
    dirs = sys.argv[1:]
    rows = load_rows(dirs)
    if len(rows) < 2:
        print("register-similarity: fewer than two rows to compare.")
        return 0

    scope = "open rows" if OPEN_ONLY else "rows"
    print(f"register-similarity: {len(rows)} {scope} from {len(dirs)} project(s), "
          f"model {MODEL}, threshold {THRESHOLD}\n", file=sys.stderr)

    vecs = embed([r["text"] for r in rows])
    if SKIPPED:
        print(f"register-similarity: {len(SKIPPED)} row(s) could not be embedded and are "
              f"excluded — first: item {SKIPPED[0][0]}, {SKIPPED[0][1]}", file=sys.stderr)
    if all(v is None for v in vecs):
        print("register-similarity: nothing could be embedded.", file=sys.stderr)
        return 2

    if QUERY:
        qv = embed([QUERY])
        if not qv or qv[0] is None:
            print("register-similarity: the query itself could not be embedded.", file=sys.stderr)
            return 2
        scored = sorted(((dot(qv[0], v), r) for v, r in zip(vecs, rows) if v is not None),
                        key=lambda p: -p[0])[:TOP]
        print(f'Closest existing rows to: "{QUERY[:90]}"\n')
        hit = False
        for s, r in scored:
            if s < THRESHOLD:
                continue
            hit = True
            print(f"  {s:.3f}  [{r['status']}] {r['project']}/{r['id']} — {r['slug']}")
        if not hit:
            print(f"  nothing at or above {THRESHOLD} — this looks like new work.")
        return 1 if hit else 0

    pairs = []
    for i in range(len(rows)):
        if vecs[i] is None:
            continue
        for j in range(i + 1, len(rows)):
            if vecs[j] is None:
                continue
            s = dot(vecs[i], vecs[j])
            if s >= THRESHOLD:
                pairs.append((s, rows[i], rows[j]))
    pairs.sort(key=lambda p: -p[0])

    # Boilerplate suppression, the general form of the checkpoint case above. A row
    # that matches near-identically in three or more DIFFERENT projects is text the
    # template handed everyone, not work anybody duplicated. Dropping the cluster is
    # right even when the wording was not literally shared: what makes it noise is
    # that it is everywhere, which is exactly what this counts.
    BOILER_SIM, BOILER_PROJECTS = 0.95, 3
    seen_in = {}
    for sc, a, b in pairs:
        if sc >= BOILER_SIM:
            for x, y in ((a, b), (b, a)):
                seen_in.setdefault(x["slug"], set()).add(y["project"])
    boiler = {sl for sl, ps in seen_in.items() if len(ps) >= BOILER_PROJECTS}
    if boiler:
        before = len(pairs)
        pairs = [p for p in pairs if p[1]["slug"] not in boiler and p[2]["slug"] not in boiler]
        print(f"register-similarity: suppressed {before - len(pairs)} pair(s) from "
              f"{len(boiler)} boilerplate row(s) carried by 3+ projects "
              f"({', '.join(sorted(boiler)[:4])}).\n", file=sys.stderr)

    if not pairs:
        print(f"register-similarity: no pair at or above {THRESHOLD}. "
              "No two rows are saying the same thing.")
        return 0

    cross = [p for p in pairs if p[1]["project"] != p[2]["project"]]
    same = [p for p in pairs if p[1]["project"] == p[2]["project"]]

    print(f"{len(pairs)} pair(s) at or above {THRESHOLD} — "
          f"{len(cross)} across projects, {len(same)} within one.\n")
    print("These are candidates for a human to read, not a verdict. Two rows can be")
    print("close in wording and different in intent; the point is that nobody was")
    print("looking at all.\n")

    def show(title, group):
        if not group:
            return
        print(f"── {title} " + "─" * max(0, 58 - len(title)))
        for s, a, b in group[:TOP]:
            print(f"  {s:.3f}  [{a['status']}] {a['project']}/{a['id']} — {a['slug']}")
            print(f"         [{b['status']}] {b['project']}/{b['id']} — {b['slug']}")
        if len(group) > TOP:
            print(f"  … and {len(group) - TOP} more (raise --top)")
        print()

    # Cross-project first: that is the case nobody can hold in their head, and the
    # one the developer actually asked about.
    show("across projects — is this already built somewhere?", cross)
    show("within one project — should these be one row?", same)
    return 1


if __name__ == "__main__":
    sys.exit(main())
