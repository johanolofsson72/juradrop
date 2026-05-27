// Spec 007 / T020 — top-right auto-updater indicator.
//
// Non-modal badge that surfaces 4 of the 8 UpdateState variants:
// Available, Downloading, ReadyToInstall (×2 — direct + deferred),
// Restarting. Hidden for Unknown / Checking / UpToDate / Failed.
//
// FR-006 — badge clickable; expands a small panel anchored below.
// FR-007 — Downloading shows "Hämtar uppdatering… N%".
// FR-008 — ReadyToInstall shows "Klar att installera — starta om?".
// FR-009 — ReadyToInstall(deferred) shows "Väntar tills jobben är klara…"
//          + an "Avbryt" button.
// FR-018 — dismiss icon hides the badge until the next state transition.
// FR-019 — release notes rendered as plain text; empty → "Inga noteringar…".
// FR-020a — Restarting state shows "Startar om…" briefly.

import { useState } from 'react';

import {
  cancelDeferredRestart,
  confirmRestartInstall,
  dismissUpdateIndicator,
  installUpdateNow,
} from '@/lib/tauri-bridge';
import { useUpdateStore } from '@/lib/update-store';

export function UpdateIndicator() {
  const status = useUpdateStore((s) => s.status);
  const [expanded, setExpanded] = useState(false);

  // FR-006/FR-010 — visible only when state is Available / Downloading /
  // ReadyToInstall / Restarting. Everything else returns null (badge hidden).
  if (
    status.state !== 'available' &&
    status.state !== 'downloading' &&
    status.state !== 'ready_to_install' &&
    status.state !== 'restarting'
  ) {
    return null;
  }

  const handleDismiss = (e: React.MouseEvent) => {
    e.stopPropagation();
    void dismissUpdateIndicator();
    setExpanded(false);
  };

  return (
    <div className="fixed top-3 right-3 z-50 select-none">
      <button
        type="button"
        onClick={() => setExpanded((x) => !x)}
        aria-live="polite"
        role="status"
        className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full
                   bg-card/80 backdrop-blur-sm border border-border/60
                   text-xs text-muted-foreground hover:bg-muted/60 transition-colors
                   focus-visible:outline-none focus-visible:ring-2
                   focus-visible:ring-ring focus-visible:ring-offset-1"
      >
        {renderBadgeContent(status)}
      </button>

      {expanded && <ExpandedPanel status={status} onDismiss={handleDismiss} />}
    </div>
  );
}

function renderBadgeContent(status: ReturnType<typeof useUpdateStore.getState>['status']) {
  switch (status.state) {
    case 'available':
      return (
        <>
          <span className="h-1.5 w-1.5 rounded-full bg-primary" aria-hidden />
          Uppdatering tillgänglig
        </>
      );
    case 'downloading':
      return (
        <>
          <span className="h-1 w-8 rounded-full bg-muted overflow-hidden" aria-hidden>
            <span
              className="block h-full bg-primary transition-all duration-300 ease-out"
              style={{ width: `${Math.max(0, Math.min(100, status.progress_pct))}%` }}
            />
          </span>
          Hämtar uppdatering… {status.progress_pct}%
        </>
      );
    case 'ready_to_install':
      if (status.deferred) {
        return (
          <>
            <span
              className="h-1.5 w-1.5 rounded-full bg-muted-foreground/50"
              aria-hidden
            />
            Väntar tills jobben är klara…
          </>
        );
      }
      return (
        <>
          <span className="h-1.5 w-1.5 rounded-full bg-primary" aria-hidden />
          Klar att installera — starta om?
        </>
      );
    case 'restarting':
      return (
        <>
          <span
            className="h-1.5 w-1.5 rounded-full bg-primary animate-pulse"
            aria-hidden
          />
          Startar om…
        </>
      );
    default:
      return null;
  }
}

interface ExpandedPanelProps {
  status: ReturnType<typeof useUpdateStore.getState>['status'];
  onDismiss: (e: React.MouseEvent) => void;
}

function ExpandedPanel({ status, onDismiss }: ExpandedPanelProps) {
  return (
    <div
      className="absolute top-full right-0 mt-2 w-80 rounded-lg border border-border
                 bg-card p-4 shadow-sm animate-in fade-in-0 slide-in-from-top-1
                 duration-200"
    >
      {status.state === 'available' && <AvailableBody status={status} onDismiss={onDismiss} />}
      {status.state === 'downloading' && <DownloadingBody status={status} onDismiss={onDismiss} />}
      {status.state === 'ready_to_install' && (
        <ReadyToInstallBody status={status} onDismiss={onDismiss} />
      )}
      {status.state === 'restarting' && (
        <p className="text-sm text-muted-foreground">Appen startas om…</p>
      )}
    </div>
  );
}

function DismissChevron({ onClick }: { onClick: (e: React.MouseEvent) => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Dölj uppdateringsmeddelande"
      className="text-muted-foreground hover:text-foreground transition-colors
                 focus-visible:outline-none focus-visible:ring-2
                 focus-visible:ring-ring focus-visible:ring-offset-1 rounded"
    >
      <span aria-hidden className="text-base leading-none">×</span>
    </button>
  );
}

function AvailableBody({
  status,
  onDismiss,
}: {
  status: Extract<ExpandedPanelProps['status'], { state: 'available' }>;
  onDismiss: (e: React.MouseEvent) => void;
}) {
  return (
    <>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-foreground">Version {status.version}</span>
        <DismissChevron onClick={onDismiss} />
      </div>
      <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground mt-3 mb-1">
        Nyheter
      </p>
      <pre className="text-sm text-foreground whitespace-pre-wrap font-sans max-h-32 overflow-y-auto">
        {status.notes.trim() ? status.notes : 'Inga noteringar för denna version.'}
      </pre>
      <button
        type="button"
        onClick={() => void installUpdateNow()}
        className="mt-4 w-full inline-flex items-center justify-center rounded-md
                   bg-primary text-primary-foreground text-sm font-medium h-9 px-3
                   hover:bg-primary/90 transition-colors focus-visible:outline-none
                   focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1"
      >
        Installera nu
      </button>
    </>
  );
}

function DownloadingBody({
  status,
  onDismiss,
}: {
  status: Extract<ExpandedPanelProps['status'], { state: 'downloading' }>;
  onDismiss: (e: React.MouseEvent) => void;
}) {
  return (
    <>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-foreground">Version {status.version}</span>
        <DismissChevron onClick={onDismiss} />
      </div>
      <p className="mt-3 text-sm text-muted-foreground">
        Hämtar uppdatering… {status.progress_pct}%
      </p>
      <div className="mt-2 h-1.5 w-full rounded-full bg-muted overflow-hidden">
        <div
          className="h-full bg-primary transition-all duration-300 ease-out"
          style={{ width: `${Math.max(0, Math.min(100, status.progress_pct))}%` }}
        />
      </div>
    </>
  );
}

function ReadyToInstallBody({
  status,
  onDismiss,
}: {
  status: Extract<ExpandedPanelProps['status'], { state: 'ready_to_install' }>;
  onDismiss: (e: React.MouseEvent) => void;
}) {
  if (status.deferred) {
    return (
      <>
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-foreground">Version {status.version}</span>
          <DismissChevron onClick={onDismiss} />
        </div>
        <p className="mt-3 text-sm text-muted-foreground">
          Appen startar om automatiskt när alla pågående jobb är klara.
        </p>
        <button
          type="button"
          onClick={() => void cancelDeferredRestart()}
          className="mt-4 w-full inline-flex items-center justify-center rounded-md
                     border border-border bg-transparent text-sm font-medium h-9 px-3
                     hover:bg-muted/60 transition-colors focus-visible:outline-none
                     focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1"
        >
          Avbryt
        </button>
      </>
    );
  }

  return (
    <>
      <div className="flex items-center justify-between">
        <span className="text-sm font-medium text-foreground">Version {status.version}</span>
        <DismissChevron onClick={onDismiss} />
      </div>
      <p className="mt-3 text-sm text-muted-foreground">
        Nedladdningen är klar — starta om för att installera.
      </p>
      <button
        type="button"
        onClick={() => void confirmRestartInstall()}
        className="mt-4 w-full inline-flex items-center justify-center rounded-md
                   bg-primary text-primary-foreground text-sm font-medium h-9 px-3
                   hover:bg-primary/90 transition-colors focus-visible:outline-none
                   focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1"
      >
        Starta om för att uppdatera
      </button>
    </>
  );
}
