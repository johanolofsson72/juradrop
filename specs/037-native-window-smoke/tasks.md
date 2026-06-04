# Tasks: Native Window Smoke

**Input**: spec.md (3 user stories), plan.md, research.md (R1–R10), data-model.md, contracts/harness.md (H-1…H-9)

**Tests**: the deliverable IS a test suite; its verification = mutation proof + repeatable green runs + residue checks.

## Phase 1: Setup

- [ ] T001 Build the debug `.app` (`npm run tauri build -- --debug --target aarch64-apple-darwin` → `src-tauri/target/aarch64-apple-darwin/debug/bundle/macos/JuraDrop.app`) — long-running; started in the background at plan completion; verify exit + bundle exists before T005

## Phase 2: Foundational

- [ ] T002 [P] Create `scripts/mock-ollama.py` per contract B (stdlib http.server, ephemeral port printed to stdout, `--port` override; `/api/tags` → gemma3:4b listing, `/api/generate` → canned `NATIV-SMOKE: sammanfattning klar.`, 404 otherwise); verify standalone with curl (tags + generate + unknown route)
- [ ] T003 [P] Create the `ui-tests/` scaffolding per plan: hand-written `JuraDropUITests.xcodeproj/project.pbxproj` (dummy `HarnessHost` app target + `JuraDropUITests` ui-testing bundle), shared scheme `xcshareddata/xcschemes/JuraDropUITests.xcscheme`, `HarnessHost/main.swift` stub, both Info.plists; verify `xcodebuild -list -project ui-tests/JuraDropUITests.xcodeproj` parses and `xcodebuild build-for-testing` compiles

## Phase 3: User Story 1 — real window renders (P1) + the FR-009 probe

**Goal**: probe a11y exposure FIRST; then assert 12 zones + chrome in the real window.

- [ ] T004 [US1] Write `ui-tests/JuraDropUITests/NativeWindowSmokeTests.swift` — `test00_probe`: launch by bundle id with `JURADROP_OLLAMA_URL` + fixture env, bounded `waitForExistence` on the window (H-1), log `app.debugDescription`, assert window present; teardown terminates the app
- [ ] T005 [US1] RUN the probe (needs T001 + T002 + T003 + a manually started mock): inspect the a11y dump — decision gate FR-009: `web_content_reachable` → continue full scope; `chrome_only_fallback` → STOP, amend spec.md + register row honestly, reduce scope (allium `ProbeWebContentExposure`)
- [ ] T006 [US1] `test01_twelveZonesAndChromeRender`: decode the runner-exported `ZONE_TITLES_JSON` (canonical titles — H-3/FR-012, no retyped Swedish), assert each title reachable in the a11y tree with bounded waits, assert help + settings affordances (H-4); zones present as enabled (mock reports model present)

## Phase 4: User Story 2 — pick-to-sidecar through real seams (P1)

- [ ] T007 [US2] `test02_pickToSidecar`: temp fixture `dokument.txt` (from `JURADROP_SMOKE_FIXTURE_DIR`); activate `Välj fil för Sammanfatta`; drive the open panel via Go-to-Folder (Cmd+Shift+G → path → Return → confirm, per R5); bounded wait for `dokument.sammanfatta.txt` next to the fixture; assert content contains the canned mock text (H-5/H-6, SC-002); assert no fixed sleeps anywhere in the suite (H-7)

## Phase 5: User Story 3 — one-command runner (P2)

- [ ] T008 [US3] Create `scripts/native-smoke.sh` per contract A: `set -euo pipefail`; preflight (xcodebuild present; R7 osascript permission probe → exit 2 with the exact System Settings instruction; kill stray JuraDrop/mock from interrupted runs); build-if-stale per R8 (`--build` forces); export titles JSON via `node -e` from the canonical TS source (R6); start mock, capture port; `lsregister -f` the bundle (R1); `mktemp -d` fixture workspace; run `xcodebuild test` with the env contract; propagate exit code; `trap EXIT` teardown (app tree, mock, temp dir) — pass or fail (H-8)
- [ ] T009 [US3] Verify runner behavior: clean-shell green run; rerun-after-interrupt works; `--probe-only` runs test00 alone; failure propagates non-zero (force one by pointing at a bogus titles file)

## Phase 6: Polish, proof, gates

- [ ] T010 SC-001 mutation proof: temporarily break one zone title in the canonical TS source → runner goes red naming the missing title → revert → green; record both runs' results in the register tick text
- [ ] T011 Repeatability + residue: two consecutive green runs; post-run `pgrep -f JuraDrop|mock-ollama` empty, temp dirs gone (H-8); wall-clock under 5 min excluding build (SC-003)
- [ ] T012 [P] Docs: verify quickstart.md matches reality post-impl; add the suite to `.claude/docs/testing.md` (what it covers/doesn't, opt-in cadence) and one line in README's build-from-source section
- [ ] T013 Gate hygiene: grep-verify NO default gate references the suite (package.json test scripts, cargo, playwright.config, .github/) — H-9/FR-008; run the standard sweep (`npm test`, `npm run test:e2e`, `cd src-tauri && cargo test`, linters) to prove zero production impact (SC-005); `graphify update .`
- [ ] T014 `/tla` (full track): distill + drift vs spec.allium; the TestRun machine has 9 states/13 transitions — expect a real (non-trivial-gate) pass over the harness lifecycle, or an honest gate decision recorded
- [ ] T015 Register tick + history entry (include the probe outcome + mutation-proof results); status summary

## Dependencies

```
T001 (background) ─┐
T002 [P] ──────────┼→ T005 (probe gate) → T006 → T007 → T008 → T009 → T010 → T011 → T013 → T014 → T015
T003 [P] → T004 ───┘                                      T012 ∥ after T008
```

## Implementation strategy

The probe (T005) is the hinge: everything after it assumes `web_content_reachable`; the fallback path replaces T006/T007's scope and amends the spec. Build runs in the background from the start — the scaffolding (T002–T004) overlaps it.
