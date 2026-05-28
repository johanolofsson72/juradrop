// Spec 007 / T026 — bottom-right "Senast kollat" footnote.
//
// Subtler than UpdateIndicator — text-only, half-opacity muted. Shows
// the last-check timestamp in local time. When status is Failed,
// clicking expands a tiny popover with the Swedish failure copy + a
// "Sök efter uppdateringar igen" button (FR-010).

import { useState } from 'react';

import { checkForUpdatesNow } from '@/lib/tauri-bridge';
import { useUpdateStore } from '@/lib/update-store';

export function UpdateRetryFootnote() {
  const status = useUpdateStore((s) => s.status);
  const [expanded, setExpanded] = useState(false);

  // Compute a human-readable timestamp from the status, or fall back
  // to a placeholder when the state doesn't carry one.
  let timestampLabel = 'Inte kontrollerad än';
  if (status.state === 'up_to_date' && status.checked_at) {
    timestampLabel = `Senast sökt: ${formatTime(status.checked_at)}`;
  } else if (status.state === 'failed' && status.checked_at) {
    timestampLabel = `Senast sökt: ${formatTime(status.checked_at)}`;
  }

  const isFailed = status.state === 'failed';

  return (
    <div className="fixed bottom-3 right-3 z-40 select-none">
      <button
        type="button"
        onClick={() => setExpanded((x) => !x)}
        className="text-[11px] text-muted-foreground/70 hover:text-muted-foreground
                   transition-colors focus-visible:outline-none focus-visible:underline"
      >
        {timestampLabel}
      </button>
      {expanded && isFailed && status.state === 'failed' && (
        <div
          className="absolute bottom-full right-0 mb-2 w-72 rounded-lg border border-border
                     bg-card p-3 shadow-sm animate-in fade-in-0 slide-in-from-bottom-1
                     duration-200"
        >
          <p className="text-sm text-foreground">{status.message}</p>
          <button
            type="button"
            onClick={() => {
              void checkForUpdatesNow();
              setExpanded(false);
            }}
            className="mt-3 w-full inline-flex items-center justify-center rounded-md
                       border border-border bg-transparent text-sm font-medium h-8 px-3
                       hover:bg-muted/60 transition-colors focus-visible:outline-none
                       focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1"
          >
            Sök efter uppdateringar igen
          </button>
        </div>
      )}
    </div>
  );
}

/** Format an ISO 8601 timestamp as Swedish-locale HH:MM. Falls back
 *  to the raw string if parsing fails. */
function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toLocaleTimeString('sv-SE', { hour: '2-digit', minute: '2-digit' });
  } catch {
    return iso;
  }
}
