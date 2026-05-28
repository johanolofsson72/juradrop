# Quickstart — Spec 008 first-run wizard

End-to-end smoke flows for the wizard. Run against `npm run tauri dev` after the spec is implemented.

## Setup (fresh install simulation)

```bash
# Reset to fresh-install state
rm -rf ~/Library/Application\ Support/se.juradrop/
rm -rf ~/.ollama/models/library/gemma3/

# Launch the app
npm run tauri dev
```

## Flow 1 — Happy path (US1)

1. Wait for the WebView to mount.
2. Verify the welcome screen renders with title "Välkommen till JuraDrop", body paragraph, privacy line, download note, Fortsätt + Avbryt buttons.
3. Verify Fortsätt is disabled + "Förbereder AI-motorn…" is visible for the first ~2 s (sidecar boot).
4. Wait for the sidecar to reach Ready; Fortsätt should enable and the helper line disappear.
5. Click Fortsätt.
6. Verify the wizard transitions to the progress UI within 300 ms.
7. Verify the percent bar updates over the next ~3 minutes; byte counter climbs in "X MB av Y MB" format with Swedish thin-space separator; ETA reads "≈ X min" while > 60 s remaining, "≈ Y s" once < 60 s.
8. Verify zone-grid is NOT visible behind the wizard (full-screen overlay).
9. On completion, verify the wizard fades out and the 2×3 zone-grid mounts.
10. Drag a `.docx` onto Sammanfatta; verify the existing summary flow works.

**Expected wall-clock**: ~3 minutes on broadband.

## Flow 2 — Subsequent launch (US2)

1. Quit the app (⌘Q).
2. Re-launch via `npm run tauri dev`.
3. Verify the welcome screen does NOT appear.
4. Verify the six zones render immediately (with the spec 002 "Startar AI…" overlay during the ~2 s sidecar boot).
5. Verify the zones become drop-targets within 5 s of launch.

**Expected wall-clock**: ~5 s to ready.

## Flow 3 — Network drop + resume (US3)

1. Reset to fresh-install (Setup).
2. Launch the app + click Fortsätt.
3. Wait until the progress UI shows ~10% (~30 s).
4. Disable WiFi (`networksetup -setairportpower en0 off` or System Settings → WiFi → off).
5. Wait ~10 s.
6. Verify the progress UI label changes to "Väntar på nätverk…" within 5 s of the drop.
7. Verify the percent bar + byte counter freeze at their last values.
8. Verify the ETA reads "—".
9. Re-enable WiFi (`networksetup -setairportpower en0 on`).
10. Verify within 5 s the label flips back to "Hämtar AI-modell…" and the percent + byte counter resume climbing.
11. Wait for completion.

**Expected**: zero progress loss; the byte counter resumes from where it stopped.

## Flow 4 — Cancel mid-download (US4)

1. Reset to fresh-install (Setup).
2. Launch the app + click Fortsätt.
3. Wait until the progress UI shows ~5% (~15 s).
4. Click "Avbryt nedladdning".
5. Verify the wizard transitions back to the welcome screen within 1 s.
6. Verify `~/.ollama/models/library/gemma3/` is empty or absent (the partial model is gone).
7. Quit the app.
8. Re-launch.
9. Verify the welcome screen appears again.
10. Click Fortsätt to restart the download.
11. Verify the byte counter starts at 0 (not resumed from the cancelled state — Ollama discards partial chunks on close).

## Flow 5 — Avbryt on welcome (US5)

1. Reset to fresh-install (Setup).
2. Launch the app.
3. Verify the welcome screen renders.
4. Click Avbryt.
5. Verify the welcome screen STAYS visible (no transition, no quit).
6. Verify the consent record file now exists with `choice = avbryt`.
7. Verify no model pull task started.
8. Quit the app (⌘Q).
9. Re-launch.
10. Verify the welcome screen appears again.
11. Click Fortsätt; verify the normal happy path resumes (the consent record is overwritten with `fortsatt`).

## Flow 6 — Escape key paths (FR-017)

1. From a fresh welcome screen, press `Esc`. Verify behavior matches Flow 5 (Avbryt invoked; welcome stays).
2. From an active progress UI, press `Esc`. Verify behavior matches Flow 4 (Cancel invoked; transitions back to welcome).
3. Tab order on welcome: Fortsätt is focused on mount; pressing Tab moves focus to Avbryt; pressing Tab again wraps to Fortsätt.
4. Press Enter on the focused Fortsätt button; verify it fires (same as a click).

## Flow 7 — Disk-full error path

1. Use `tmpfs` or a small APFS volume to simulate disk pressure (< 4 GB free).
2. Reset to fresh-install (Setup).
3. Launch the app + click Fortsätt.
4. Verify the wizard transitions to the error phase within 5 s with the existing Swedish copy "Inte tillräckligt med diskutrymme — frigör minst 4 GB".
5. Verify the "Försök igen" button is present.
6. Free disk space.
7. Click "Försök igen".
8. Verify the pull restarts and the flow continues normally.

## Flow 8 — Force-quit mid-download

1. Reset to fresh-install (Setup).
2. Launch the app + click Fortsätt.
3. Wait until the progress UI shows ~20% (~60 s).
4. Force-quit the app (⌘⌥Esc → JuraDrop → Force Quit, OR `kill -9 <pid>`).
5. Verify the partial model bytes are still on disk (the pull task didn't get a chance to clean up).
6. Re-launch the app.
7. Verify the welcome screen appears (consent = fortsatt BUT model is incomplete).
8. Click Fortsätt.
9. Verify Ollama resumes the pull from the cached chunks (the percent jumps quickly through the already-downloaded portion, then continues from the actual point).

## Success-criteria verification map

| SC | Verified by | Notes |
|---|---|---|
| SC-001 (welcome renders ≤ 800 ms) | Flow 1 step 1–2 | Playwright timing assertion in `tests/e2e/first-run-wizard.spec.ts` |
| SC-002 (subsequent launches skip welcome) | Flow 2 | vitest assertion on `useWizardState({ consent: fortsatt, model: ready })` |
| SC-003 (zone gating during wizard) | Flow 1 step 8 | Destructive Playwright test attempting a drag-drop during progress phase |
| SC-004 (network drop recovery) | Flow 3 | Integration test driving `useProgressEstimate` with a fake clock |
| SC-005 (cancel cleanup) | Flow 4 steps 6–10 | Integration test asserting absence of model bytes after cancel |
| SC-006 (Swedish copy invariants) | Cross-language drift test | `WizardCopy.errors.test.tsx` + `wizard_strings.rs` |
| SC-007 (no new outbound surface) | Static grep | New invariant test `wizard_invariants.rs` |
| SC-008 (VoiceOver) | Flow 1 manual step | Real-hardware verification on a Mac with VoiceOver enabled |
