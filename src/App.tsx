import { useEffect } from 'react';
import { WelcomeCard } from '@/components/WelcomeCard';
import { ConsentModal } from '@/components/ConsentModal';
import { SammanfattaZone } from '@/components/SammanfattaZone';
import { useStatusStore } from '@/lib/status-store';
import { getStatus, subscribeStatus, subscribeProgress } from '@/lib/tauri-bridge';

// Root screen. Spec 001 wired the welcome card; spec 002 added the consent
// modal (FR-019); spec 003 adds the first drop zone (Sammanfatta) beneath
// the welcome card. The welcome card carries the global "AI är redo / AI
// startar…" status; the drop zone is the working surface below it.
// On mount: seed the store via get_status, then subscribe to status +
// progress events for live updates. The zone subscribes to
// juradrop://sammanfatta on its own (inside SammanfattaZone).
export function App() {
  const setStatus = useStatusStore((s) => s.setStatus);
  const setProgress = useStatusStore((s) => s.setProgress);

  useEffect(() => {
    let statusUnsub: (() => void) | undefined;
    let progressUnsub: (() => void) | undefined;

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
    }

    return () => {
      statusUnsub?.();
      progressUnsub?.();
    };
  }, [setStatus, setProgress]);

  return (
    <main className="grid min-h-screen place-items-start bg-background p-6 text-foreground">
      <div className="mx-auto flex w-full max-w-md flex-col items-center gap-10 pt-12">
        <WelcomeCard />
        <SammanfattaZone />
      </div>
      <ConsentModal />
    </main>
  );
}
