# Quickstart / Test Flows — Spec 026

## Functional coverage (one test per implemented function)

1. **Reuse external Ollama** — with an Ollama already serving on the port, launch → readiness reaches `ready` with `ownership=reused_external`; all nine zones enabled; a dropped doc processes. (integration / gated real-Ollama)
2. **Spawn bundled when port free** — no Ollama running → bundled sidecar spawns, `ownership=we_started`, reaches `ready`.
3. **Port conflict** — non-Ollama listener on the port → `port_conflict` status, honest Swedish message, zones disabled, no crash/leak.
4. **Single readiness truth** — in every readiness state, assert `header-ready == all-zones-enabled` (regression test for the drift bug). (Rust unit + vitest)
5. **Shutdown honors ownership** — `ownership=reused_external` → no stop issued; `ownership=we_started` → stop issued. (Rust unit)
6. **Drag-over highlight** — dragover event over a zone (app ready) lights exactly that zone; moving zones hands off; leave/drop clears. (`drag-hover.test.ts` — DONE, 8 cases)
7. **Välj fil clickable when ready / inert when not** — picker opens iff ready. (vitest)
8. **Window startup size** — config asserts 1160×760; min/responsive unchanged. (vitest/config assertion)

## Destructive scenarios (≥8 across the 6 attack categories)

1. **Invalid input**: port answered by a process returning garbage/non-JSON to `/api/tags` → treated as port-conflict, not a crash. (cat 1)
2. **Boundary/race**: port free at probe, occupied by the time we spawn → resolves to a single consistent state, never half-ready. (cat 4/5)
3. **Timing**: drag-over events arriving before readiness → no highlight. (cat 5)
4. **Wrong order**: drop released outside any zone → nothing processed, no stuck highlight. (cat 2)
5. **Rapid dragging**: fast zone-to-zone drag → never more than one zone highlighted. (cat 5)
6. **Skip steps**: "Välj fil" invoked while not ready → picker does not open. (cat 3)
7. **Mid-session death**: reused external Ollama killed mid-session → existing spec-011 honest-failure path; app never claims ready while unreachable. (cat 5)
8. **Privacy**: assert no new outbound destination introduced; AI host stays loopback (telemetry/privacy denylist). (cat 1 / Principle I)
9. **Accessibility**: "Välj fil" reachable by keyboard; Esc/Tab behavior on the port-conflict state unaffected. (cat 6)

## Manual hardware verification (real Mac)

- With Homebrew/Ollama.app already running → JuraDrop launches fully usable; quitting JuraDrop leaves the external Ollama running.
- Drag a real `.docx` over each zone → glow + accepted-drop cursor; drop → processes.
- Launch at default size → all nine zones visible.
