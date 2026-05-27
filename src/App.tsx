import { useEffect } from 'react';
import { WelcomeCard } from '@/components/WelcomeCard';
import { ConsentModal } from '@/components/ConsentModal';
import { DropZone } from '@/components/DropZone';
import { ZONE_ORDER } from '@/components/DropZone.identity';
import { UpdateIndicator } from '@/components/UpdateIndicator';
import { UpdateRetryFootnote } from '@/components/UpdateRetryFootnote';
import { useStatusStore } from '@/lib/status-store';
import { ensureUpdateStatusSubscription } from '@/lib/update-store';
import {
  dispatchToZone,
  getStatus,
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

  useEffect(() => {
    let statusUnsub: (() => void) | undefined;
    let progressUnsub: (() => void) | undefined;
    let dropUnsub: (() => void) | undefined;

    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

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
        const el = document.elementFromPoint(position.x, position.y);
        const zoneEl = el?.closest('[data-zone-id]') as HTMLElement | null;
        if (!zoneEl) return; // drop outside any zone — silently ignore
        const zoneId = zoneEl.dataset.zoneId as ZoneId | undefined;
        if (!zoneId) return;
        void dispatchToZone(zoneId, paths);
      }).then((fn) => {
        dropUnsub = fn;
      });
    }

    return () => {
      statusUnsub?.();
      progressUnsub?.();
      dropUnsub?.();
    };
  }, [setStatus, setProgress]);

  return (
    <main className="min-h-screen bg-background p-6 text-foreground">
      <div className="mx-auto flex w-full max-w-5xl flex-col items-center gap-8 pt-8">
        <WelcomeCard />
        <section
          aria-label="Drop-zoner"
          className={[
            'grid w-full gap-4',
            'grid-cols-1',         // < 520 px (rare on desktop)
            'sm:grid-cols-2',      // ≥ 520 px
            'lg:grid-cols-3',      // ≥ 920 px (the canonical 2×3)
          ].join(' ')}
        >
          {ZONE_ORDER.map((id) => (
            <DropZone key={id} zoneId={id} />
          ))}
        </section>
      </div>
      <ConsentModal />
      {/* Spec 007 — auto-updater UI. Fixed-positioned overlays, do
          not disturb the 2×3 grid layout. */}
      <UpdateIndicator />
      <UpdateRetryFootnote />
    </main>
  );
}
