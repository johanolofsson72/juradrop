# Feature Specification: Hardware verification run (CHECKLIST — BLOCKED ON USER)

**Branch**: `main` | **Created**: 2026-05-29 | **Status**: BLOCKED (needs a real M-series Mac)
**Track**: Spec-only. Manual checklist only — no code.

## The blocker (why I can't do this)

Throughout specs 002–016, every **wall-clock / perceptual** success criterion was deferred to "a real M-series Mac" because automated tests cover the *invariants* but not the *timing a human perceives*. Those have never actually been run. I can't run them (no GUI hardware, no real model timing here). This spec collects them into one checklist for you to execute once, before `v0.1.0`.

## Pre-req
- A real Apple-Silicon Mac with the app running via `npm run tauri dev` (or the built `.app`), Ollama sidecar live, `gemma3:4b` pulled. (Spec 018's `--ignored` suite confirms the prompts work; this is about *timing + feel*.)

## Checklist — run on hardware, tick each

### First run + model download (spec 008)
- [ ] SC-005: cancel mid-download leaves a clean resumable state (no half-file crash).
- [ ] Welcome → download progress → ready flows feel correct; ETA is sane.
- [ ] Network drop mid-pull → graceful pause + resume.

### Cold launch + transitions (spec 003 / 013)
- [ ] SC-001: cold launch to usable window ≤ 60s.
- [ ] SC-005: zone state transitions (idle→dragover→processing→success) feel ≤ ~100ms / snappy.
- [ ] All 9 zones visible on launch with NO scroll/resize (the recent layout fix — confirm at 900×650).

### Per-zone real round-trip (spec 003–013)
- [ ] Drag a real `.docx` onto each of the 9 zones → sidecar appears next to it + opens automatically.
- [ ] Anonymisera: residual-PII warning appears when the model misses one (spec 014) — try a doc with an unusual personnummer format.
- [ ] Click "Välj fil" (spec 016) on a zone → native picker opens, choose a file → processes identically. Test via keyboard (Tab + Enter) too.

### Input formats (spec 005 / 009)
- [ ] SC-001/SC-002/SC-005: `.pdf`, `.txt`, `.md`, `.rtf`, `.odt` round-trips within budget; `.pages` shows the named-format error when extraction fails.

### Settings + appearance (spec 010)
- [ ] SC-001: tier change (Snabb/Smart/Stor) applies ≤ 2s.
- [ ] SC-003/SC-004: panel slide animation smooth; appearance follows system within ≤ 500ms of a light/dark switch.
- [ ] Help panel (spec 013) + per-zone (?) popovers open/close correctly; help/settings mutual exclusion holds visually.

### Auto-updater (spec 007)
- [ ] SC-001: update install ≤ 90s; SC-002: no restart while a job is processing; SC-006: NoNetwork detected ≤ 30s.

### Crash recovery (spec 011)
- [ ] SC-001: kill the Ollama sidecar mid-job → silent auto-restart + retry (one).
- [ ] SC-002: kill it twice → terminal Swedish error, no stack trace.
- [ ] SC-004: recovery within ~90s.

### Distribution (spec 020)
- [ ] After the signed DMG ships: clean-Mac install, no Gatekeeper warning.

## Status
SCAFFOLDED — checklist complete. Blocked on you running it on real hardware. Tick items here as you verify; file any failure as a new spec.
