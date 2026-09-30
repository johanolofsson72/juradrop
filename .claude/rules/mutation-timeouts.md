---
paths:
  - "**/stryker-config*.json"
  - "**/stryker.conf*"
  - "**/.gremlins.y*ml"
  - "**/*mutation*"
  - "**/StrykerOutput/**"
  - "**/reports/mutation/**"
---

# Mutation timeouts rule (how to read a mutation score without being lied to)

A mutation score is a claim that the tests noticed a deliberate bug. Five traps make that claim
wrong, and all but one of them make it wrong in the flattering direction. Traps 1-3 and 5 are
specific to mutation tools. Trap 4 is the principle they share, and scripts across the template cite
it for things that have nothing to do with mutation.

## Trap 1 — A timed-out mutant is counted as detected

A mutant that made the suite hang was not caught. Nothing asserted anything; the run just stopped.
Both tools the template uses still score it as a win:

- **Stryker** (.NET and JS) reports `detected / valid`, where detected is `Killed + Timeout`. One
  measured gate: strict 97.69%, Stryker 100.00%.
- **gremlins** (Go) at its default `--timeout-coefficient` reported 127 mutants TIMED OUT and printed
  `Test efficacy: 100.00%`. At `--timeout-coefficient=20` the same run was 89.09% with 18 survivors
  (hetznerradar F003).

**Do:** print the Timeout count next to every score. Compute the strict figure when it matters:
`Killed / (Killed + Survived + Timeout + NoCoverage)`. Run gremlins at `--timeout-coefficient=20` or
higher. Give Stryker enough headroom (`additional-timeout` in Stryker.NET, `timeoutMS` /
`timeoutFactor` in StrykerJS) that a timeout means a hang, not a slow machine.

## Trap 2 — The headline is not comparable across runs

Timeouts vary from run to run, and a timed-out mutant counts as neither killed nor lived. So the
percentage moves with the timeouts, not with the tests. More timeouts can print a higher number:

- Same code, same package: `Lived 6 / Timed out 98 → 100.00%`, then `Lived 0 / Timed out 51 →
  99.42%` (F024).
- At coefficients 20 and 40, all four mutants in one file came back TIMED OUT. Run by hand, three
  were killed in about 5 s and one was equivalent. Two runs minutes apart gave 87.32% with 1
  timeout and 100.00% with 51 (F071). The coefficient moves the problem; it does not fix it.
- Stryker, two runs, both 90.91%, disagreeing on seven mutants (`.claude/docs/testing.md`).

**Do:** read the Survived/Lived list, never the percentage alone. Compare per-mutant verdicts between
runs. Re-run every timed-out mutant by hand, or in isolation, before counting it either way.

## Trap 3 — The run nobody waits for

The module that most needs the gate is often the one with the slowest tests. hetznerradar's
`internal/watch` took 11 hours under gremlins at face value and 1m46s under `GOFLAGS=-short`,
because one stress test was 234 of the package's 242 seconds and gremlins cannot pass test flags
through (F021). `internal/store` under `-race` went past 40 minutes for the same reason (F063).

The fix (the flag) changes what is measured. Under `-short` the stress test does not run, so a
mutant only it would kill survives.

**Do:** carry the flag with the number (`89% under -short`) and name the tests it excludes. Read a
survivor that only an excluded test could kill as an artefact of the flag, not a gap. Never let an
infeasible run quietly become a skipped one.

## Trap 4 — An unmeasured state and a clean state must never render identically

A timeout is an unknown. Scoring it as a kill is one case of a general failure: something that was
not measured is reported in the same words, or with the same exit code, as something measured and
found clean. The direction of the error is always toward a green light, so nobody goes looking.

It looks like this outside mutation testing:

- a job that has never run shown as "0 days since" (`scripts/maintenance-due.sh`);
- a suite that could not be detected reported as a pass (`scripts/project-maintenance.sh`);
- an enumeration that parses nothing, such as a regex in the wrong language or an attribution it
  cannot read, reporting "no findings" (`scripts/lane_status.py`, `carve-budget-rationale.md`);
- a gate with nothing to mutate printing "No results to report" as if it passed (F026);
- a conclusion kept after its premise stopped being checked (`scripts/bash_write_targets.py`).

**Do:** give the unknown state its own word and its own exit (`unmeasurable`, `never run`, exit 3),
distinct from both pass and fail. Then **prove the detector bites before trusting its silence**:
run a control, a case you know is there, first. An empty result and a probe that never ran look
identical, and a guard widened by a fix must be shown to still reject what it should. A detector
earns belief only after it has found a known positive.

## Trap 5 — A coverage artefact reads as a gap

gremlins reports a `case` arm in a tagless Go `switch` as NOT COVERED even when tests kill the
mutant. Go emits a coverage block for the case body, not for the case expression, so gremlins
skips it. This was proven twice in hetznerradar (F023). A reader who trusts the report writes a test
that already exists.

**Do:** before writing a test for a NOT COVERED or surviving mutant, apply the mutation by hand and
run the suite. If it fails, the tool is wrong. Record that and write no test.

## Checked

`scripts/validate-rule-citations.sh` fails when a file cites a rule or doc that does not exist, or a
trap this file does not define. Until spec 041 this rule was cited in ten places and existed in none.
