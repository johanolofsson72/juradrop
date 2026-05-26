import { useEffect } from 'react';
import { WelcomeCard } from '@/components/WelcomeCard';
import { ConsentModal } from '@/components/ConsentModal';
import { useStatusStore } from '@/lib/status-store';
import { getStatus, subscribeStatus, subscribeProgress } from '@/lib/tauri-bridge';

// Root screen for spec 002. Welcome card from spec 001 + the FR-019 consent
// modal (shown only when consent.choice = not_asked AND visible =
// begar_samtycke). On mount: seed the store via get_status, then subscribe to
// status + progress events for live updates.
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
    <main className="grid min-h-screen place-items-center bg-background p-6 text-foreground">
      <WelcomeCard />
      <ConsentModal />
    </main>
  );
}
