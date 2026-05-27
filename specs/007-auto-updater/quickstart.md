# Spec 007 quickstart — 7 smoke flows

Manual verification flows for the auto-updater. Run after implementation is complete.

## Prereqs

- A built JuraDrop app at v0.1.0 (or whatever the current `Cargo.toml` version is).
- A published v0.2.0 draft (or higher) on the GitHub release pipeline from spec 006 — OR — a locally-served manifest via `python3 -m http.server 8765` for offline testing.
- For offline tests: edit `tauri.conf.json`'s `plugins.updater.endpoints` temporarily to point at `http://localhost:8765/latest.json`.

## Flow 1 — Happy-path update on idle app

1. Launch v0.1.0. Wait ~5 seconds for the launch-time check.
2. The indicator badge "Uppdatering tillgänglig" appears in the top-right corner of the main window. NO modal dialog appears.
3. Click the badge. The panel expands showing "Nyheter i version 0.2.0" + the release notes + an "Installera nu" button.
4. Click "Installera nu". The badge text changes to "Hämtar uppdatering… N%" and N counts up.
5. When the download completes, the badge changes to "Klar att installera — starta om?" with a "Starta om för att uppdatera" button.
6. Click the button. The badge briefly shows "Startar om…", the window blanks, the new process launches.
7. Verify the new version's About / window title reads `0.2.0`.

**Pass criteria**: SC-001 (≤ 90 s wall-clock from "Installera nu" to new process live).

## Flow 2 — Update appears while a zone is processing

1. Launch v0.1.0. Drop a multi-page `.docx` on Sammanfatta.
2. While the zone is in `Processing`, force a fresh manifest check (e.g. via the `check_for_updates_now` command from a dev console, or by waiting for the 4-hour tick).
3. The indicator badge "Uppdatering tillgänglig" appears in the top-right BUT the Sammanfatta zone keeps processing — no interruption.
4. The Sammanfatta sidecar completes successfully and the zone returns to idle.
5. Continue with Flow 1's steps 3–6.

**Pass criteria**: SC-002 — zero restart events fire while any zone is in `Processing`. The Sammanfatta sidecar is byte-identical to a no-update run.

## Flow 3 — Click "Starta om" while a zone is mid-processing → deferred restart

1. Get to the `ReadyToInstall` state via Flow 1 steps 1–5.
2. Before clicking "Starta om", drop a `.docx` on Sammanfatta.
3. Click "Starta om för att uppdatera" while the zone is in `Processing`.
4. The button text changes to "Väntar tills jobben är klara…" with a chevron "Avbryt".
5. Wait for the Sammanfatta sidecar to complete. The moment the zone returns to non-`Processing`, the app auto-restarts — no second click needed.
6. The new v0.2.0 process launches.

**Pass criteria**: FR-009 deferral fires automatically; consent flag preserves the user's intent.

## Flow 4 — Cancel a deferred restart

1. Get to "Väntar tills jobben är klara…" via Flow 3 steps 1–4.
2. Click the "Avbryt" chevron.
3. The button text changes back to "Starta om för att uppdatera". The app does NOT restart even when the zone returns to idle.

**Pass criteria**: cancellation clears `pending_restart_consent`; the auto-fire path is correctly gated.

## Flow 5 — Offline → silent failure → recovery on network return

1. Disable network (WiFi off + ethernet unplugged).
2. Launch JuraDrop. Wait for the launch-time check.
3. NO indicator badge appears. The window shows the normal six zones — no error banner, no modal.
4. Look at the bottom-right footnote: "Senast kollat: <time>" — it's clickable.
5. Click it. A small failure-recovery panel expands showing "Kan inte nå GitHub — kontrollera nätverksanslutningen" + "Sök efter uppdateringar igen".
6. Re-enable network. Click "Sök efter uppdateringar igen".
7. State transitions through `Checking` to either `UpToDate` or `Available`.

**Pass criteria**: SC-004 — `NoNetwork` shows specific Swedish copy, not a generic "fel uppstod". User can self-recover.

## Flow 6 — Tampered signature

1. Locally serve a manifest pointing at a tampered DMG (or a valid DMG with a wrong `.sig`).
2. Launch JuraDrop pointed at the local endpoint.
3. State transitions `Checking → Available → Downloading → Failed` after the download completes.
4. The indicator badge hides; the footnote shows "Säkerhetskontrollen misslyckades — uppdateringen installeras inte" with a "Sök efter uppdateringar igen" affordance.
5. The current running v0.1.0 is unaffected. The partial download is discarded from memory.

**Pass criteria**: FR-012 — signature verification is not bypassable; the install never proceeds with an invalid signature.

## Flow 7 — User dismisses the indicator + it re-appears on next check

1. Get to the `Available` state via Flow 1 steps 1–2.
2. Click the X on the indicator badge (the "Dölj"/dismiss affordance).
3. The badge disappears. The bottom-right footnote shows the same "Senast kollat" but no failure-recovery affordance (state is still `Available`, not `Failed`).
4. Wait for the next 4-hour tick OR manually invoke `check_for_updates_now` from the footnote affordance.
5. The badge re-appears (per FR-018).

**Pass criteria**: dismissal is per-tick — it doesn't persist across re-checks. The user is gently reminded; not punished by aggressive nagging.

## Verification commands

```bash
# Rust integration test for the state machine + Swedish copy:
cd src-tauri && cargo test --test update_lifecycle

# React unit tests for the indicator + store:
npm test -- --run src/__tests__/UpdateIndicator.test.tsx src/__tests__/UpdateStore.test.tsx

# Cross-language drift assertion (Rust ↔ TS Swedish strings):
cd src-tauri && cargo test update_failure_strings_match_fixture

# Outbound network audit — must remain identical to spec 006:
grep -RInE "\bfetch\(|XMLHttpRequest|new WebSocket\(|reqwest::|tokio::net::|hyper::Client|isahc::" src/ src-tauri/src/
# Every match must be in spec 002's sidecar/{manager,client}.rs.
# Spec 007 adds ZERO new outbound surfaces.
```
