# Implementation Plan: Strict Content-Security-Policy

**Spec**: [spec.md](./spec.md) · **Allium**: [spec.allium](./spec.allium) · **Track**: full (security invariant; TLA+ triviality gate expected)
**Branch**: `main` (direct-push per spec-register.md)

## Summary

Replace `app.security.csp: null` in `src-tauri/tauri.conf.json` with an explicit strict Content-Security-Policy, plus a separate dev-only `devCsp`, so the WKWebView can only load/connect to the app's own bundled assets, the Tauri IPC channel, and the localhost Ollama endpoint. This makes Constitution Principle I a structural runtime property. Add automated tests that pin the production policy and assert every security invariant; verify the live egress block manually in `tauri dev` (WKWebView is not drivable in CI — see spec 019).

## Technical Context

- **Config surface**: `src-tauri/tauri.conf.json` → `app.security.csp` (was `null`) + new `app.security.devCsp`.
- **Policy strings**: see research.md R-6 (production + dev).
- **Framework behavior**: Tauri 2 injects script/style nonces + sha256 hashes at build time, so `script-src 'self'` works for the bundled React app (research.md R-1). `dangerousDisableAssetCspModification` stays at default (enabled).
- **Test surface**:
  - Rust: a `csp` config test (new, e.g. `src-tauri/src/security/csp.rs` or a test module that reads the bundled config) asserting the production policy satisfies FR-002…FR-005, FR-012…FR-014, and `csp != null`.
  - A structural test asserting `script-src` contains neither `'unsafe-inline'` nor `'unsafe-eval'`, `connect-src` contains zero non-localhost hosts, and no `report-uri`/`report-to` token appears.
- **No frontend code changes** — the renderer already makes no remote requests (research.md R-3).
- **No new dependencies, no new outbound destinations** (FR-011).

## Constitution Check

| Principle | Impact | Verdict |
|---|---|---|
| I. Privacy by Architecture | This spec STRENGTHENS it — turns the no-egress promise into an enforced policy. Adds zero outbound destinations. | ✅ Strengthens |
| III. Local-Only Inference | Ollama origins limited to `127.0.0.1`/`localhost`:11434; no remote host token anywhere. | ✅ Upholds |
| VII. Bundled Sidecar | No change to sidecar lifecycle. | ✅ Neutral |
| VIII. Honest Failure States | No new user-facing copy; a blocked egress is a security event, not a user error. | ✅ Neutral |
| II/IV/V/VI | No install-path, single-user, i18n, or native-feel impact. | ✅ Neutral |

No violations. No complexity-tracking entries needed.

## Project Structure

### Documentation (this feature)
- spec.md, spec.allium, research.md, plan.md (this file), data-model.md, contracts/csp-policy.md, quickstart.md, checklists/requirements.md

### Source Code (repository root)
- `src-tauri/tauri.conf.json` — set `csp` + `devCsp` (the change).
- `src-tauri/src/security/` (new module) OR an existing test module — the policy-pinning + invariant tests reading the bundled config string.
- No `src/**` changes.

## Build sequence

1. Edit `tauri.conf.json`: set production `csp` and `devCsp` (research.md R-6).
2. Add the Rust test(s) pinning the production policy and asserting FR-002…FR-005, FR-012…FR-014, FR-010 (no report endpoint, localhost-only connect-src, no unsafe script, defense-in-depth directives present, csp != null).
3. Run `cargo test`, `npm test`, `cargo clippy -- -D warnings`, `cargo fmt --check`, `npm run lint && npm run typecheck` — all must stay green (SC-002).
4. Manual: `npm run tauri dev`, drop a document on a zone (Ollama round-trip works under CSP, SC-003), click the GitHub About link (FR-007), and run the egress-probe snippet from quickstart in the devtools console (SC-001).
5. `/tla` (expected triviality-gate skip — single static config value, no transitions), then commit + push to main, tick register.

## Phase 2 (TLA+) expectation

The "state machine" is one static policy value with no transitions and a single actor — it will hit the TLA+ triviality gate (≤3 states, no concurrency, no async). The security invariants are enforced structurally by the config + the pinning test, not by a temporal property. `/tla` will record the triviality skip with rationale.
