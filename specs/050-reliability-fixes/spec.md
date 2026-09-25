# Spec 050 — reliability-fixes

**Track:** full [hardened] — touches the updater state machine, the first-run consent/pull state machine, process lifecycle (sidecar shutdown), and the WebView capability surface.
**Created:** 2026-09-25 · **Requested by:** Johan ("analysera appen, förbättra funktioner och lös buggar", "använd rätt modeller och senaste tekniken").

## Problem

A code audit of v0.4.1 (every claim below was read in the source, file:line cited) found defects that a user can hit today:

1. **Updates never restart on macOS, and a successful install is shown as a failure.** `updater/commands.rs` `run_plugin_install` assumes `Update::install` exits the process. That only happens on Windows. On macOS it replaces the bundle and returns `Ok`. The result is discarded, `run_deferred_install` then unconditionally records `InstallFailed`, and nothing calls `app.restart()`. The user sees "Uppdateringen misslyckades" after a successful install and keeps running the old binary until they quit by hand.
2. **The consent retry is stuck on the welcome screen.** `give_consent` never clears `error_override`. After "Avbryt nedladdning" (`ModellSaknasAvbruten`) or a disk-full error (`FelDiskFull`), pressing Fortsätt/Försök igen starts the pull, but `snapshot()` keeps forcing the stale override. The download runs invisibly and the app stays on the welcome/error screen until a restart.
3. **The error-panel "Avbryt" does nothing.** `FirstRunProgress` calls `cancel_consent`, which returns early unless consent is `NotAsked`. In the error phase it is always `Fortsatt`.
4. **The first-run pull is killed after 300 s total.** `gemma3:4b` is ~3.3 GB, so anything slower than ~90 Mbit/s fails. The stream already has a 90 s stall detector (`PULL_STREAM_IDLE_TIMEOUT`), and the tier pulls deliberately have no total cap.
5. **The output .docx names the wrong model.** The header always says `gemma3:4b` (`docx_write.rs` `MODEL_LABEL`), even when Snabb (`llama3.2:1b`) or Stor (`gemma3:12b`) produced it.
6. **Wrong download size in the UI.** The wizard says "cirka 2 GB", the consent modal "~3 GB", and the progress ETA assumes 2 GiB. The real size is ~3.3 GB, so the byte counter and ETA are off by ~40 %.
7. **Cmd+Q orphans Ollama.** Only `WindowEvent::CloseRequested` stops the sidecar. Cmd+Q goes through `RunEvent::ExitRequested/Exit`, so Ollama keeps running (and holding RAM) until the next launch reaps it.
8. **An `/api/tags` failure at boot leaves the app stuck on "Startar…"** with no retry and no error: the failure is only `eprintln!`-ed.
9. **Unhandled IPC rejections.** `giveConsent`/`cancelConsent` (WelcomeWizard, ConsentModal, FirstRunProgress) and `dispatchToZone` from the drop handler have no `catch`. A failure is silent: an unhandled promise rejection and no Swedish message.
10. **Startup event race and StrictMode listener leak.** `App.tsx` calls `getStatus()` before `subscribeStatus` is registered, so an emit in between is lost. The unlisten handles are stored inside `.then`, so an unmount before resolution leaks the listener (and in dev, a drop dispatches twice).
11. **Over-broad WebView capability.** `shell:allow-spawn` lets the WebView start the bundled Ollama binary with arbitrary arguments, and `shell:allow-kill` lets it kill processes. Only the Rust side needs either.
12. **Stale bundled Ollama (v0.24.0).** The current stable version is v0.34.4 (2026-09-23). It adds the MLX engine on Apple Silicon (faster inference) and a year of fixes. The model family stays gemma3 by Johan's decision (Gemma 4 small variants are 7–10 GB and untested against our prompts).

## Goal

Every defect above is fixed, each is covered by a test that fails on the old code, and nothing new leaves the Mac.

## Scope

**In:** items 1–12.
**Out:** a model-family change (Gemma 4, a later spec with live testing on a Mac); the `[ docx ]` idle badge wording (recorded as a finding); the double consent UI on first run (by design, per spec 008 e2e); React/Vite/Tailwind major migrations (spec 052 does safe upgrades only).

## Functional requirements

- **FR-001** On macOS, after `Update::install` returns `Ok`, the app MUST restart (`AppHandle::restart`). It MUST record `InstallFailed` only when `install` returns `Err` or the update can no longer be resolved.
- **FR-002** `give_consent` MUST clear `error_override` before it evaluates disk space and starts the pull, so the wizard reflects the new truth (progress, or a fresh `FelDiskFull`).
- **FR-003** `cancel_consent` MUST also be honoured when consent is `Fortsatt` and the model is not `Ready` and not `Downloading` (the error phase). It sets `choice = Avbryt`, clears `error_override`, persists, and emits, which takes the wizard back to welcome. It stays a no-op while downloading, when the model is ready, and when consent is already `Avbryt`.
- **FR-004** The bundled first-run pull MUST NOT have a total-duration cap. The 90 s stall detector remains the failure bound (Johan, 2026-09-25).
- **FR-005** The .docx header MUST name the model that actually produced the output (the dispatch-pinned `model_id`).
- **FR-006** Every user-visible statement of the default model's download size MUST read "cirka 3,3 GB" / "~3,3 GB", and the progress byte estimate MUST use 3.3 GB. It is sourced from one TS constant, and a test ties that constant to the Rust tier map's size badge.
- **FR-007** Cmd+Q, the app menu's Quit, and closing the main window MUST all stop the sidecar, cancel the update ticker, and clear the pidfile exactly once (Johan: quit and stop Ollama, no confirmation dialog).
- **FR-008** An `/api/tags` failure in `after_sidecar_ready` MUST be retried (3 attempts, 1 s / 2 s backoff). If all attempts fail, it MUST surface `FelOvantat` (existing Swedish copy + existing retry affordance) instead of staying silent.
- **FR-009** Every fire-and-forget IPC call in the consent and drop paths MUST catch rejection and surface a specific Swedish message. Consent failures show inline in the wizard/modal: "Kunde inte spara ditt val. Försök igen." A drop dispatch failure sets the app status line: "Kunde inte skicka filen till zonen. Försök igen."
- **FR-010** `App.tsx` MUST register its status listener before it reads the initial status. Every `listen()` registration in `App.tsx`, `DropZone.tsx` and `use-progress-estimate.ts` MUST be unlistened even if the component unmounts before the promise resolves.
- **FR-011** `capabilities/default.json` MUST NOT grant `shell:allow-spawn` or `shell:allow-kill` (Johan, 2026-09-25). `shell:allow-open` stays scoped to the Releases URL.
- **FR-012** ~~`scripts/fetch-ollama.sh` MUST pin Ollama v0.34.4~~ — **DEFERRED (finding F001).** Investigation (2026-09-25) showed that from v0.34 the `ollama` binary no longer embeds the inference runner. It needs `llama-server` plus the `libllama`/`libggml`/MLX dylibs beside it (`Contents/Resources/`), while `fetch-ollama.sh` bundles only the binary. Shipping the bump as-is would very likely produce a sidecar that starts but cannot run a model, and it cannot be runtime-tested without a Mac. The pin stays at v0.24.0 (SHA verified identical: `8073624e…`).
- **FR-013** (TLA+ GAP-1) `give_consent` on a model that is already `Ready` MUST record consent only: no disk check and no re-pull.
- **FR-014** (TLA+ GAP-2) An exhausted `/api/tags` probe MUST set the model to `NotPresent` (unconfirmed), not leave a stale `Ready`.
- **FR-015** (security review 3a) `give_consent` and the boot auto-pull MUST claim the pull slot atomically (`claim_pull_slot`, under the write lock, before any `.await`), and roll back if the save or the disk check fails.
- **FR-016** (security review 1a) The updater MUST install only if the re-checked release version equals the downloaded one (`install_matches_download`). Otherwise it fails closed.
- **FR-017** (security review) A pull-stream line longer than 64 KiB with no newline MUST fail the pull (`MAX_PULL_LINE_BYTES`). There is no unbounded buffer now that there is no total cap.

## Clarifications

### Session 2026-09-25

- Q: Should Cmd+Q ask for confirmation during an active job? → A: No. Quit and stop Ollama (Johan). Writes are atomic, so no partial file can remain.
- Q: Remove the WebView's spawn/kill permissions? → A: Yes (Johan).
- Q: Replace the 300 s pull cap with what? → A: Stall detector only, matching the tier pulls (Johan).
- Q: Should the model family change? → A: No. Keep gemma3; bump only the Ollama runtime (Johan, kickoff).
- Q: Where does an `/api/tags` exhaustion surface? → A: The existing `FelOvantat` status. No new Swedish status is introduced (auto-picked: smallest honest change).
- Q: Should the restart after an update be immediate? → A: Yes. The user has already consented, either by clicking "Starta om" or through the deferred-restart banner. The restart is the consented action (auto-picked).

## Threat model (STRIDE over the changed trust boundaries)

| Boundary | Threat | Mitigation |
|---|---|---|
| WebView → shell plugin | **E**levation: compromised WebView spawns `ollama serve` with attacker args (e.g. bind a non-loopback host) or kills processes | FR-011 removes both permissions; a Rust test asserts the capability file grants neither |
| Updater install → restart | **T**ampering: restart into an unsigned bundle | `tauri-plugin-updater` verifies the minisign signature *before* `install`; restart only follows `Ok`. Unchanged pubkey |
| Updater | **D**oS: restart loop | Restart only follows a successful install of a strictly newer version (the plugin's `check` compares versions) |
| Pull without total cap | **D**oS: a hung download holds the wizard forever | 90 s stall detector plus the user-visible "Avbryt nedladdning" |
| Exit path | **I**nformation disclosure: orphaned Ollama keeps model and any in-flight prompt in RAM after quit | FR-007 stops the sidecar on every exit path |
| Error surfacing | **I**nformation disclosure: raw Rust error in UI | FR-009 shows fixed Swedish strings only; raw errors go to the console only |
| New Ollama binary | **T**ampering (supply chain) | SHA-256 pin, verified by `fetch-ollama.sh` in CI before signing |

No threat is left without a mitigation. No new outbound network call: the Ollama version change reuses the existing localhost API and the existing registry pull.

## Verification record (2026-09-25)

- **TLA+** `tla/FirstRun.tla`: TLC is clean on the fixed model (30 states; `DownloadVisible`, `HiddenImpliesReady`, `ErrorAvbrytWorks`, `NoDeadEnd` and liveness `DownloadEnds` all hold). The same invariants FAIL on the v0.4.1 model (`Fixed = FALSE`: DownloadVisible, ErrorAvbrytWorks, NoDeadEnd), so they catch the original bugs. The first runs found GAP-1 and GAP-2 in the new code, and both were fixed (FR-013/014).
- **Adversarial review** (security-scanner): 4 findings (1a, 3a, 3b, line buffer), all fixed in this spec (FR-015/016/013/017). Categories 2, 4, 5 and 6 are clean.
- **Mutation (Stryker)** on the changed TS: 83.8% overall. `listen-lifecycle` 90%, `use-progress-estimate` 88% (was 44%), `status-store` 76% (finding F002: the survivors are pre-existing seed literals).
- **Tests**: Rust 664 passed; vitest 489 passed.
- **Not run here**: `/security-review` (the built-in) and runtime `npm run tauri dev` scenarios, which need a Mac.

## Scenarios

In `specs/SCENARIOS.md`: SC-044 (re-worded), SC-150..SC-156. All ☐, pending a runtime pass on a Mac.

## Definition of done

The Rust + vitest tests for FR-001…FR-012 pass; clippy/fmt/eslint/tsc are clean; the threat model is recorded; there is a security-scanner adversarial pass; the Stryker run is on the changed TS modules; TLA+ covers the consent/pull recovery transitions. The runtime scenarios SC-050-01/06/08 need a Mac (`npm run tauri dev`) and are recorded as `☐ mapped` until Johan observes them.
