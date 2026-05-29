# Data Model — Spec 026

## SidecarReadiness (the single source of truth)

| Field | Type | Notes |
|---|---|---|
| `status` | enum: `probing` \| `ready` \| `port_conflict` \| `failed` | drives BOTH global header + per-zone gate |
| `ownership` | enum: `none` \| `reused_external` \| `we_started` | decides shutdown behavior |

**Transitions** (`status`):
- `probing → ready` (reused external, or bundled came up)
- `probing → port_conflict` (port held by non-Ollama listener)
- `probing → failed` (bundled spawn failed, port was free)
- `ready ↔ failed` (mid-session death + recovery — **owned by spec 011**, not re-modeled here)

**Invariants**:
- `status = ready ⟹ ownership ∈ {reused_external, we_started}`
- `status ∈ {probing, port_conflict, failed} ⟹ ownership = none`
- `ownership = reused_external ⟹ the external process is never stopped by us`

**Derived**: `is_ready = (status == ready)` — the ONE value the rest of the app consumes.

## Zone (existing entity, gate clarified)

| Field | Type | Notes |
|---|---|---|
| `slug` | String | one of the 9 zone ids |
| `state` | enum: `idle` \| `dragover` \| `processing` \| `success` \| `error` | unchanged |
| `disabled` | derived = `not SidecarReadiness.is_ready` | MUST be derived from the single truth, not an independent signal |

**Cross-entity invariant (the headline fix)**: for every Zone, `disabled == not SidecarReadiness.is_ready`. The global header readiness and per-zone `disabled` therefore agree in every reachable state (FR-004 / SC-002).

## UserVisibleStatus (existing enum, one new variant)

Existing: `startar | laddar_ner_modell | begar_samtycke | klar | fel_kunde_inte_starta | fel_porten_upptagen* | ...`

- **New/clarified**: a port-conflict variant surfaced as a calm Swedish `fel_*` status (no port number / "Ollama" / errno per Principle VII). (Note: a `fel_porten_upptagen`-style internal enum name is fine in code; the *user-facing string* must hide the implementation.)

## No new persistence

Readiness is in-memory; window size is static config. No storage, no migration, no new outbound destinations (Principle I).
