import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { useStatusStore } from '@/lib/status-store';

// FR-019 consent modal — shown exactly once per fresh install, before the
// app makes its only authorized outbound network call (model pull from
// ollama.com). The user actively opts in or cancels.
export function ConsentModal() {
  const status = useStatusStore((s) => s.status);
  const give = useStatusStore((s) => s.giveConsent);
  const cancel = useStatusStore((s) => s.cancelConsent);

  const open = status.visible === 'begar_samtycke' && status.consent === 'not_asked';

  return (
    <Dialog open={open}>
      <DialogContent className="sm:max-w-md" aria-describedby="consent-body">
        <DialogHeader>
          <DialogTitle>Ladda ner AI-modell</DialogTitle>
          <DialogDescription id="consent-body">
            JuraDrop hämtar nu en AI-modell (~3 GB) från ollama.com. Det är enda
            gången något skickas utanför din Mac.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="gap-2 sm:gap-2">
          <Button type="button" variant="outline" onClick={() => void cancel()}>
            Avbryt
          </Button>
          <Button type="button" onClick={() => void give()}>
            Fortsätt
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
