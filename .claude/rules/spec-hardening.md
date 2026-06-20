# Spec hardening rule (risk-tier above "full", + cross-spec integration checkpoints)

The pipeline tracks in `.claude/rules/feature-pipeline.md` (full / light / spec-only) size the *process* to the spec. This rule adds the tier **above** full — **hardened** — for specs whose blast radius justifies extra adversarial scrutiny, and a **cross-spec integration checkpoint** that fires as the project's surface area grows. Risk is not only per-spec: ten individually-fine specs can still rot at the seams. This rule covers both.

It layers on top of the existing rules — it never replaces them. A hardened spec still runs the entire full-track pipeline (`specify → clarify → elicit → plan → tasks → analyze → implement → tests → tla`); hardening is what gets *added*, not a different path.

## When a spec is HARDENED (BLOCKING — any ONE trigger fires it)

Classify at triage time, right after `/speckit-specify`. If **any** of these holds, the spec is hardened — escalate it above the full track:

1. **Risk-domain keyword.** The spec touches authentication / authorization, payments / money movement, PII or secrets handling, file upload / file parsing, or introduces a **new external API surface** (a new public endpoint, webhook receiver, or third-party integration). These are the domains where a bug is a breach, not a glitch.
2. **Full track + state machine / concurrency.** Any full-track spec that introduces non-trivial concurrency or a state machine — exactly the shape `/tla` exists to model. Hidden interleavings are where "works on my machine" ships a race.
3. **Explicit register marker.** The spec's row in `specs/INDEX.md` carries the `[hardened]` tag (see `.claude/rules/spec-register.md`). The author/wizard decided at triage time that this one needs the extra teeth, regardless of the mechanical triggers.
4. **Size threshold.** The spec creates a **new entity/aggregate** OR is estimated to touch **≥ 6 files**. Large surface = large attack surface; the destructive suite and review pass scale with it.

When in doubt, harden. Unlike the full/light/spec-only choice (where over-application fabricates false drift), hardening only *adds* verification — the worst case is spending review budget on a spec that turned out safe. That is the cheap direction to be wrong in.

## What HARDENING adds (BLOCKING — all four, on top of the full track)

A hardened spec is not "done" (per the `CLAUDE.md` Definition of Done) until **all four** of these have run, in addition to everything the full track already requires:

1. **Threat-model pass (before implement).** Run the `security-scanner` agent against the spec's new surface AND enumerate threats explicitly — a STRIDE-style pass (Spoofing / Tampering / Repudiation / Information disclosure / Denial of service / Elevation of privilege) over each new trust boundary the spec introduces. Record the threats and their mitigations in the spec (a `## Threat model` section). A threat with no mitigation is an open finding — surface it per `.claude/rules/validation-followup.md`, do not bury it.
2. **Expanded destructive + stress suite.** Raise the destructive-suite ceiling above the normal input-domain sizing (per `.claude/docs/testing.md`) — a hardened interactive function gets the **top of its band, not the middle** — AND add a stress/load pass per `.claude/docs/stress-testing.md` against the new surface (concurrency, large payloads, rate-limit / resource-exhaustion behaviour). The four observable states (success / specific visible error / empty / loading) must hold *under stress*, not just at rest.
3. **Hard mutation-kill gate.** For a hardened spec, the Stryker mutation kill rate on the **changed critical module(s)** is a **blocking gate to tick the register** — not the normal nightly/on-demand target. A green suite that kills no mutants does not pass. Run `dotnet stryker` (or the stack equivalent) on the changed modules before the spec is marked done; if the kill rate is below target, the tests are theatre and the spec is not done.
4. **Adversarial review agent.** Beyond the normal `/code-review`, run a dedicated adversarial pass — the `security-scanner` agent in "assume it's exploitable, prove me wrong" mode, plus a `dotnet-reviewer` / language reviewer pass focused on the new trust boundaries. Treat every flagged item as a finding requiring an explicit fix/defer/dismiss decision per `.claude/rules/validation-followup.md`.

These four are the hardening surcharge. They do not replace unit/integration/E2E/PBT/VRT/TLA+ — those still run because the spec is also full-track.

## Cross-spec integration hardening checkpoint (BLOCKING — every 5 completed specs)

Per-spec hardening cannot catch integration rot — two specs that are each fine can interact badly, and that risk compounds with every spec added. So the **project** gets a periodic hardening pass independent of any single spec.

**The rule:** after **every 5th completed spec** (specs 5, 10, 15, …), the next thing worked is an **integration-hardening checkpoint**, *before* the next feature spec starts. The checkpoint is a real register row — see the format in `.claude/rules/spec-register.md`:

```
- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after spec 005
```

The checkpoint is worked like any other row (run it, tick it, commit, push) and it does:

1. **Full-system regression** — the entire test suite (not just the changed module): unit + integration + E2E + visual-regression baselines. Integration is where AI code most often breaks at the seams; this is the seam check.
2. **Cross-cutting security sweep** — `security-scanner` agent over the whole surface + a `scripts/project-freshness.sh` run (trufflehog verified-secret scan + `npm audit` dependency-CVE report). Catches secrets and CVEs that accumulated across the last five specs.
3. **Scenario-map reconciliation** — verify `specs/SCENARIOS.md` still matches reality across all features built so far; a drift starts a scenario interview per `.claude/rules/scenarios.md`, it is not silently patched.
4. **Mutation spot-check** — run Stryker on the two or three most-changed critical modules since the last checkpoint; a collapse in kill rate means recent specs added code the tests do not actually exercise.

The checkpoint produces a status summary like a spec does, then stops (it is a legitimate per-row stop per `.claude/rules/spec-register.md`). N = 5 is the default cadence; a project may set its own N at wizard time (recorded in the register history), but the checkpoint is never silently skipped — a register that has passed a multiple of 5 with no checkpoint row is a drift to surface, not a thing to ignore.

## Fresh context for big specs — start with `/clear` (BLOCKING reminder)

A full-track or hardened spec is a long, context-heavy run (spec → clarify → elicit → plan → tasks → analyze → implement → a large test matrix → tla). Starting it on top of an already-loaded conversation means the implementation phase runs with a context full of stale, unrelated tokens — exactly the condition `CLAUDE.md`'s "Use `/clear` between unrelated tasks" warns against. So **every full-track or hardened spec begins in a fresh session.**

**Hard constraint — a skill or hook cannot run `/clear`.** `/clear` is a harness built-in; there is no tool and no hook action that clears context. So this rule is enforced by **reminder, not automation**:

- The `spec-register-orientation` hook (`scripts/spec-register-orientation-hook.sh`, SessionStart) inspects the next register row. When it is a **full-track**, **`[hardened]`**, or **checkpoint** row, it prints a loud banner: *start this spec in a fresh session — run `/clear` now.*
- The `project-wizard` and `sync-template` skills surface the same reminder when they hand off to the first/next spec.
- This rule is the source of truth the banner points at.

When you see that banner and the current session already carries unrelated context: **stop, tell the user to run `/clear`, and pick the spec back up in the fresh session.** Do not power through a hardened spec on a polluted context to "save a round-trip" — the context hygiene is the point. (If the session is *already* fresh — e.g. the banner fired at the very first SessionStart — there is nothing to clear; proceed.)

## How this interacts with the other rules

- `feature-pipeline.md` — defines the full/light/spec-only tracks. Hardened is the tier **above** full; the pipeline's triage table points here.
- `spec-register.md` — defines the `[hardened]` row tag, the checkpoint row format, and the every-5 cadence. This rule defines *what those rows mean and what they run*.
- `continuous-execution.md` — the hardening additions are part of the **same task** as the spec; the threat-model pass → impl → expanded tests → mutation gate → adversarial review do not get permission stops between them. The only stops are real ambiguity, hard blockers, and Allium/TLA+/threat-model **findings** (which always get surfaced per `validation-followup.md`).
- `validation-followup.md` — every threat-model finding, every adversarial-review flag, every mutation-gate failure is a finding surfaced for an explicit decision. Hardening that silently swallows its own findings is hardening theatre.
- `github-actions.md` — none of the hardening steps become CI workflows. Threat model, stress, mutation, adversarial review, and the integration checkpoint all run **locally**, on demand. A "hardening CI workflow" is exactly the sprawl that rule forbids.

## What this rule forbids

- Running a payments / auth / PII / upload / new-external-surface spec on the plain full track without the four hardening additions.
- Treating the `[hardened]` register tag as decorative — if it is on the row, the four additions are mandatory.
- Skipping the integration-hardening checkpoint because "the last five specs all passed." Each spec passing in isolation is exactly the condition the checkpoint exists to look past.
- Downgrading the mutation-kill gate to "nightly, optional" on a hardened spec — on hardened specs it is a blocking tick gate.
- Powering through a full/hardened spec on a context-polluted session after the `/clear` banner fired, instead of clearing.
- Wiring any hardening step as a GitHub Action. Local only.
