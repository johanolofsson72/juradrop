# Research notes — Spec 008 first-run wizard

## R-001 — WizardPhase derivation: pure-function vs persisted state

**Decision**: The wizard phase is a **pure function of `AppStatus`**, computed in a `useWizardState` hook on every status update. No persisted React state, no Zustand slice, no Rust-side mirror.

**Truth table** (the hook):

| `consent.choice` | `model.status` | `visible` | `sidecar.status` | → `WizardPhase` |
|---|---|---|---|---|
| `not_asked` | (any) | (any) | (any) | `welcome` |
| `avbryt` | (any) | (any) | (any) | `welcome` |
| `fortsatt` | `not_present` | (any) | (any) | `welcome` |
| `fortsatt` | `download_failed` | (any) | (any) | `error` |
| `fortsatt` | `downloading` | `laddar_ner_modell` | (any) | `progress` |
| `fortsatt` | `downloading` | `fel_disk_full` | (any) | `error` |
| `fortsatt` | `downloading` | `fel_modellnedladdning_avbroten` | (any) | `error` |
| `fortsatt` | (any) | `modell_saknas_avbruten` | (any) | `welcome` |
| `fortsatt` | `ready` | `klar` | `ready` | `hidden` |

The truth table is the entire derivation. The hook is < 30 lines.

**Why**: Persisting the phase in React state would race with `juradrop://status` events and require an explicit re-sync on every consent/model change. A pure function has no race surface — the phase is always consistent with the latest `AppStatus` snapshot. The minimum-visible-time requirement (FR-019) is handled by a separate `useMinVisibleHold` hook that wraps the pure derivation, not by state.

**Rejected alternative**: a Zustand slice mirroring `WizardPhase`. Adds 30 lines of mirror code + a race condition; gains nothing because the input AppStatus is already a Zustand slice.

## R-002 — ETA throughput estimate: rolling window strategy

**Decision**: A **10-second rolling window** of `(timestamp, byte_count)` samples, with the ETA computed as `(total_bytes - last_byte_count) / mean_bps_over_window`.

**Implementation sketch** (`use-progress-estimate.ts`):

```typescript
interface Sample { t: number; bytes: number; }
const WINDOW_MS = 10_000;

function meanBps(samples: Sample[]): number {
  if (samples.length < 2) return 0;
  const oldest = samples[0];
  const newest = samples[samples.length - 1];
  const dt = (newest.t - oldest.t) / 1000;
  if (dt <= 0) return 0;
  return (newest.bytes - oldest.bytes) / dt;
}
```

Per progress event:
1. Push `{ t: now, bytes: bytes_now }`.
2. Drop samples older than `now - WINDOW_MS`.
3. Compute `mean_bps`.
4. If `mean_bps == 0` → `eta_seconds = null` (render "—").
5. Else `eta_seconds = (total_bytes - bytes_now) / mean_bps`.

The window is intentionally short (10 s) so the ETA reflects the **current** throughput, not a stale long-term average. On a 5 G connection that suddenly drops to LTE, the ETA adjusts within ~10 s — which matches the user's mental model.

**Rejected alternative**: an exponential moving average (EMA) with α = 0.1. The EMA is smoother but trails real changes by a much longer window; on a network drop it would take 30+ s for the ETA to reflect reality.

**Network-drop trigger**: the same sample buffer doubles as the waiting-on-network detector. If `now - last_sample.t >= 5000 ms` AND the wizard is in `progress` phase, the label flips to `waiting`. The next sample flips it back. The 5-second threshold is the FR-007 clarification.

## R-003 — Cancel-race semantics: lock-acquire-order resolution

**Decision**: The existing `parking_lot::RwLock<ModelStatus>` from spec 002 governs the race. The new `cancel_model_pull` command acquires the write-lock and reads the current `ModelStatus` under the lock:

```rust
pub async fn cancel_model_pull(state: tauri::State<'_, AppState>, app: AppHandle) -> Result<(), String> {
    let mut status = state.model_status.write();
    if *status == ModelStatus::Ready {
        // Cancel-race: download already completed. Silent no-op.
        return Ok(());
    }
    if *status != ModelStatus::Downloading {
        // Already cancelled, never started, or failed. Idempotent.
        return Ok(());
    }
    // Cancel won the race: trip the token + flip status + emit event.
    state.pull_cancel.cancel();
    *status = ModelStatus::NotPresent;
    *state.error_override.write() = Some(UserVisibleStatus::ModellSaknasAvbruten);
    drop(status); // release before emit
    let _ = app.emit("juradrop://status", state.snapshot());
    Ok(())
}
```

The lock-acquire-order resolution means **exactly one** of these two outcomes always wins, never a flickering intermediate:
- Cancel acquires the lock BEFORE the pull task's `Completed` event marks `status = Ready` → cancel wins, wizard returns to welcome.
- Pull task's `Completed` event marks `status = Ready` BEFORE cancel acquires the lock → cancel is no-op, wizard transitions to hidden.

Both outcomes are user-coherent — the wizard never shows a frozen "Hämtar…" after a completed download.

**Rejected alternative**: a cancellation token alone, no status check. Risks the user seeing "Cancelled" copy after the download finished successfully — confusing and inconsistent.

## R-004 — Sidecar-boot gating: disabling the Fortsätt button

**Decision**: The Fortsätt button reads `sidecar.status === 'ready'` from the `useStatusStore` mirror. While the sidecar is `starting` or `not_started`, Fortsätt is rendered with `disabled={true}` + a small italic helper line below the CTAs reads "Förbereder AI-motorn…" (FR-002 clarification).

**Why a disabled button + helper line, not a loading spinner**: The user is on a welcome screen reading prose; a spinner under the buttons would feel like a modal dialog hijacking attention. A subtle italic line in the muted-foreground color (matching the spec 007 `UpdateRetryFootnote` pattern) reassures without dominating. The button is greyed but visibly part of the layout, so the user knows what's about to happen.

**Boot window**: spec 002's contract says the sidecar reaches Ready in ≤ 10 s (SC-001 of spec 002). In practice on M-series hardware it's ≤ 2 s. The user reads the welcome paragraph in ~5 s; by the time their eye reaches the Fortsätt button, the helper line is gone.

## R-005 — Minimum-visible time: useMinVisibleHold strategy

**Decision**: A small `useMinVisibleHold(actualPhase, minMs)` hook holds the **previous phase** for at least `minMs` (default 300) after a transition. When the model pull completes instantly (cached install, fiber link, or a fast Rust unit-test path), the wizard would otherwise mount and unmount in < 100 ms, producing a flicker.

**Implementation sketch**:

```typescript
function useMinVisibleHold(actual: WizardPhase, minMs: number): WizardPhase {
  const [held, setHeld] = useState(actual);
  const mountedAt = useRef(Date.now());
  useEffect(() => {
    const elapsed = Date.now() - mountedAt.current;
    if (elapsed >= minMs) {
      setHeld(actual);
      mountedAt.current = Date.now();
    } else {
      const timer = setTimeout(() => {
        setHeld(actual);
        mountedAt.current = Date.now();
      }, minMs - elapsed);
      return () => clearTimeout(timer);
    }
  }, [actual, minMs]);
  return held;
}
```

The hook only delays the **hide** transition (the visible-to-hidden moment). Other phase changes pass through immediately (the user is still looking at the wizard either way).

**Rejected alternative**: a CSS `animation-delay` of 300 ms. Doesn't actually delay the component unmount, only the visual fade-out; the React tree mismatch would still cause a layout shift.

## R-006 — Welcome paragraph copy: humanizer-first design

**Decision**: The welcome body paragraph is locked at spec time (clarification 1) at exactly **199 characters** so the SwedishCopy invariant `length <= 200` has a 1-char headroom. The full text:

> JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst.

**Humanizer applied**: The early draft included "ger dig kraftfullt stöd" (AI-tinged + promotional). Replaced with the literal verb list ("sammanfatta, översätta, anonymisera, punktlista och förenkla") — every verb is the actual name of one of the six zones. The paragraph serves double duty as a feature preview.

**Why exactly 199 chars**: We could make it shorter, but the verb list IS the feature preview. Cutting any verb would mean a zone goes unnamed on the welcome — confusing.

**Rejected alternative**: a longer multi-paragraph welcome with bullet points. Adds reading time + lengthens the boot window where the user is staring at copy waiting for Fortsätt to enable.

## R-007 — Subsequent-launch silence: render the right thing immediately

**Decision**: `App.tsx` checks `useWizardState()` at the **top of its render**. The default React 18 render is synchronous from the moment the WebView's JS loads; the very first render emits either `<Wizard />` (if the truth table says non-hidden) OR `<ZoneGrid />` (if `hidden`).

**Critical detail**: `useStatusStore` is hydrated on first render with the result of the initial `getStatus` invocation from the Tauri bridge layer. That invocation is synchronous in dev and ~50 ms in production. We do NOT render a placeholder while the status loads — we render the welcome wizard, then immediately swap to zone-grid if the status update flips the phase.

**Mitigation against an initial-flicker**: the `useMinVisibleHold` hook prevents the wizard from flashing for < 300 ms. If the initial `getStatus` lands within 300 ms and reveals the wizard should be hidden, the wizard stays visible for the remaining hold time, then dismounts. From the user's perspective, the initial paint either shows the wizard (fresh install path) or shows the zone-grid (subsequent-launch path) — never a mid-state.

## R-008 — Zone-gating via App.tsx conditional render

**Decision**: App.tsx renders **exactly one** of:
- `<Wizard />` when `useWizardState() != 'hidden'`
- `<ZoneGrid />` (the existing 2×3 zone layout) when `useWizardState() === 'hidden'`

This closes the FR-005 + FR-018 gates structurally — the zones are not in the React tree at all while the wizard is mounted, so they can't be drag-targets, can't intercept Tab focus, and can't render any partial state.

**Rejected alternative**: rendering both in parallel with a CSS `pointer-events: none` overlay over the zones. Brittle — keyboard navigation still reaches the zones via Tab; screen readers still announce them; the disabled state has to be plumbed to six separate DropZone components.

## R-009 — Network-drop label switch via the same progress sample buffer

**Decision**: The `use-progress-estimate.ts` hook owns the sample buffer. Inside the same hook, a `setInterval(checkStale, 1000)` checks `(now - last_sample.t)` every second. If it exceeds 5000 ms while in `progress` phase, the label state flips to `waiting`. The next genuine progress sample flips it back AND resets the buffer's start point so the ETA estimator doesn't account for the dead time.

**Why a 1 s polling interval**: Tauri events are push-based via the IPC channel; we can't subscribe to "no event arrived for X ms" directly. A 1 s poll is cheap (1 timer per session) and well below the 5 s threshold so the label reliably flips within 5–6 s of the actual drop.

## R-010 — Test isolation: avoid hitting Ollama in unit tests

**Decision**: The `WelcomeWizard.test.tsx` + `FirstRunProgress.test.tsx` tests drive `useStatusStore` synchronously via `useStatusStore.setState({...})` — same pattern as the spec 003 `SammanfattaZone.test.tsx`. The wizard components are pure functions of the store; no Tauri bridge calls fire in tests.

The integration test `tests/cancel_model_pull.rs` uses `wiremock` for the Ollama HTTP surface (same as spec 002's `pull_robustness.rs`). No real network.

## R-011 — Reused vocabulary inventory

This spec adds 9 new visible Swedish strings + 1 long welcome paragraph (199 chars). The existing vocabulary already covers:
- `Startar AI…` (sidecar boot, from spec 002)
- `Klar` (model ready, from spec 002)
- `Modellnedladdningen avbröts — försök igen` (download failure, from spec 002)
- All 6 `UserVisibleStatus` error variants

New strings (each ≤ 80 chars except the welcome paragraph at ≤ 200):

| Key | String | Used in |
|---|---|---|
| `welcome_title` | `Välkommen till JuraDrop` | WelcomeWizard header |
| `welcome_paragraph` | `JuraDrop läser dokument lokalt på din Mac och hjälper dig sammanfatta, översätta, anonymisera, punktlista och förenkla juridisk text — utan att något skickas till någon molntjänst.` | WelcomeWizard body |
| `welcome_privacy_line` | `Inget dokumentinnehåll lämnar din Mac.` | WelcomeWizard privacy reassurance |
| `welcome_download_note` | `En AI-modell på cirka 2 GB laddas ner första gången du startar appen — efter det fungerar allt utan nät.` | WelcomeWizard download expectation |
| `welcome_cta_primary` | `Fortsätt` | WelcomeWizard primary button |
| `welcome_cta_secondary` | `Avbryt` | WelcomeWizard secondary button |
| `welcome_sidecar_helper` | `Förbereder AI-motorn…` | WelcomeWizard sidecar-boot helper line |
| `progress_label_downloading` | `Hämtar AI-modell…` | FirstRunProgress active-download label |
| `progress_label_waiting` | `Väntar på nätverk…` | FirstRunProgress network-drop label |
| `progress_cancel_button` | `Avbryt nedladdning` | FirstRunProgress Cancel button |
| `progress_eta_unknown` | `—` | FirstRunProgress ETA when bps=0 (rendered as literal em-dash) |
| `progress_error_retry` | `Försök igen` | FirstRunProgress error-state retry button |

12 keys total in `wizard-strings.json`. Each gets a corresponding TS-side mirror in `src/lib/wizard-strings.ts` and the same cross-language drift test pattern as spec 007's `UpdateFailure.errors.test.tsx`.
