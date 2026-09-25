# Spec interview — 050-reliability-fixes

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. The base is auto-answered with the recommended option. The spec was flagged hardened (updater + consent state machines, capability surface), so the overflow questions went to the developer (Johan, 2026-09-25).

## Q1 — Scope boundary
**Q:** Does this spec change the model family?
**A:** No. Keep gemma3 and bump the Ollama runtime only (Johan, kickoff AskUserQuestion).

## Q2 — Scope boundary (out)
**Q:** Are the React/Vite/Tailwind majors in scope?
**A:** No. Safe upgrades only, in spec 052 (Johan).

## Q3 — Primary actor & trigger
**Q:** Who hits these bugs?
**A (auto):** Every end user. The updater bug hits everyone on each update, and the consent bugs hit first-run users on a slow or full disk.

## Q4 — Happy path (updater)
**Q:** What does success look like after "Starta om och installera"?
**A (auto):** The app closes and reopens on the new version within seconds. No failure banner.

## Q5 — Error semantics (updater)
**Q:** When is InstallFailed recorded?
**A (auto):** Only when `install` returns Err or `check` no longer returns the update. That reuses the existing Swedish failure + retry surface.

## Q6 — Four states (consent recovery)
**Q:** After cancel → Fortsätt, what does the user see?
**A (auto):** The progress screen immediately, then success. A fresh FelDiskFull is shown if the disk is still full, never the stale screen.

## Q7 — Error panel Avbryt
**Q:** Where does the error-panel Avbryt lead?
**A (auto):** Back to the welcome screen (consent = avbryt), where the user can start again. It is a no-op while a download runs.

## Q8 — Pull cap (overflow)
**Q:** What replaces the 300 s total pull cap?
**A:** The stall detector only (90 s silence), matching the tier pulls (Johan).

## Q9 — Data model
**Q:** Are any persisted fields added?
**A (auto):** None. `settings.json` stays at two keys and the consent record is unchanged in shape.

## Q10 — Validation (docx label)
**Q:** Which model name goes in the .docx header?
**A (auto):** The dispatch-pinned `model_id` string, verbatim (it comes from the closed tier map, so no injection surface).

## Q11 — Copy
**Q:** Which download size is shown?
**A (auto):** "cirka 3,3 GB" (Swedish decimal comma). It has one TS source, pinned to the Rust tier badge by a test.

## Q12 — Exit behaviour (overflow)
**Q:** Should Cmd+Q during processing ask for confirmation?
**A:** No. Quit and stop Ollama (Johan).

## Q13 — Authorization (overflow)
**Q:** Should the WebView keep shell spawn/kill permissions?
**A:** No. Remove both (Johan).

## Q14 — Concurrency
**Q:** What happens with a double click on Försök igen during a pull?
**A (auto):** The existing `Downloading` idempotency guard makes the second call a no-op. It is kept, and a test covers it.

## Q15 — Concurrency (exit)
**Q:** Can the shutdown run twice (CloseRequested and then Exit)?
**A (auto):** The cleanup lives only in `RunEvent::Exit`, which fires once. CloseRequested just requests exit.

## Q16 — Integration points
**Q:** Which seams change?
**A (auto):** The tauri-plugin-updater install/restart, the Ollama `/api/tags` + `/api/pull`, the Tauri capability file, and the TS↔Rust status events.

## Q17 — Edge case (tags failure)
**Q:** What if `/api/tags` fails transiently at boot?
**A (auto):** 3 attempts with 1 s/2 s backoff, then FelOvantat, whose existing retry re-runs the boot.

## Q18 — Non-functional
**Q:** Is there a latency budget for the extra retries?
**A (auto):** At most 3 s added only on failure. The happy path is unchanged.

## Q19 — Acceptance
**Q:** What is the measurable definition of done?
**A (auto):** One failing-then-passing test per FR, green clippy/fmt/tsc/eslint, and a Stryker run on the changed TS.

## Q20 — Reversibility
**Q:** What is the rollback story?
**A (auto):** It is a code-only change. Reverting the commit restores 0.4.1 behaviour, and there is no data migration.

## Q21 — Non-goals
**Q:** Does this spec add new Swedish statuses or screens?
**A (auto):** No. It adds only two inline error strings (FR-009).
