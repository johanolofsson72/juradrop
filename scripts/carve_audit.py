import os, re, sys, collections

reg = open(os.environ["REG"], encoding="utf-8", errors="replace").read()
budget = int(os.environ.get("BUDGET") or 2)

ROW = re.compile(r"^- \[([ xX/!])\] +\*{0,2}([^\s—*]+)", re.M)
rows = {}
for line in reg.split("\n"):
    m = ROW.match(line)
    if m:
        rows[m.group(2)] = line

# "carved by H7u", "Found by 091", "From H2" -- the id is the first token after the phrase.
ATTR = re.compile(r"(?:carved by|found by|opened by|from)\s+\**(?:spec\s+)?([A-Za-z]?[0-9][0-9A-Za-z.]*)", re.I)
parent, unresolved = {}, []
for rid, line in rows.items():
    m = ATTR.search(line)
    if not m:
        continue
    # A trailing period is sentence punctuation, not part of the id: "carved by 073." cited 073.
    pid = m.group(1).rstrip(".")
    if pid == rid:
        continue
    if pid in rows:
        parent[rid] = pid
    else:
        unresolved.append((rid, pid))

kids = collections.Counter(parent.values())
over = sorted(((n, p) for p, n in kids.items() if n > budget), reverse=True)

def depth(rid):
    seen, d = set(), 0
    while rid in parent and rid not in seen:
        seen.add(rid); rid = parent[rid]; d += 1
        if d > 50: break
    return d

deep = sorted(((depth(r), r) for r in rows if depth(r) > 2), reverse=True)

def chain(rid):
    out, seen = [rid], {rid}
    while rid in parent and parent[rid] not in seen:
        rid = parent[rid]; out.append(rid); seen.add(rid)
    return " -> ".join(reversed(out))

bad = 0
if over:
    bad += 1
    print(f"[CARVE BUDGET] {len(over)} row(s) carved more than {budget} (carve-budget.md section 2):")
    for n, pid in over[:10]:
        ks = sorted(k for k, v in parent.items() if v == pid)
        print(f"  {pid} produced {n}: {' '.join(ks[:12])}")
if deep:
    bad += 1
    print(f"[CARVE DEPTH] {len(deep)} row(s) past depth 2 (section 3 — there is no depth 3):")
    for d, rid in deep[:10]:
        print(f"  {rid} is depth {d}:  {chain(rid)}")
if unresolved:
    print(f"[CARVE ATTRIBUTION] {len(unresolved)} row(s) name a parent this register does not hold:")
    for rid, pid in unresolved[:10]:
        print(f"  {rid} cites {pid}")
    print("  Reported, not dropped: a mis-parsed attribution and no attribution look the same otherwise.")
if not over and not deep:
    extra = f" ({len(unresolved)} unresolved attribution(s) above.)" if unresolved else ""
    print(f"carve shape: clean — {len(parent)} attributed row(s), none over {budget} carves, none past depth 2.{extra}")
sys.exit(1 if bad else 0)
