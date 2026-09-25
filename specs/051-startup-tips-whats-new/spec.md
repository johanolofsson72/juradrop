# Spec 051 — startup-tips-whats-new

**Track:** light. It is a UI feature with a single actor and no concurrency. It has small linear state: shown → dismissed.
**Created:** 2026-09-25 · **Requested by:** Johan: "skapa någonting som ger användaren tips varje gång man startar appen" and "gör … uppdatering av appen enklare".

## Problem

JuraDrop has twelve zones, a per-drop instruction field, three model tiers, click-to-browse and Cmd+, settings. Most users discover a fraction of this. After an auto-update nothing tells them what changed, so an update is invisible unless it breaks something.

## Goal

1. **Tip on every launch.** When the app is ready (`klar`), a small, calm card above the zones shows one Swedish tip. It shows a different tip each launch and rotates through the whole bundled list before repeating. The user can dismiss it (×) or step to the next tip, and can switch tips off in Settings with "Visa tips vid start".
2. **"Nytt i versionen" after an update.** On the first launch of a new version, the card shows that version's bundled release notes (3–5 bullet points in Swedish) instead of a tip. It shows once per version.

Both are **bundled in the app**: no network, no telemetry, and nothing about the user leaves the Mac (Principle I). Preferences live in `localStorage` (`juradrop-startup`), the same pattern as `juradrop-appearance`. `settings.json` stays at two keys (its invariant test forbids more).

## Scope

**In:** the tip card, the what's-new card, the Settings toggle, the bundled tip list (≥ 12 tips), the bundled 0.5.0 notes, and persistence.
**Out:** fetching tips or release notes online (forbidden by Principle I); tips inside the first-run wizard (the wizard already explains itself); per-tip "don't show this one again"; rich formatting or links in tips.

## Functional requirements

- **FR-001** The card renders only in the zone-grid path (`wizardPhase === 'hidden'`, i.e. status `klar`) and never over the wizard.
- **FR-002** Each launch shows the tip at the stored `nextTip` index (mod the list length), then persists `nextTip + 1`. The next launch therefore shows the next tip, and the whole list cycles before any tip repeats.
- **FR-003** "Nästa tips" shows the following tip in place and also advances the stored index, so it isn't shown again next launch.
- **FR-004** × ("Stäng tipset") hides the card for this session. It comes back next launch unless tips are off.
- **FR-005** The Settings section "Start" has a checkbox, "Visa tips vid start" (default on), that persists immediately. When it is off, no tip card appears. What's-new still appears once per version: it is information about the app, not a tip.
- **FR-006** What's-new appears when a stored `lastSeenVersion` exists, differs from the running version, and bundled notes exist for the running version. With no stored version (fresh install or upgrade from ≤ 0.4.1), the signal is whether consent was **given during this session**. A fresh install consents; an existing install never does. A fresh install therefore gets no what's-new but does get a tip. (The wizard mounting is NOT a usable signal: the frontend's default status is `not_asked` until the backend answers, so the wizard briefly mounts on every launch.) The running version is always persisted once the card decision is made.
- **FR-007** What's-new has one action, "Okej" (dismiss), plus ×. It never shows again for that version. The next launch shows a tip as usual.
- **FR-008** All copy is Swedish (du-form, no exclamation marks, no emojis) and lives in `src/lib/startup-strings.ts`. The only icon is lucide `Lightbulb` (tip) or `Sparkles` (what's new).
- **FR-009** Storage failures (a locked-down WebView, corrupt JSON) fall back to defaults (tips on, index 0) and never break the app. Corrupt or foreign values are sanitized: an index is clamped to a non-negative integer, and the version is accepted only as a string.
- **FR-010** Accessibility: the card is a `<section aria-label>`, the buttons are real `<button>`s with Swedish labels, Escape is not bound (the zones keep keyboard focus order), and the card has no motion beyond a 150 ms fade that `prefers-reduced-motion` disables.

## Clarifications

### Session 2026-09-25 (auto-picked, recommended)

- Q: Where is the preference stored? → A: `localStorage`, key `juradrop-startup`. Rust `settings.json` is invariant-locked to two keys, and the appearance preference already uses localStorage.
- Q: Are tips random? → A: No. They rotate deterministically, which guarantees variety and is testable.
- Q: Does the tips toggle also silence what's-new? → A: No. What's-new is once per version and about the app itself.
- Q: How are upgraders from ≤ 0.4.1, who have no stored version, detected? → A: Consent was not given this session (see FR-006). A fresh install still gets a tip.
- Q: Where does the running version come from? → A: `version` from package.json at build time. `release-prep.sh` guarantees it equals tauri.conf.json, and it is synchronous, so there is no loading flash.

## Scenarios

SC-157 tip shown on launch · SC-158 next launch shows the next tip · SC-159 Nästa tips · SC-160 × hides for the session · SC-161 toggle off → no tip · SC-162 what's-new once after update · SC-163 fresh install → tip, no what's-new · SC-164 corrupt storage → defaults, no crash · SC-165 loading: nothing renders until the decision is made (no flash of the wrong card).

## Definition of done

Unit (the pure decision + storage functions, with PBT over arbitrary stored JSON), integration (App renders the card in the klar path and not in the wizard path), functional + destructive component tests, the vitest suite green, and the scenario rows added.
