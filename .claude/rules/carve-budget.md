# Carve budget rule (the register has to converge)

Every other rule pushes toward creating rows; this is the half that says when to stop. The **carve ratio** (rows added ÷ rows ticked) above 1.0 grows the backlog without bound, because the work produces the rows. Measurements across five projects, the `H7` 122-row cascade, and full reasoning: `.claude/docs/carve-budget-rationale.md`.

## The contract (BLOCKING)

### 1. A finding is recorded, not rowed

The normal outcome of finding something is to write it down and keep going:

```bash
bash scripts/finding.sh --add "<one line>" --spec 031 --kind gap
```

It lands in `specs/FINDINGS.md` (git-tracked). Dispositions, in order: (1) **fix it inside the current spec** when that is smaller than recording it; (2) **record it as a finding** — the default; (3) **carve a row immediately** — the exception, only for work that blocks the next spec and cannot wait.

### 2. Findings are reviewed every 5 specs, and only the review grows the register

Every 5 ticked specs (the cadence `maintenance-due.sh` tracks) the open findings are presented as **one batch** and the developer decides per finding: fix now, make it a row, or drop it. An empty ledger means no review is due. **`SPEC_CARVE_BUDGET`** caps immediate carves (default 2; 0 is legitimate) — a ceiling on the exception, not an allowance.

### 2b. At review time, ask whether the row already exists

Run `bash scripts/register-similarity.sh --text "<the row you are about to write>"` during the batch review. It is a **report, never a gate** (local embeddings, no network); it does not group rows by subject — that is a `grep` for the filename.

### 3. Carve depth stops at 2

A row carved by an original spec is depth 1; carved by a depth-1 row is depth 2. **No depth 3** — that is a convergence stop. Record depth on the row: `— carved by H7u (d2)`; no marker = depth 0.

### 4. Harness defects belong to the template, not to the product register

A defect in `.claude/**`, `scripts/**`, a hook, guard or skill goes to the **template repo** (`/Users/jool/repos/Claude`) register and reaches projects via sync. The product register carries one standing row, `T0 — harness-defects`, pointing at blocking template rows — ticked when nothing blocks, never carved from. Exception: a harness defect blocking the current spec right now → fix in place **and** file the template row in the same commit.

### 4b. All three limits are measured

`bash scripts/register-convergence.sh --carves` measures carves per spec and depth. Depth is **derived from the attribution**, never trusted from a marker. `carved by <id>` is canonical; `found by`, `opened by`, `from` are accepted. A row citing a missing parent is **reported, never dropped**. `scripts/project-maintenance.sh` reports it as a finding, never fails a build on it.

### 5. The register reports its own convergence

`scripts/register-convergence.sh` (in `project-maintenance.sh` and at SessionStart): **< 1.0** converging; **1.0–1.3** flat, reported; **≥ 1.3 over 10+ ticked rows** diverging → **convergence stop**.

### 6. The convergence stop

A legitimate stop (`.claude/rules/continuous-execution.md`). Finish the current spec, then report:

```
**Convergence stop — the register is growing faster than it closes**

- Carve ratio: <N> over the last <W> ticked rows (threshold 1.3)
- Open rows: <before> → <now>
- The <K> heaviest carvers: <row ids and what each produced>
- Deepest carve chain: <root> → … → <leaf> (depth <D>)

Three ways out, pick one:
1. Freeze carving — no new rows until open rows fall below <target>. Findings go to the run log.
2. Batch — fold the <M> open spec-only rows into one consolidated row.
3. Cut — the rows that no longer matter get deleted, not deferred. Name them.
```

The developer decides; Claude does not silently keep carving.

### 7. Deleting a row is allowed

A row that no longer describes wanted work may be **deleted**, with a one-line Register history entry naming it and why (git history and `INDEX.pending.md` keep the trail).

## What this rule forbids

- Turning a finding into a row on the spot — record it; an immediate carve needs a reason naming why it cannot wait.
- Treating the 2-carve ceiling as an allowance; the expected carves for an ordinary spec is **zero**.
- Carving a third row from one spec without folding the rest into one.
- Carving at depth 3.
- A harness/tooling defect on a product register as anything but the standing `T0` row.
- Continuing past a diverging carve ratio without telling the developer.
- "The finding was real" as sufficient reason for a row.

Surfacing stays governed by `.claude/rules/validation-followup.md`; this rule governs rowing. Checkpoints (`.claude/rules/spec-hardening.md`) file one consolidated row.
