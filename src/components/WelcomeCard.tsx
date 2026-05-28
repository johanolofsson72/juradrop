import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { useStatusStore, statusMessage } from '@/lib/status-store';

// Spec 002 welcome card — title + Swedish subtitle from spec 001, plus a
// live status string driven by the zustand store wired to Tauri events.
// The disabled "Kom igång" button from spec 001 is removed because the
// status string is now the meaningful content (not a placeholder).
//
// Post-spec-012 polish: when state is `klar` (happy path — sidecar up,
// model pulled, nothing to say), return null so the zone grid gets the
// full window without visual chrome competing for attention. The card
// re-appears automatically for begar_samtycke, laddar_ner_modell, and
// every fel_*/modell_saknas_avbruten state — preserving Principle VIII
// honest-failure-state surfacing.
export function WelcomeCard() {
  const status = useStatusStore((s) => s.status);
  if (status.visible === 'klar') return null;
  const message = statusMessage(status);
  const isError = status.visible.startsWith('fel_') || status.visible === 'modell_saknas_avbruten';

  return (
    <Card className="w-full max-w-md">
      <CardHeader className="space-y-2">
        <CardTitle className="text-2xl font-semibold tracking-tight">JuraDrop</CardTitle>
        <CardDescription className="text-sm text-muted-foreground">
          Lokal AI för svenska juriststudenter
        </CardDescription>
      </CardHeader>
      <CardContent>
        <p
          aria-live="polite"
          aria-atomic="true"
          className={
            isError
              ? 'text-sm text-destructive'
              : 'text-sm text-muted-foreground transition-colors'
          }
        >
          {message}
        </p>
      </CardContent>
    </Card>
  );
}
