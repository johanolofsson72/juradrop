# Lane handoff rule (two machines, one file — never a person as the transport)

**This rule is inert on a single-lane project.** With one developer there is no other session
to reach, the hook prints nothing, and nothing below applies. It costs a solo project exactly
zero. Read on only where a project runs two or more developers against one register
(`.claude/rules/spec-register.md`, "Two lanes").

Two developers on two machines share a git repo and nothing else. When one session finds
something the other needs to know, there are two routes and only one of them works:

- **The wrong route:** write the finding in the chat and let the developer paste it into the
  other session. That makes a person the transport between two machines that already share a
  disk. The finding then lives in a transcript nobody can search, it arrives only if somebody
  remembers to carry it, and it is gone at the next `/clear`.
- **The right route:** write the finding in the file that owns that kind of information,
  commit, push. The other machine reads it at its next session start, by itself.

This rule says which file owns what.

## Where each kind of finding belongs (BLOCKING)

| The finding | The file | Why that one |
|---|---|---|
| Belongs to a row that already exists | `specs/INDEX.pending.md` under that row's heading | The row is a pointer; the diagnosis lives in the archive (`.claude/rules/spec-register.md`) |
| Is work no row covers | A **new row in `specs/INDEX.md`**, owner-tagged | The register is the list of what gets built. A finding with no row is work nobody has taken |
| Only someone outside the team can decide | The project's open-questions file, with a `**Blocks:**` line | That file holds only what is unanswered, and it is where they read |
| Is something deliberately deferred | The project's deferral log (e.g. `specs/PHASE-DEBT.md`) | No line, no deferral |
| Is something the next session on the **same** spec needs | `<spec-dir>/run-log.md` | Survives `/clear`, but only within that spec — the other lane never reads it |

The last row is the one most often used wrongly. `run-log.md` is memory inside a spec, not a
channel between developers. A finding parked there is written, saved, pushed — and addressed
to nobody. `CLAUDE.md` records the same failure for a diagnosis left in a run log.

## The `**Blocks:**` line (machine-read)

Each open question carries one line directly under its heading:

```markdown
## 15. Which of two buyers is the invoice recipient?

**To:** the client. **Blocks:** register row 008b — not as a start gate, but before the first
real invoice is issued.
```

`scripts/lane_status.py` reads `register row <id>` out of that line and crosses it against the
register, so it can say at every session start which unanswered question is holding an
**unticked** row. A question whose row is ticked is not reported — it is no longer in anyone's
way.

A question with **no** `**Blocks:**` line is reported as unmapped rather than skipped: a
missing mapping is the thing worth fixing, and an enumeration that silently drops what it
cannot parse reports a clean project and a broken one identically
(`.claude/rules/mutation-timeouts.md`, trap 4).

Write `**Blocks:** no register row — <why>` when the answer holds up no build. That is a real
statement, not an empty field.

The parser accepts the Swedish spellings (`**Blockerar:**`, `registerrad N`) alongside the
English, because the project this was extracted from keeps a customer-facing question file in
Swedish. A parser that read one language would have reported "no open questions" on a file
full of them.

## Asking outright: "is there anything for me to do?"

```bash
bash scripts/lane-status.sh              # your lane, from SPEC_OWNER
bash scripts/lane-status.sh --owner sam  # the register through the other developer's eyes
```

The same question put to Claude in the terminal reaches the `lane-status` skill, which runs
that script and answers with a recommendation rather than a menu. It reports: your row, the
other lane's row, what is unclaimed with every dependency ticked, what is held and why, which
open questions hold a row, and who committed what this week.

There is exactly one engine, `scripts/lane_status.py`. The hook renders the brief at session
start, the script the full report on demand. Two readers of one register that could answer
differently about who owns what is precisely what `.claude/rules/spec-register.md` warns
about — so one parser, two renderings, never two implementations.

Neither resolves "which spec is active". `scripts/spec_active.py` owns that question and the
PreToolUse guards enforce its answer.

## What the session-start hook shows

Only when the register actually carries an owner tag, and only when there is something to say:

1. **What the other lane holds** — their `- [/]` row or their next `- [ ]`, or that they have
   none. That the other lane is free is information: it is the state in which somebody takes
   an unclaimed row without saying so.
2. **Unclaimed rows whose `needs` are all ticked** — what can actually start today.
3. **Unanswered questions holding an unticked row**, per above.
4. **Whether upstream is ahead of this machine** — read from the ref already on disk, no extra
   network round. Writing to the register from a stale base is how two lanes get conflicts in
   the one file both must be able to trust.

## Claiming a row

An owner tag is last on the register row: `— @sam`. Putting a tag on an **unclaimed** row is
ordinary — it is how somebody says "I'll take it". Moving a tag that is already there is not:
the other lane's row is not yours to take, tick, or renumber
(`.claude/rules/spec-register.md`). Propose, and let the owner answer.

When Claude assigns a row, it writes that as a **proposal in the register**, not as a decision
in the chat. Changing a tag takes the developer a second; asking first costs a round trip and
a wait.

## The merge cost is in the coordination files, not the code

Measured on agentcrm over the two weeks both lanes ran (2026-08-20 → 09-02), the files both
developers touched most were not source files:

| File | Touches | Johan | David |
|---|---|---|---|
| `specs/INDEX.md` | 117 | 70 | 47 |
| `specs/INDEX.pending.md` | 50 | 17 | 33 |
| `specs/SCENARIOS.md` | 49 | 30 | 19 |
| `specs/PHASE-DEBT.md` | 25 | 10 | 15 |

Two source files made the top fifteen. So the hours spent merging are mostly two people appending
to four markdown files, and git calling every append at the same end a conflict.

Those files are **lists**, and two lanes appending different entries is two additions, not a
disagreement. `bash scripts/install-lane-merge-drivers.sh` sets `merge=union` on them in
`.gitattributes` (a built-in strategy — nothing to register per clone, unlike a custom merge driver,
which every clone has to register by hand before it does anything).

**The trade, stated plainly.** `union` never reports a conflict; it keeps both sides. That is right
for an append and wrong when both lanes edit the *same* row — there you get the row twice instead of
a conflict marker. Two things bound it: this rule already forbids touching the other lane's row, and
`scripts/validate-register-ids.sh` fails on a duplicated id. **Run that after every merge** — it is
the gate that makes the trade a good one. `scripts/test-lane-merge-drivers.sh` asserts both halves,
the clean append and the duplicated row, so the risk is pinned by a test rather than remembered.

`specs/SCENARIOS.md` is deliberately **excluded**: it carries Mermaid diagrams, and union would
interleave two graphs into a block that renders as nothing while reporting a clean merge. A map that
contended belongs in the split layout (`.claude/rules/scenarios.md`), where each lane owns its own
feature file and the contention goes away structurally rather than being merged around. agentcrm's
map is 254 KB in one file — ten times the context-cost canary — so that split is overdue on its own
merits.

## Bringing a lane level again (`scripts/lane-catchup.sh`)

A lane that sets `CLAUDE_TEMPLATE_AUTOSYNC=0` — which the second machine is told to
do, so the two do not race each other's config commits — receives nothing on its
own. When the other lane changes the rules or the shared machinery, this is the one
command that says what is missing:

```bash
bash scripts/lane-catchup.sh            # report only
bash scripts/lane-catchup.sh --apply    # also make the two machine-local fixes
```

It checks, in this order: the permission denies that make ordinary commands prompt,
the repository's position against origin, whether the shared machinery landed, the
nightly cron (a crontab entry is not in git), and what this lane owns.

**The order is the point.** The first draft of this was a written list sent to a
person, and it put the permission fix fourth — so the developer approved a prompt
per command on the way to the step that stops the prompts. It also ended with
"report back", which makes a person the transport between two machines that already
share a disk: the thing this rule exists to remove. A finding that concerns the
other lane goes in `specs/INDEX.pending.md` or a new row, committed and pushed.

## What this rule forbids

- Reporting a finding that concerns the other lane **only** in the chat. The chat may summarise
  what a file already says — never be the only place it exists.
- Asking the developer to forward something to the other developer's session. That is the
  transport this rule exists to remove.
- Putting a cross-lane finding in `run-log.md` and calling it written.
- Writing to the register without pulling first, once the hook has said upstream is ahead.
- Adding a new file for a kind of information an existing file already owns. There are five
  files in the table above, and a sixth is almost never needed.
