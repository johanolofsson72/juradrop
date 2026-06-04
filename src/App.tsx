import { useCallback, useEffect } from 'react';
import { WelcomeCard } from '@/components/WelcomeCard';
import { ConsentModal } from '@/components/ConsentModal';
import { DropZone } from '@/components/DropZone';
import { ZONE_ORDER } from '@/components/DropZone.identity';
import { InstructionField } from '@/components/InstructionField';
import { instructionForDispatch } from '@/lib/instruction-store';
import { GearIcon } from '@/components/GearIcon';
import { HelpIcon } from '@/components/HelpIcon';
import { HelpPanel } from '@/components/HelpPanel';
import { SettingsPanel } from '@/components/SettingsPanel';
import { UpdateIndicator } from '@/components/UpdateIndicator';
import { UpdateRetryFootnote } from '@/components/UpdateRetryFootnote';
import { Wizard } from '@/components/Wizard';
import { ensureSettingsSubscription, useSettingsStore } from '@/lib/settings-store';
import { ensureTierDownloadSubscription } from '@/lib/tier-download-store';
import { useStatusStore } from '@/lib/status-store';
import { ensureUpdateStatusSubscription } from '@/lib/update-store';
import { useCmdComma } from '@/lib/use-cmd-comma';
import { useHelpPanel } from '@/lib/use-help-panel';
import { useSettingsPanel } from '@/lib/use-settings-panel';
import { useWizardState } from '@/lib/use-wizard-state';
import { createDragHoverTracker } from '@/lib/drag-hover';
import { applyAppearance } from '@/lib/appearance';
import { useAppearanceStore } from '@/lib/appearance-store';
import {
  dispatchToZone,
  getStatus,
  subscribeFileDragLeave,
  subscribeFileDragOver,
  subscribeFileDropped,
  subscribeProgress,
  subscribeStatus,
  type ZoneId,
} from '@/lib/tauri-bridge';

// Root screen.
//   spec 001: welcome card.
//   spec 002: consent modal (FR-019).
//   spec 003: first drop zone (Sammanfatta).
//   spec 004: 2×3 grid of six drop zones + elementFromPoint routing
//             for the OS-level drop event (FR-010a).
//
// On mount we seed the store via get_status, subscribe to status +
// progress events, and listen for `juradrop://file-dropped` so we
// can resolve which zone DOM element was under the cursor at drop
// time and dispatch to it.
export function App() {
  const setStatus = useStatusStore((s) => s.setStatus);
  const setProgress = useStatusStore((s) => s.setProgress);
  const appearance = useAppearanceStore((s) => s.appearance);

  // Spec 026 — theme controller. Apply the saved appearance, and when it's
  // "system", re-apply whenever the OS light/dark flips. The inline script in
  // index.html applies it before first paint; this keeps it reactive.
  useEffect(() => {
    applyAppearance(appearance);
    if (appearance !== 'system') return;
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => applyAppearance('system');
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, [appearance]);

  useEffect(() => {
    let statusUnsub: (() => void) | undefined;
    let progressUnsub: (() => void) | undefined;
    let dropUnsub: (() => void) | undefined;
    let dragoverUnsub: (() => void) | undefined;
    let dragleaveUnsub: (() => void) | undefined;

    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

    // Spec 026 — drives the per-zone hover highlight during an OS drag.
    // Tauri's OS-level drag-drop suppresses the WebView's HTML5 dragover,
    // so the highlight rides the native Over/Leave events forwarded by
    // Rust (lib.rs). Routing logic lives in createDragHoverTracker, which
    // is unit-tested in drag-hover.test.ts.
    const hover = createDragHoverTracker({
      zoneAtPoint: (x, y) => {
        const el = document.elementFromPoint(x, y);
        const zoneEl = el?.closest('[data-zone-id]') as HTMLElement | null;
        return (zoneEl?.dataset.zoneId as ZoneId | undefined) ?? null;
      },
      getZone: (id) => {
        // Spec 026 — gate the hover highlight on the GLOBAL readiness truth
        // (same as DropZone), not the racy per-zone disabled flag.
        const st = useStatusStore.getState();
        const snap = st.zones[id];
        return snap ? { ...snap, disabled: st.status.visible !== 'klar' } : undefined;
      },
      setZone: (id, next) => useStatusStore.getState().setZone(id, next),
    });

    if (inTauri) {
      void getStatus()
        .then(setStatus)
        .catch(() => {
          // Pre-mount race: setup may still be initializing; events will catch up.
        });

      void subscribeStatus(setStatus).then((fn) => {
        statusUnsub = fn;
      });
      void subscribeProgress(setProgress).then((fn) => {
        progressUnsub = fn;
      });

      // Spec 007 — ensure the update-status listener is registered
      // once per app lifetime. Idempotent; subsequent renders/HMR
      // reloads are no-ops.
      ensureUpdateStatusSubscription();

      // FR-010a — OS drop → elementFromPoint → dispatch_to_zone.
      void subscribeFileDropped(({ paths, position }) => {
        hover.clear();
        const el = document.elementFromPoint(position.x, position.y);
        const zoneEl = el?.closest('[data-zone-id]') as HTMLElement | null;
        if (!zoneEl) return; // drop outside any zone — silently ignore
        const zoneId = zoneEl.dataset.zoneId as ZoneId | undefined;
        if (!zoneId) return;
        // Spec 041 — pin the instruction at drop time (FR-006); the
        // pick path in pickFileForZone does the same.
        void dispatchToZone(zoneId, paths, instructionForDispatch());
      }).then((fn) => {
        dropUnsub = fn;
      });

      // Spec 026 — light up the idle zone under the cursor while dragging.
      void subscribeFileDragOver((position) => {
        hover.over(position.x, position.y);
      }).then((fn) => {
        dragoverUnsub = fn;
      });

      // Spec 026 — drag left the window without dropping → clear highlight.
      void subscribeFileDragLeave(() => {
        hover.clear();
      }).then((fn) => {
        dragleaveUnsub = fn;
      });
    }

    return () => {
      statusUnsub?.();
      progressUnsub?.();
      dropUnsub?.();
      dragoverUnsub?.();
      dragleaveUnsub?.();
    };
  }, [setStatus, setProgress]);

  // Spec 008 / T014 — render the wizard OR the zone-grid, never both.
  // The wizard owns the entire viewport while visible (FR-005 +
  // FR-018); zones are absent from the React tree until the model is
  // ready. UpdateIndicator + UpdateRetryFootnote (spec 007 chrome)
  // stay mounted in both paths since they're top/bottom-right overlays.
  const wizardPhase = useWizardState();

  // Spec 010 — settings panel. Subscribe to persisted snapshot on
  // first mount; the panel-visibility hook owns the slide-in state
  // machine. The gear icon stays mounted in both wizard and zone-grid
  // paths but auto-disables itself while the wizard is up (FR-005a).
  useEffect(() => {
    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
    if (inTauri) {
      ensureSettingsSubscription();
      // Spec 027 — hydrate + subscribe to on-demand tier downloads so an
      // in-flight pull survives the panel closing/reopening (FR-011).
      ensureTierDownloadSubscription();
    }
  }, []);
  const settingsPanel = useSettingsPanel();
  // Spec 013 — help panel + mutual exclusion (FR-023): at most one
  // slide-in panel open at a time. Opening one closes the other.
  const helpPanel = useHelpPanel();
  const openSettings = useCallback(() => {
    helpPanel.closePanel();
    settingsPanel.openPanel();
  }, [helpPanel, settingsPanel]);
  const openHelp = useCallback(() => {
    settingsPanel.closePanel();
    helpPanel.openPanel();
  }, [helpPanel, settingsPanel]);
  const toggleSettingsPanel = useCallback(() => {
    helpPanel.closePanel();
    settingsPanel.togglePanel();
  }, [helpPanel, settingsPanel]);
  useCmdComma(toggleSettingsPanel);
  // Refresh tier pull state when the spec 008 wizard finishes a pull
  // (status flips to klar). Cheap re-fetch on every status update.
  const statusVisible = useStatusStore((s) => s.status.visible);
  const refreshSettings = useSettingsStore((s) => s.refresh);
  useEffect(() => {
    if (statusVisible === 'klar') void refreshSettings();
  }, [statusVisible, refreshSettings]);

  return (
    <main className="min-h-screen bg-background p-6 text-foreground">
      {wizardPhase !== 'hidden' ? (
        <Wizard />
      ) : (
        <div className="mx-auto flex w-full max-w-5xl flex-col items-center gap-4 pt-12">
          <WelcomeCard />
          {/* Spec 041 — per-drop instruction "half-zone": steering for
              the NEXT drop on any zone, pinned at dispatch time. */}
          <InstructionField />
          <section
            aria-label="Drop-zoner"
            className={[
              'grid w-full gap-3',
              'grid-cols-1',         // < 520 px (rare on desktop)
              'sm:grid-cols-2',      // ≥ 520 px
              'lg:grid-cols-3',      // ≥ 920 px (the canonical 3×3, 9 zones)
            ].join(' ')}
          >
            {ZONE_ORDER.map((id) => (
              <DropZone key={id} zoneId={id} />
            ))}
          </section>
        </div>
      )}
      <ConsentModal />
      {/* Spec 007 — auto-updater UI. Fixed-positioned overlays, do
          not disturb the 2×3 grid layout. */}
      <UpdateIndicator />
      <UpdateRetryFootnote />
      {/* Spec 010 — settings panel + gear icon. Both mounted in both
          paths; gear self-disables during wizard/restart-confirm. */}
      {/* Spec 013 — chrome help icon (left of gear) + help panel. */}
      <HelpIcon enabled={helpPanel.helpIconEnabled} onClick={openHelp} />
      <GearIcon enabled={settingsPanel.gearIconEnabled} onClick={openSettings} />
      <HelpPanel visibility={helpPanel.visibility} onClose={helpPanel.closePanel} />
      <SettingsPanel
        visibility={settingsPanel.visibility}
        onClose={settingsPanel.closePanel}
      />
    </main>
  );
}
