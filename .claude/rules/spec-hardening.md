# Spec hardening rule (risk-tier above "full", + cross-spec integration checkpoints)

**Hardened** is the tier above the full track (`.claude/rules/feature-pipeline.md`): the entire full pipeline **plus** four additions. A periodic **integration checkpoint** covers the seams between specs. Long form (reasoning, interaction prose): `.claude/docs/spec-hardening-rationale.md`.

## When a spec is HARDENED (BLOCKING — any ONE trigger fires it)

Classify at triage, right after `/speckit-specify`:

1. **Risk-domain keyword** — authentication / authorization, payments / money movement, PII or secrets, file upload / parsing, or a **new external API surface** (public endpoint, webhook receiver, third-party integration).
2. **Full track + state machine / concurrency.**
3. **Explicit register marker** — the row carries `[hardened]` (`.claude/rules/spec-register.md`).
4. **Size threshold** — a **new entity/aggregate** OR an estimated **≥ 6 files** touched.

When in doubt, harden — it only adds verification.

## What HARDENING adds (BLOCKING — all four, on top of the full track)

Not "done" until all four have run:

1. **Threat-model pass (before implement).** `security-scanner` agent over the new surface + a STRIDE pass (Spoofing / Tampering / Repudiation / Information disclosure / Denial of service / Elevation of privilege) per new trust boundary, recorded in a `## Threat model` section of the spec. A threat with no mitigation is an open finding (`.claude/rules/validation-followup.md`).
2. **Expanded destructive + stress suite.** Top of the input-domain band, not the middle (`.claude/docs/testing.md`), plus a stress/load pass per `.claude/docs/stress-testing.md` (concurrency, large payloads, rate-limit / resource exhaustion). The four observable states (success / specific visible error / empty / loading) must hold *under stress*.
3. **Hard mutation-kill gate.** Stryker kill rate on the changed critical module(s) is a **blocking gate to tick the register** (`dotnet stryker` or stack equivalent). Below target = tests are theatre = not done. A timed-out mutant is not a kill: read the score per `.claude/rules/mutation-timeouts.md`.
4. **Adversarial review.** `security-scanner` in "assume it's exploitable, prove me wrong" mode + a `dotnet-reviewer` / language reviewer pass on the new trust boundaries + the built-in **`/security-review`** as an independent second opinion. Every flag gets an explicit fix/defer/dismiss decision.

These do not replace unit/integration/E2E/PBT/VRT/TLA+.

## Cross-spec integration hardening checkpoint (BLOCKING — every 5 feature specs)

Once 5 feature specs are ticked since the last ticked checkpoint, before the next feature spec, work a checkpoint row. Checkpoint, carved (`016a`, `carved by …`) and standing rows do not count; `scripts/checkpoint-cadence.sh` is the one count both readers use. Row: `- [ ] H1 — integration-hardening — checkpoint — full-system regression + security sweep after spec 005`. It runs:

1. **Full-system regression** — entire suite: unit + integration + E2E + visual-regression baselines.
2. **Cross-cutting security sweep** — `security-scanner` over the whole surface + `scripts/project-freshness.sh` (trufflehog + key-shape scan + dependency audits).
3. **Scenario-map reconciliation** — index + every `specs/scenarios/*.md` vs reality; drift starts a scenario interview (`.claude/rules/scenarios.md`).
4. **Mutation spot-check** — Stryker on the 2–3 most-changed critical modules since the last checkpoint.

A checkpoint is bounded by the carve budget: many findings → **one consolidated row**, never past depth 2 (`.claude/rules/carve-budget.md`). It ends with a status summary and stops like a spec. N = 5 unless the project set its own N at wizard time (recorded in register history); a register N or more feature specs past its last checkpoint with none pending is drift to surface.

## Fresh context for big specs — start with `/clear` (BLOCKING reminder)

Every full-track, hardened or checkpoint row begins in a fresh session. A hook cannot run `/clear`; `scripts/spec-register-orientation-hook.sh` prints the banner. When it fires and the session carries unrelated context: stop, tell the user to run `/clear`, resume in the fresh session. (Already fresh → proceed.)

## Interactions (one line each)

Hardened triggers are the strong prior for human overflow questions in the spec interview (`.claude/rules/spec-interview.md`); the additions are part of the same continuous task (`.claude/rules/continuous-execution.md`); every threat/adversarial/mutation finding is surfaced (`.claude/rules/validation-followup.md`); none of it becomes a CI workflow (`.claude/rules/github-actions.md`).

## What this rule forbids

- A payments / auth / PII / upload / new-external-surface spec on the plain full track without the four additions.
- Treating the `[hardened]` tag as decorative.
- Skipping the checkpoint because "the last five specs all passed".
- Downgrading the mutation gate to "nightly, optional" on a hardened spec.
- Powering through a full/hardened spec on a polluted context after the `/clear` banner fired.
- Wiring any hardening step as a GitHub Action. Local only.
