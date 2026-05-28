# Wizard events contract — Spec 008

Spec 008 introduces **zero new event channels**. The wizard reads exclusively from the existing channels listed below. SC-007 codifies "no new outbound surface" + "no new event channels".

## Existing channels read by the wizard

### `juradrop://status` (existing, spec 002)

Payload shape (already documented in `src/lib/tauri-bridge.ts`):

```typescript
interface AppStatus {
  visible: UserVisibleStatus;
  sidecar: SidecarStatus;
  model: ModelStatus;
  progress_percent: number | null;
  consent: ConsentChoice;
}
```

The wizard reads:
- `consent` — drives the welcome trigger (FR-001).
- `model` — drives the welcome / progress / error / hidden derivation (R-001 truth table).
- `sidecar` — drives the Fortsätt-button-disabled gating during boot (clarification 4).
- `visible` — drives the error-phase Swedish copy selection.

### `juradrop://progress` (existing, spec 002)

Payload shape:

```typescript
interface ProgressEvent {
  percent: number; // 0–100
}
```

The wizard's `useProgressEstimate` hook subscribes to this channel and maintains a rolling-window byte counter + ETA estimator. The channel does NOT emit byte counts — the hook synthesises bytes from `percent * estimated_total_bytes`.

## Wizard-internal phase transitions (NOT events; React state)

| From | To | Trigger | Side effect |
|---|---|---|---|
| `welcome` | `progress` | `give_consent` returns Ok + next `juradrop://status` with `model.status = downloading` | Mount FirstRunProgress; useProgressEstimate starts |
| `welcome` | `welcome` | `cancel_consent` returns Ok | Welcome stays visible; consent.choice = avbryt |
| `progress` | `welcome` | `cancel_model_pull` returns Ok + next `juradrop://status` with `model.status = not_present`, `visible = modell_saknas_avbruten` | Unmount FirstRunProgress |
| `progress` | `error` | `juradrop://status` with `visible ∈ {fel_disk_full, fel_modellnedladdning_avbroten, fel_kunde_inte_starta, …}` | Show error sub-panel inside FirstRunProgress |
| `progress` | `hidden` | `juradrop://status` with `model.status = ready` AND `(now - mountedAt) >= 300 ms` | Unmount Wizard; mount ZoneGrid |
| `error` | `progress` | `give_consent` re-invoked via Försök-igen button | Pull task restarted from 0 |
| `error` | `welcome` | (no UI affordance for this in v0.1) | — |
| `hidden` | `welcome` | Next launch where derivation returns non-hidden (e.g. model deleted out-of-band) | App.tsx re-renders; useWizardState returns welcome |

All transitions are driven by the React layer reacting to existing channel events. No new Rust-side event emitters.

## SC-007 audit instructions

To verify zero new outbound surface:

```bash
# Should produce exactly the matches that were present before spec 008.
grep -RIn '"juradrop://' src/ src-tauri/src/ | sort -u
```

The expected match set after spec 008 lands is **the same set as after spec 007** plus zero additions. Spec 008 reuses `juradrop://status` and `juradrop://progress`; it adds no new strings of the form `juradrop://*`.

The existing spec 007 invariant test in `src-tauri/tests/update_invariants.rs::updater_introduces_no_new_outbound_surface` catches any drift on the HTTP-client surface. Spec 008 EXTENDS this test (or adds a sibling `wizard_invariants.rs::wizard_introduces_no_new_outbound_surface`) to cover the wizard-specific allowlist.
