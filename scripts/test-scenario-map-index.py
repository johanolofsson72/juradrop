#!/usr/bin/env python3
"""test-scenario-map-index.py — the index must not drift from the files it summarizes.

WHY THIS EXISTS: splitting the scenario map (spec 007bl) bought a small per-spec read and
created a failure mode that did not exist before — the index and the feature files can now
disagree. One document cannot contradict itself; two can, silently, and the contradiction
looks like nothing at all until somebody trusts the wrong half.

The sharpest case is the per-feature status tally. It is the project-wide progress view — the
one that made checkpoint H1's section 3 possible — and it goes stale the instant a future spec
flips a `◐` to `✓` inside a feature file and does not touch the index. Nothing else would
notice: the row count is unchanged, the losslessness gate still passes, the canary is silent,
and the index goes on stating a number that was true last month.

So the nine invariants below run on every spec, against the real map, rather than being
verified once by hand at the moment they were introduced.

Silent on projects in the single-file layout — there is no index to drift from, so every check
is vacuous and reporting on it would be noise.

Run:  bash scripts/test-scenario-map-index.py
Exit: 0 all invariants hold (or single-file layout) · 1 one or more violated
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX = os.path.join(ROOT, "specs", "SCENARIOS.md")
FEAT_DIR = os.path.join(ROOT, "specs", "scenarios")
EXTRACT = os.path.join(ROOT, "scripts", "scenario-map-rows.sh")

FAILED = []


def ok(msg):
    print(f"  ok:   {msg}")


def na(case, why):
    # NOT APPLICABLE is its own answer. Printing "ok" for an invariant whose input column does not
    # exist is the vacuous pass this whole file spent a year reporting; printing "FAIL" would blame
    # the map for a shape the checker chose not to support. Neither is true, so neither is printed.
    print(f"  n/a:  {case} — {why}")


def bad(case, detail):
    print(f"  FAIL: {case} — {detail}")
    FAILED.append(case)


if not os.path.isdir(FEAT_DIR) or not os.listdir(FEAT_DIR):
    print("single-file layout — no index to drift from, nothing to check")
    sys.exit(0)

if not os.path.isfile(INDEX):
    print("FAIL: specs/scenarios/ exists but specs/SCENARIOS.md does not")
    sys.exit(1)


def rows_of(*paths):
    """Rows via the one extractor, so this harness and the losslessness gate agree on what a
    row IS. Re-parsing the tables here would let the two drift — the very defect being tested."""
    out = subprocess.run(["sh", EXTRACT, *paths], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"extractor failed on {paths}: {out.stderr.strip()}")
    # TAB-separated, not "|": a scenario cell may contain a pipe. See the OUTPUT block
    # in scenario-map-rows.sh.
    return [l.split("\t") for l in out.stdout.split("\n") if l.strip()]


index_text = open(INDEX, encoding="utf-8").read()

# An index row, TABLE shape: | [Title](scenarios/slug.md) | specs | id-ranges | tally |
ROW_RE = re.compile(
    r"^\| \[(?P<title>[^\]]+)\]\(scenarios/(?P<file>[a-z0-9.-]+\.md)\) \| (?P<specs>[^|]*) \| (?P<ids>[^|]*) \| (?P<tally>[^|]*) \|$",
    re.M,
)

# ...and LIST shape, which is what a split index written as bullets looks like:
#     - ### Feature: Connect Fortnox   (spec: 280-fortnox-org-config)  → [scenarios/280.md](scenarios/280.md)
# It carries a title, a spec slug and a link, and it carries NO id-range and NO tally — so the
# invariants that compare those are not applicable to it and say so rather than passing vacuously.
# The colon after "spec" is OPTIONAL, and that is not a nicety. rocky writes
# "(spec 292)" on 194 of its 240 index links and "(spec: 279-…)" on the other 46.
# Requiring the colon made the gate see 46 links where there are 240, and then
# report 194 perfectly-linked files as orphans on disk. Measured 2026-09-03: it
# named 88 files as orphans when exactly TWO are genuinely unreferenced.
#
# A gate that invents 86 findings is worse than one that finds none — the two real
# ones were invisible inside the noise, and nobody reads the 89th line of a list
# that is wrong at the top.
LIST_RE = re.compile(
    r"^[-*] +#*\s*Feature:\s*(?P<title>.+?)\s*\((?:spec|specs):?\s*(?P<specs>[^)]*)\)"
    r".*?\]\(scenarios/(?P<file>[a-z0-9.-]+\.md)\)",
    re.M,
)

# A list index does not have ONE shape either. This project's grew a second one partway through —
# a heading carrying the prose and the spec slug, with the link on its own continuation line:
#     ## Actor: ... — slug (553): ... (spec: 553-the-slug)
#       → [scenarios/553.md](scenarios/553.md)
# Knowing only the first shape is what produced "183 orphan feature files": not 183 unindexed
# features, one unrecognised row shape. So the link is the anchor and the spec slug is looked up
# from the nearest heading above it, which covers both list forms with one rule.
LINK_RE = re.compile(r"^\s*(?:[-*]\s*)?(?:→|->)\s*\[[^\]]*\]\(scenarios/(?P<file>[a-z0-9.-]+\.md)\)", re.M)
SPEC_IN_LINE = re.compile(r"\((?:spec|specs):\s*([^)]*)\)")
# The same fact written without the parentheses: "— spec 377 live-correctness-batch". Both forms are
# in this project's index, and knowing only the first one made a link borrow the slug of the heading
# ABOVE its own — which the slug invariant then reported as index drift. It was attribution.
SPEC_BARE = re.compile(r"\bspecs?\s+(\d{3}[a-z0-9.]*)[ \t]+([a-z0-9][a-z0-9-]*)")
# And a third: "— responsive-appshell-and-mobile-navigation (515):", the slug before the number.
# It sits in the heading's identifier region, right after the actor text and before the prose, so it
# is matched there and not hunted for anywhere on the line.
SPEC_DASH = re.compile(r"[—-]\s*([a-z][a-z0-9-]{3,})\s*\((\d{3}[a-z0-9.]*)\)\s*[:.]")
HEADING = re.compile(r"^\s*(?:#{2,}\s|[-*]\s*#{2,}\s)")


def spec_of(line):
    # ORDER MATTERS, and it is least-ambiguous first. SPEC_BARE scans for "spec NNN slug" anywhere on
    # the line, and these headings carry paragraphs of prose that cite other specs by number — it
    # read "spec 506 has" out of the middle of one and attributed the row to spec 506. The two
    # explicit forms are tried before the loose one for exactly that reason.
    hit = SPEC_IN_LINE.search(line)
    if hit:
        return hit.group(1).strip()
    hit = SPEC_DASH.search(line)
    if hit:
        return f"{hit.group(2)}-{hit.group(1)}"
    hit = SPEC_BARE.search(line)
    if hit:
        return f"{hit.group(1)}-{hit.group(2)}"
    return ""


def list_entries(text):
    lines = text.split("\n")
    found = []
    for i, line in enumerate(lines):
        m = LINK_RE.match(line)
        if not m:
            continue
        # THE WALK STOPS AT THE FIRST HEADING. A link belongs to the heading directly above it; if
        # that heading names no spec, this row names no spec and says so. An unbounded walk happily
        # attributes a link to a heading two features earlier, and the slug invariant then reports
        # that as drift in the map — a checker manufacturing the defect it is checking for.
        specs, title = "", ""
        for j in range(i, max(-1, i - 8), -1):
            cand = spec_of(lines[j])
            if cand:
                specs = cand
                title = lines[j].lstrip("#-* ").split("(")[0].strip()
                break
            if j != i and HEADING.match(lines[j]):
                title = lines[j].lstrip("#-* ").split("(")[0].strip()
                break
        found.append({"title": title, "file": m.group("file"), "specs": specs, "ids": "", "tally": ""})
    return found


entries = [m.groupdict() for m in ROW_RE.finditer(index_text)]
INDEX_SHAPE = "table"
if not entries:
    # MERGE the two list shapes, do not pick one. An index can use both, and
    # rocky's does: 80 rows are "- ### Feature: … (spec 292) → [link]" which only
    # LIST_RE sees, and 154 are a heading with the link on its own continuation
    # line, which only LINK_RE sees. Taking whichever matcher found MORE threw
    # away the other 80 and reported them as orphan files on disk — 88 findings
    # where two are real.
    #
    # Keyed on the file, because that is what an entry is about; a file matched by
    # both shapes is one entry, and LIST_RE's is preferred because it carries the
    # spec column straight off the row rather than inferring it from a heading.
    INDEX_SHAPE = "list"
    merged = {}
    for e in list_entries(index_text):
        merged[e["file"]] = e
    for m in LIST_RE.finditer(index_text):
        merged[m.group("file")] = dict(m.groupdict(), ids="", tally="")
    entries = list(merged.values())
files_on_disk = sorted(f for f in os.listdir(FEAT_DIR) if f.endswith(".md"))

print(f"index has {len(entries)} rows ({INDEX_SHAPE} shape); {len(files_on_disk)} feature files on disk")

# AN UNREADABLE INDEX IS NOT AN INDEX FULL OF DEFECTS. With zero rows parsed, "every feature file is
# an orphan" and "no feature file has a back-link" are both arithmetically true and both meaningless
# — and on a 229-file map they print 229 filenames twice, which is how a checker gets switched off.
# This ran that way for as long as the extractor was refusing the map: it reported ok over zero rows,
# and the moment it could read rows it started accusing everything instead. Stop, and say which of
# the two shapes was expected.
if not entries and files_on_disk:
    bad("the index shape is recognised",
        f"{len(files_on_disk)} feature files on disk and not one index row parsed. The index is "
        f"neither the table shape (| [Title](scenarios/x.md) | specs | ids | tally |) nor the list "
        f"shape (- ### Feature: T   (spec: N-slug)  → [scenarios/x.md](...)). Nothing below this "
        f"line can be evaluated, so it is not evaluated.")
    print()
    print("FAILED — the index could not be read, so nothing downstream was evaluated")
    raise SystemExit(1)

# --- 1. every feature file is linked, and every link resolves -------------------------
linked = [e["file"] for e in entries]
missing = [f for f in linked if not os.path.isfile(os.path.join(FEAT_DIR, f))]
orphans = [f for f in files_on_disk if f not in linked]
if missing:
    bad("every index link resolves", f"broken: {', '.join(missing)}")
else:
    ok(f"every index link resolves ({len(linked)})")
if orphans:
    # An orphan is a feature whose scenarios exist but which is invisible to anyone reading
    # the index — mapped and unfindable, which is worse than unmapped because it looks done.
    bad("no orphan feature files", f"on disk but not linked: {', '.join(orphans)}")
else:
    ok("no orphan feature files")

# --- 2. each file is indexed exactly once ---------------------------------------------
dupes = {f for f in linked if linked.count(f) > 1}
if dupes:
    bad("each feature file indexed exactly once", f"duplicated: {', '.join(sorted(dupes))}")
else:
    ok("each feature file indexed exactly once")

# --- 3. the link matches the file's own primary slug ----------------------------------
SLUG_RE = re.compile(r"\b(\d{3}[a-z]*-[a-z0-9][a-z0-9-]*)\b")
bad_link = []
for e in entries:
    stem = e["file"][:-3]
    if stem.startswith("cross-cutting"):
        continue
    if stem not in e["specs"]:
        bad_link.append(f"{e['file']} (Spec column: {e['specs'].strip()})")
if bad_link:
    bad("link matches a slug the row names", "; ".join(bad_link))
else:
    ok("link matches a slug the row names")

# --- 4. tally counts LIVE rows, and retired are named separately ----------------------
# The list shape carries no tally and no id-range, so these two invariants have nothing to compare.
# Reported as not-applicable rather than as ok: "ok over a column that does not exist" is the same
# vacuous pass this file was reporting over zero rows.
tally_bad = retired_bad = 0
SKIP_TALLY = INDEX_SHAPE == "list"
for e in [] if SKIP_TALLY else entries:
    rows = rows_of(os.path.join(FEAT_DIR, e["file"]))
    live = [r for r in rows if r[5] == "0"]
    retired = [r for r in rows if r[5] == "1"]
    head = e["tally"].split("·")[0]
    # Compare the tally PER STATUS, not by total. Comparing totals looks equivalent and is
    # not: flipping a ◐ to a ✓ inside a feature file and rewriting "7 ✓, 1 ◐" as "8 ✓"
    # leaves the sum at 8 and passes a total-only check — which is exactly the drift this
    # invariant exists to catch, and exactly what a total-only version of it let through
    # when the mutation check was run. "✓ *" is its own status and must not collapse into
    # "✓", so the alternation puts the longer token first.
    #
    # "✓ int" is a second decorated variant, and it is here for the same reason. ighweld-2026's map
    # documents it as "validated at the integration layer" and carries three such rows (spec 100).
    # It is a real distinction, not drift, so the map must be able to keep it — and the tally is
    # built from the rows' literal status strings, so a token the alternation does not know can
    # never be tallied correctly. Without this the owning feature's row is unsatisfiable: every
    # index it could be given claims {"✓": 3} while the file holds {"✓ int": 3}.
    #
    # LONGEST FIRST IS LOAD-BEARING, and it is the whole of the change. With "✓" ahead of it,
    # "3 ✓ int" matches as "3 ✓" and the accommodation silently does nothing — the gate would still
    # fail, and it would fail claiming the index undercounts a status it had just been taught.
    claimed = {}
    for n, st in re.findall(r"(\d+)\s+(✓ \*|✓ int|✓|◐|☐)", head):
        claimed[st] = claimed.get(st, 0) + int(n)
    actual = {}
    for r in live:
        actual[r[4]] = actual.get(r[4], 0) + 1
    m = re.search(r"(\d+) retired", e["tally"])
    claimed_ret = int(m.group(1)) if m else 0
    if claimed != actual:
        fmt = lambda d: ", ".join(f"{v} {k}" for k, v in sorted(d.items())) or "nothing"
        bad("tally counts live rows", f"{e['file']}: index says [{fmt(claimed)}], file has [{fmt(actual)}]")
        tally_bad += 1
    if claimed_ret != len(retired):
        bad("retired named separately", f"{e['file']}: index says {claimed_ret}, file has {len(retired)}")
        retired_bad += 1
if not tally_bad:
    if SKIP_TALLY:
        na("tally counts live rows, not retired", "the list-shape index carries no tally column")
    else:
        ok(f"tally counts live rows, not retired ({len(entries)} features)")
if not retired_bad:
    if SKIP_TALLY:
        na("retired rows named separately", "the list-shape index carries no tally column")
    else:
        ok("retired rows named separately where present")

# --- 5. the id ranges in the index cover exactly that file's ids ----------------------
# An id may carry a letter suffix: SC-023a, SC-033b. .claude/rules/scenarios.md
# permits them (a sub-scenario carved from an existing row keeps its parent's
# number), and both spec_active.py and the traceability gate read them. This test
# did not: it called int() on the whole tail and CRASHED with a traceback rather
# than failing, on the first split project that had one. msroute has none, which
# is why it went unseen until film-i-vast was split on 2026-09-03.
#
# The suffix is dropped for range arithmetic on purpose. A range "SC-030..035"
# is a statement about numbers, and SC-033b lives inside it — comparing the
# numeric part is what makes the index's range and the file's contents
# comparable at all.
def _num(tok):
    """Numeric part of an id tail, suffix ignored. '033b' -> 33."""
    digits = "".join(c for c in tok if c.isdigit())
    return int(digits) if digits else None

def expand(spec):
    out = set()
    for part in spec.split(","):
        part = part.strip()
        if ".." in part:
            a, b = part.split("..")
            lo, hi = _num(a[3:]), _num(b[3:] if b.startswith("SC-") else b)
            if lo is not None and hi is not None:
                out |= set(range(lo, hi + 1))
        elif part.startswith("SC-"):
            n = _num(part[3:])
            if n is not None:
                out.add(n)
    return out


range_bad = 0
for e in [] if SKIP_TALLY else entries:
    claimed = expand(e["ids"])
    actual = {n for n in (_num(r[0][3:]) for r in rows_of(os.path.join(FEAT_DIR, e["file"]))) if n is not None}
    if claimed != actual:
        bad("index id-ranges match the file", f"{e['file']}: only-in-index {sorted(claimed-actual)}, only-in-file {sorted(actual-claimed)}")
        range_bad += 1
if not range_bad:
    if SKIP_TALLY:
        na("index id-ranges match each file", "the list-shape index carries no id-range column")
    else:
        ok("index id-ranges match each file's ids exactly")

# --- 6. back-link at the top of every feature file ------------------------------------
no_backlink = []
for f in files_on_disk:
    first = open(os.path.join(FEAT_DIR, f), encoding="utf-8").readline()
    if "](../SCENARIOS.md)" not in first:
        no_backlink.append(f)
if no_backlink:
    bad("back-link on every feature file", ", ".join(no_backlink))
else:
    ok(f"back-link on every feature file ({len(files_on_disk)})")

# --- 7. every slug a file's headings cite appears inside that file ---------------------
# The reminder hook finds a feature by grepping for the slug. A heading that cites a slug the
# body never repeats is fine; a slug cited NOWHERE in the file is a feature the hook will
# report as an unmapped scenario gap on every future spec.
slug_bad = []
for f in files_on_disk:
    text = open(os.path.join(FEAT_DIR, f), encoding="utf-8").read()
    cited = set()
    for h in re.findall(r"^#{1,3} .*$", text, re.M):
        cited |= set(SLUG_RE.findall(h))
    for s in cited:
        if s not in text:
            slug_bad.append(f"{f}: {s}")
if slug_bad:
    bad("cited slugs appear in their file", "; ".join(slug_bad))
else:
    ok("cited slugs appear in their file")

# --- 8. a nested sub-feature is not indexed separately --------------------------------
# It travels inside its parent's file. An index row of its own would claim its rows twice.
nested = set()
for f in files_on_disk:
    text = open(os.path.join(FEAT_DIR, f), encoding="utf-8").read()
    for h in re.findall(r"^## .*$", text, re.M):
        nested |= set(SLUG_RE.findall(h))
double = [s for s in nested if f"scenarios/{s}.md" in index_text]
if double:
    bad("nested sub-features not indexed separately", ", ".join(double))
else:
    ok(f"nested sub-features not indexed separately ({len(nested)} nested)")

# --- 9. strike-through and retired status agree ---------------------------------------
# Not done in awk: BSD awk compares multi-byte strings wrongly — "☐" == "—" evaluates TRUE,
# so an awk version of this check reports every live row as a violation. Found writing it.
all_rows = rows_of(INDEX, *[os.path.join(FEAT_DIR, f) for f in files_on_disk])
mismatch = [r[0] for r in all_rows if (r[4] == "—") != (r[5] == "1")]
if mismatch:
    bad("strike-through matches retired status", ", ".join(mismatch))
else:
    ok(f"strike-through matches retired status ({len(all_rows)} rows)")

print()
if FAILED:
    print(f"{len(FAILED)} invariant(s) violated — the index and the feature files disagree")
    sys.exit(1)
print("index and feature files agree on all nine invariants")
sys.exit(0)
