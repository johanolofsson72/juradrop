# Tasks: Strict Content-Security-Policy (spec 030)

**Track**: full · **Branch**: `main` (direct-push)
Source of truth: spec.md, spec.allium, plan.md, contracts/csp-policy.md.

## Phase 1 — Implementation

- [ ] T001 — Set the production `csp` in `src-tauri/tauri.conf.json` `app.security.csp` to the strict policy string (contracts/csp-policy.md production block). Replaces `null`.
- [ ] T002 — Add `app.security.devCsp` with the dev policy string (contracts/csp-policy.md dev block: production + `http://localhost:1420` + `ws://localhost:1420`).

## Phase 2 — Functional coverage tests (one per pinned guarantee)

Implemented "functions" here = the seven contract guarantees C-1…C-7. A Rust
test module (`src-tauri/src/security/csp_test.rs` or a `#[cfg(test)]` module
that reads the bundled `tauri.conf.json` via `include_str!` / `env!("CARGO_MANIFEST_DIR")`)
covers each:

- [ ] T003 — Test C-1: production `csp` is present, non-null, non-empty (FR-001).
- [ ] T004 — Test C-2: `connect-src` host set ⊆ the five allowed localhost/self/ipc tokens; zero other hosts (FR-002/003, SC-005).
- [ ] T005 — Test C-3: `script-src` has `'self'`, lacks `'unsafe-inline'` + `'unsafe-eval'` + any `http(s)://` host (FR-004/012).
- [ ] T006 — Test C-4: no `report-uri` / `report-to` token anywhere (FR-013).
- [ ] T007 — Test C-5: `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, `form-action 'self'` all present (FR-014).
- [ ] T008 — Test C-6: `style-src`/`img-src`/`font-src` carry no `http(s)://` remote host; `data:` only on img/font (FR-005).
- [ ] T009 — Test C-7: `devCsp` exists, differs from `csp` only by dev-origin/ws additions, and still satisfies C-4 + C-5 (FR-015 — dev never relaxes report/defense-in-depth).

## Phase 3 — Destructive / regression scenarios

CSP enforcement lives in WKWebView (not CI-drivable). Destructive coverage here
is (a) regression — nothing else breaks — and (b) tamper-resistance of the pin:

- [ ] T010 — Boundary: a synthetic CSP string with a smuggled remote `connect-src` host FAILS C-2 (proves the test actually catches a leak, not just rubber-stamps).
- [ ] T011 — Boundary: a synthetic CSP with `'unsafe-inline'` in `script-src` FAILS C-3.
- [ ] T012 — Boundary: a synthetic CSP carrying `report-to` FAILS C-4.
- [ ] T013 — Regression: full `cargo test` suite green (updater, shell, sidecar, all zones) — FR-006/007/008, SC-002.
- [ ] T014 — Regression: full `npm test` + `npm run typecheck` + `npm run lint` green (no frontend behavior change).
- [ ] T015 — Lint/format: `cargo clippy --all-targets -- -D warnings` + `cargo fmt --check` clean.

## Phase 4 — Manual verification (quickstart.md)

- [ ] T016 — `tauri dev`: UI renders fully (SC-004), document drop works (SC-003), GitHub link opens (FR-007), devtools egress probe blocked (SC-001), a zone runs proving IPC intact.

## Phase 5 — Pipeline close

- [ ] T017 — `/tla` (expected triviality-gate skip; record rationale).
- [ ] T018 — Commit + push to `main`; tick spec 030 in `specs/INDEX.md`.

## Notes

- No `src/**` changes (renderer makes no remote requests).
- Net new dependencies: 0. Net new outbound destinations: 0 (FR-011).
- The T010/T011/T012 negative tests guard against a future edit silently loosening the policy (FR-010 — the pin is only as good as its ability to fail).
