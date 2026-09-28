# Lane handoff rule (two machines, one file — never a person as the transport)

**Inert on a single-lane project** — with one developer there is no other session to reach and nothing below applies. It matters only where two or more developers share one register (owner tags, `.claude/rules/spec-register.md` "Two lanes"). Full rule, `**Blocks:**` line format, session-start hook output, merge-driver trade-off and catch-up procedure: `.claude/docs/lane-handoff-rationale.md` — read it before acting on a multi-lane project.

## Where each kind of finding belongs (BLOCKING, multi-lane only)

A cross-lane finding is written in the file that owns it, committed and pushed — never carried by a person between chats:

| The finding | The file |
|---|---|
| Belongs to an existing row | `specs/INDEX.pending.md` under that row's heading |
| Is work no row covers | A **new owner-tagged row in `specs/INDEX.md`** (against the carve budget) |
| Only someone outside the team can decide | The project's open-questions file, with a `**Blocks:** register row <id>` line (or `**Blocks:** no register row — <why>`) |
| Is deliberately deferred | The deferral log (e.g. `specs/PHASE-DEBT.md`) |
| Only the next session on the **same** spec needs it | `<spec-dir>/run-log.md` — memory inside a spec, never a channel between developers |

Tools: `bash scripts/lane-status.sh [--owner <name>]` (engine `scripts/lane_status.py`; `scripts/spec_active.py` owns "which spec is active"), `bash scripts/lane-catchup.sh [--apply]`, `bash scripts/install-lane-merge-drivers.sh` (`merge=union` on the list files — run `scripts/validate-register-ids.sh` after every merge; pinned by `scripts/test-lane-merge-drivers.sh`).

## What this rule forbids

- Reporting a cross-lane finding **only** in chat, or asking the developer to forward it to the other session.
- Parking a cross-lane finding in `run-log.md` and calling it written.
- Writing to the register without pulling first once the hook says upstream is ahead.
- Moving an owner tag that is already there (propose; the owner answers), or adding a new file for information an existing file already owns.
