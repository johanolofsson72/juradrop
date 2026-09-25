# Tasks — 050 reliability-fixes

- [x] T001 [FR-001] Updater: restart on Ok, InstallFailed only on Err (`updater/commands.rs`)
- [x] T002 [FR-002] `give_consent` clears `error_override` (`sidecar/commands.rs`)
- [x] T003 [FR-003] `cancel_consent_allowed` guard + override clear + PBT truth table
- [x] T004 [FR-004] Remove the 300 s total pull cap
- [x] T005 [FR-005] .docx header names the dispatch model + test
- [x] T006 [FR-006] `DEFAULT_MODEL_DOWNLOAD` constant; wizard/consent/progress use it; cross-language pin test
- [x] T007 [FR-007] `shutdown()` on `RunEvent::Exit`
- [x] T008 [FR-008] `/api/tags` retry + FelOvantat
- [x] T009 [FR-009] Catch + Swedish inline error in WelcomeWizard, ConsentModal, FirstRunProgress; drop failure → status line
- [x] T010 [FR-010] Listener-disposal fix in App/DropZone/progress hook; subscribe-before-read
- [x] T011 [FR-011] Capability narrowing + Rust assertion test
- [ ] T012 [FR-012] Ollama v0.34.4 pin + SHA — DEFERRED (F001: runner split into llama-server + dylibs; needs bundling rework + Mac test)
- [x] T013 Tests: vitest functional + destructive for T009/T010; cargo tests for T003/T005/T011
- [x] T014 Security-scanner adversarial pass; Stryker on the changed TS; /tla on the recovery machine
- [x] T015 [FR-013/014] TLA+ GAP-1/GAP-2 fixes (consent on Ready model; tags exhaustion → NotPresent)
- [x] T016 [FR-015..017] Security review fixes: atomic pull claim, install version pin, pull line cap
