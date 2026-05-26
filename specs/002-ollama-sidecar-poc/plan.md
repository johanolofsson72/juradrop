# Implementation Plan: 002 — Ollama Sidecar PoC

**Branch**: `main` (direct-push per `.claude/rules/spec-register.md`) | **Date**: 2026-05-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-ollama-sidecar-poc/spec.md`. Allium spec at [spec.allium](./spec.allium).

## Summary

Wire the bundled Ollama sidecar into the JuraDrop app from spec 001. On launch: start the Ollama HTTP server as a child process bound to loopback only, check whether `gemma3:4b` is present, and — on first launch only — show a one-time Swedish consent modal before pulling the model from `ollama.com` (the only outbound network call Principle I allows). The welcome card from spec 001 grows a Swedish status string ("Startar AI…" / "Laddar ner AI-modell … N%" / "AI redo" / Swedish error variants). A developer-only Rust integration test (`#[ignore]`-marked) sends a hardcoded prompt through `/api/generate` and asserts a non-empty response.

## Technical Context

**Language/Version**: Rust stable (≥ 1.75 per Tauri 2.x; currently 1.95 in the dev env per spec 001 implementation). TypeScript 5.x strict.

**Primary Dependencies (Rust additions)**:
- `reqwest` 0.12 with `json` + `rustls-tls` features for Ollama HTTP API (loopback) and the registry pull. Pinned to `rustls-tls` (not native-tls) so we avoid macOS Keychain interaction and keep the binary self-contained.
- `tokio` (already transitively present via Tauri 2.x) for async.
- `serde` + `serde_json` (already present) for Ollama API JSON.
- `tauri-plugin-shell` 2.x — the official Tauri 2.x plugin that spawns sidecar binaries under capability gating.
- `tauri` `process` API for app-data directory and quit-handling (already in `tauri` core).

**Primary Dependencies (JS additions)**:
- shadcn `Dialog` (and `DialogTrigger`, `DialogContent`, `DialogHeader`, `DialogTitle`, `DialogDescription`, `DialogFooter`) — for the FR-019 consent modal.
- `zustand` ^4 — small store for the sidecar status the welcome card reads. (CLAUDE.md spec stack mentions zustand; this is its first real use.)
- Tauri `event` API (already in `@tauri-apps/api`) for receiving status updates from Rust.

**Storage**:
- Consent state — single JSON file at `app_data_dir()/consent.json`. Tauri's `path` API resolves to `~/Library/Application Support/se.noisycricket.juradrop/consent.json` on macOS.
- Model artifact — managed by Ollama itself in `~/.ollama/models/`. JuraDrop never touches this directory directly.

**Testing**:
- Vitest for the React modal + welcome card status rendering.
- `cargo test` for Rust unit tests of the sidecar manager, model presence check, and consent persistence.
- `cargo test -- --ignored` for the one round-trip integration test (FC-008). This MUST be opt-in because it loads a 3 GB model.
- Playwright stub stays from spec 001 (real E2E still defers to spec 003).

**Target Platform**: macOS 12+, Apple Silicon only (`aarch64-apple-darwin`). Universal2 stays deferred to spec 006.

**Project Type**: Single desktop app — same two-tree layout as spec 001 (`src/` + `src-tauri/`).

**Performance Goals**:
- Sidecar reachable on loopback within 10 s of `app start` event (SC-001).
- Model pull completes within 5 min on 100 Mbit/s (SC-002).
- Round-trip prompt → response ≤ 30 s with warm model (SC-004).
- Sidecar fully exits within 5 s of app quit (SC-003).

**Constraints**:
- Outbound network limited to `ollama.com` (registry) and loopback. No other outbound traffic. Audited at impl time.
- Sidecar binds loopback only (Tauri config + Ollama env var `OLLAMA_HOST=127.0.0.1:11434`).
- Prompts and responses MUST NOT appear in logs (FR-012). All logging redacts content.
- Bundled Ollama binary is `aarch64-apple-darwin` only at this spec.

**Scale/Scope**: One app process, one Ollama child, one model file, one consent record. No concurrency, no multi-user, no distributed coordination.

## Constitution Check

*GATE: Must pass before Phase 0. Re-checked after Phase 1.*

| # | Principle | Plan compliance |
|---|-----------|----------------|
| I | Privacy by Architecture (NON-NEGOTIABLE) | **PASS with explicit Principle I exception 2 invoked.** The only new outbound call is the model pull from `ollama.com`, which Principle I explicitly authorizes ("Initial Ollama model download from `ollama.com` … on first launch"). FR-019 + FR-019b gate the pull behind explicit user consent — a stronger guarantee than the constitution requires. No telemetry, no analytics, no other outbound calls. The grep audit from spec 001 (T039b) is re-run with the registry domain whitelisted. |
| II | Zero-CLI Install | **PASS.** The Ollama binary is bundled inside the `.app` (via the `tauri-plugin-shell` sidecar convention). The user never runs `brew install`, `ollama pull`, or any shell command. Consent dialog uses plain Swedish, not technical terms. |
| III | Local-Only Inference | **PASS.** Sidecar bound to `127.0.0.1` only via `OLLAMA_HOST` env var; loopback enforced by `LoopbackOnly` invariant. No remote-host config exposed. |
| IV | Single-User Desktop App | **PASS.** Sidecar lifecycle tied to app process. No background daemon survives quit. Consent state stored per-user in app-support, not in a shared service. |
| V | Swedish-First UI, English-First Code | **PASS.** All user-facing strings introduced by this spec are Swedish and pass through `humanizer` before merge (FR-017). Rust/TS code, comments, commit messages: English. |
| VI | Native macOS Feel | **PASS.** Consent dialog uses shadcn `Dialog` which renders as a centered modal with native-feeling backdrop blur (consistent with macOS sheet aesthetics). Welcome card status updates use no motion beyond shadcn's built-in `transition-colors`. |
| VII | Bundled Sidecar — Ollama Is Internal Plumbing | **PASS.** The user-facing strings never expose "Ollama" except in the FR-019 consent modal where the destination URL must be honest. The model tag `gemma3:4b` is never shown in UI. Welcome card says "AI redo", not "ollama ready". |
| VIII | Honest Failure States | **PASS.** Six distinct Swedish error states are defined (FR-010, FR-019b, US4 scenarios). No stack traces, no English error codes. The one-retry mechanism for sidecar crashes (SidecarOneRetry rule) is the minimum honest fallback before surfacing the error. |
| IX | Open Source, Free, No Lock-In | **PASS.** Ollama is MIT-licensed. The bundled binary is the upstream release. No paywalled features added. |

**Result**: All nine principles pass. No Complexity Tracking entries needed.

The most load-bearing principle for this spec is I; FR-019 + FR-019b + the audit grep in tasks make it machine-checkable that no outbound call other than `ollama.com` exists.

## Project Structure

### Documentation (this feature)

```text
specs/002-ollama-sidecar-poc/
├── spec.md                          # done
├── spec.allium                      # done
├── checklists/
│   └── requirements.md              # done
├── plan.md                          # this file
├── research.md                      # Phase 0 output
├── data-model.md                    # Phase 1 output
├── quickstart.md                    # Phase 1 output
├── contracts/                       # Phase 1 output
│   ├── tauri-commands.md            # 4 Tauri commands exposed to the WebView
│   ├── tauri-events.md              # Status / progress events Rust→WebView
│   ├── ollama-api-usage.md          # Which Ollama endpoints we call, request/response shapes
│   ├── capabilities.md              # Updated capabilities/default.json shape
│   └── consent-store.md             # consent.json schema
└── tasks.md                         # /speckit-tasks output (later)
```

### Source Code (additions to the spec-001 tree)

```text
juradrop/
├── package.json                              # add: tauri-plugin-shell-api, zustand
├── src-tauri/
│   ├── Cargo.toml                            # add: reqwest, tauri-plugin-shell
│   ├── binaries/                             # NEW — bundled sidecars
│   │   └── ollama-aarch64-apple-darwin       # Ollama server binary (fetched by scripts/fetch-ollama.sh)
│   ├── capabilities/
│   │   └── default.json                      # ADD: shell sidecar scope + app commands
│   ├── tauri.conf.json                       # ADD: tauri-plugin-shell config, sidecar binary
│   └── src/
│       ├── main.rs                           # unchanged structure
│       ├── lib.rs                            # ADD: register plugin, register commands, wire RunEvent hooks
│       └── sidecar/                          # NEW module
│           ├── mod.rs                        # public façade
│           ├── manager.rs                    # OllamaSidecar lifecycle (spawn, wait_ready, stop)
│           ├── client.rs                     # reqwest client wrapping Ollama HTTP API
│           ├── status.rs                     # UserVisibleStatus + AppStatus derivation
│           ├── consent.rs                    # FirstLaunchConsent persistence to app_data_dir
│           ├── commands.rs                   # #[tauri::command] exposed to WebView
│           └── log_safe.rs                   # Redaction helpers — FR-012 / NoPromptOrResponseInLogs
│   ├── tests/                                # NEW — integration tests
│   │   ├── sidecar_lifecycle.rs              # FC-001, FC-002
│   │   ├── model_presence.rs                 # FC-003
│   │   ├── consent_persistence.rs            # FR-019, FR-019b
│   │   └── sidecar_roundtrip.rs              # FC-008 with #[ignore]
├── scripts/
│   └── fetch-ollama.sh                       # NEW — downloads pinned Ollama binary into src-tauri/binaries/
├── src/
│   ├── App.tsx                               # mount the consent modal + welcome card status
│   ├── components/
│   │   ├── WelcomeCard.tsx                   # MODIFY — embed AI status string from store
│   │   ├── ConsentModal.tsx                  # NEW — shadcn Dialog implementing FR-019
│   │   └── ui/
│   │       └── dialog.tsx                    # NEW — shadcn dialog primitives (via `npx shadcn add dialog`)
│   ├── lib/
│   │   ├── tauri-bridge.ts                   # NEW — typed wrapper around invoke() + listen()
│   │   └── status-store.ts                   # NEW — zustand store mirroring AppStatus
│   └── __tests__/
│       ├── App.test.tsx                      # extend to test status updates + modal visibility
│       ├── WelcomeCard.test.tsx              # extend with status-string assertions
│       ├── ConsentModal.test.tsx             # new — modal flow + consent dispatch
│       └── status-store.test.ts              # new — zustand state transitions
```

**Structure Decision**: Extend spec 001's two-tree layout. New Rust module `src-tauri/src/sidecar/` keeps lifecycle/client/consent isolated and testable. New React module `src/lib/` houses the Tauri bridge + zustand store. The `scripts/fetch-ollama.sh` is repo-level since it's a build-time concern.

## Phase 0 — Research output

See [research.md](./research.md). Topics: bundled-binary fetch and version pin, sidecar plugin scope, app-data persistence, Ollama API shapes, log-safe handling of prompts/responses, capability minimization, registry domain pinning, fail-fast on missing binary.

## Phase 1 — Design output

- [data-model.md](./data-model.md) — Rust types and React store mirroring `spec.allium` entities.
- [contracts/tauri-commands.md](./contracts/tauri-commands.md) — the four `#[tauri::command]`s exposed to the WebView.
- [contracts/tauri-events.md](./contracts/tauri-events.md) — the events Rust emits to React (status changes, progress).
- [contracts/ollama-api-usage.md](./contracts/ollama-api-usage.md) — exact Ollama endpoints we call.
- [contracts/capabilities.md](./contracts/capabilities.md) — the updated `capabilities/default.json` shape (adds exactly the permissions FR-016 requires).
- [contracts/consent-store.md](./contracts/consent-store.md) — `consent.json` schema.
- [quickstart.md](./quickstart.md) — end-to-end developer walkthrough.

## Re-evaluated Constitution Check (post-Phase 1)

Post-design re-check: still PASS for all nine principles. The contracts encode the load-bearing invariants:
- `capabilities.md` enforces FR-016 (minimal allowlist) at config level.
- `ollama-api-usage.md` enumerates the only outbound destinations.
- `consent-store.md` encodes the FR-019 "once per fresh install" guarantee.
- `tauri-commands.md` shows the WebView surface is small and gated.

The log-safe module (`src-tauri/src/sidecar/log_safe.rs`) is the structural enforcement point for `NoPromptOrResponseInLogs`.

## Complexity Tracking

Empty — no constitution gate violations.
