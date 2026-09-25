# Spec interview — 051-startup-tips-whats-new

Anti-drift interview per .claude/rules/spec-interview.md.
Mode: AUTO. The base is auto-answered with the recommended option. The spec is not flagged: it is a light track with no hardened trigger, no PII, no network and no new entity in Rust. The scope and the feature set were chosen by Johan at kickoff.

## Q1 — Scope boundary
**Q:** Does this include release notes after an update?
**A:** Yes. Johan picked "Nytt i versionen" alongside "Tip on every launch" at kickoff.

## Q2 — Out of scope
**Q:** Can tips or notes be fetched online?
**A (auto):** No. They are bundled only, because of Principle I, which forbids new outbound calls.

## Q3 — Primary actor & trigger
**Q:** When does the card appear?
**A (auto):** On every launch, once the status is `klar` and the zone grid is visible. It never appears over the wizard.

## Q4 — Happy path
**Q:** What does success look like?
**A (auto):** A one-line Swedish tip in a quiet card above the zones, with "Nästa tips" and ×. After an update, "Nytt i version X" with bullets.

## Q5 — Data model
**Q:** What is persisted?
**A (auto):** `localStorage['juradrop-startup'] = { tipsEnabled: boolean, nextTip: number, lastSeenVersion: string | null }`.

## Q6 — Validation
**Q:** What if the stored JSON is garbage?
**A (auto):** Sanitize it field by field and fall back to the defaults. Never throw.

## Q7 — Four states
**Q:** What are the success, error, empty and loading states?
**A (auto):** Success: the card is shown. Error: storage failure → defaults, the card still shows, and it is logged to the console only. Empty: a version without notes → a tip instead. Loading: render nothing until the version resolves.

## Q8 — Error semantics
**Q:** Can `getVersion()` fail?
**A (auto):** Yes, in theory. Fall back to the build-time version, so the card logic never blocks.

## Q9 — Authorization
**Q:** Are there any permissions?
**A (auto):** N/A. It is a single local user; `core:app:default` is already granted.

## Q10 — Concurrency
**Q:** Can two windows race?
**A (auto):** N/A. It is a single-window app.

## Q11 — Integration points
**Q:** What does it touch?
**A (auto):** App.tsx (zone-grid path), the Wizard (to mark that first-run was needed), SettingsPanel (the new "Start" section), and Tauri `getVersion`.

## Q12 — Edge: rotation
**Q:** Is the order random or rotating?
**A (auto):** Rotating, persisted so the next launch shows the next tip, and the list cycles fully.

## Q13 — Edge: upgrade from ≤ 0.4.1
**Q:** How are old users, who have no stored version, detected?
**A (auto):** If the wizard wasn't needed this launch, the user is treated as an upgrader and shown what's new.

## Q14 — Non-functional
**Q:** Is there a performance budget?
**A (auto):** Constant-time work at launch and no layout shift once rendered (it appears with the grid, not after it).

## Q15 — Acceptance
**Q:** What is the definition of done?
**A (auto):** SC-157..165 are covered by tests, PBT on sanitize, and vitest is green.

## Q16 — Reversibility
**Q:** What is the rollback story?
**A (auto):** It is frontend-only. Remove the component and leave the key harmlessly orphaned.

## Q17 — Tone
**Q:** What should the copy sound like?
**A (auto):** Du-form, direct, no exclamation marks, no emojis, per MASTER.md tone of voice.

## Q18 — Accessibility
**Q:** How is it reached from the keyboard?
**A (auto):** Real buttons in DOM order before the zones, with Swedish aria-labels. No focus trap and no autofocus, so the zones stay the first thing to act on.
