// Spec 008 / T013 — progress UI for the in-flight model download.
//
// Same centered-card visual language as WelcomeWizard. Renders the
// percent bar + Swedish-formatted byte counter + ETA + Cancel button.
// On error sub-states, swaps to a small error panel with "Försök igen".
//
// FR-004 — percent bar + byte counter + ETA + Cancel.
// FR-007 — "Väntar på nätverk…" label when bytes stale for ≥ 5 s.
// FR-009 — error sub-state with Försök igen.
// FR-010 — Cancel invokes cancel_model_pull.
// FR-017 — Escape fires Cancel.

import { useEffect } from 'react';

import {
  cancelConsent,
  cancelModelPull,
  giveConsent,
} from '@/lib/tauri-bridge';
import { useStatusStore } from '@/lib/status-store';
import {
  formatBytesSwedish,
  useProgressEstimate,
} from '@/lib/use-progress-estimate';
import { WIZARD_STRINGS } from '@/lib/wizard-strings';
import { statusMessage } from '@/lib/status-store';

export function FirstRunProgress() {
  const visible = useStatusStore((s) => s.status.visible);
  const estimate = useProgressEstimate();

  const isError =
    visible === 'fel_disk_full' ||
    visible === 'fel_modellnedladdning_avbroten' ||
    visible === 'fel_kunde_inte_starta' ||
    visible === 'fel_ovantat' ||
    visible === 'fel_porten_upptagen';

  // FR-017 — Escape on progress fires Cancel.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !isError) {
        e.preventDefault();
        void cancelModelPull();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [isError]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="wizard-progress-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-background p-8"
    >
      <div
        className="w-full max-w-md rounded-xl border border-border bg-card p-8 shadow-sm
                   animate-in fade-in-0 slide-in-from-bottom-2 duration-300"
      >
        {isError ? (
          <ErrorPanel visibleStatus={visible} />
        ) : (
          <DownloadingPanel
            label={estimate.label}
            pct={estimate.lastPct}
            bytes={estimate.lastByteCount}
            total={estimate.totalByteCount}
            etaRendered={estimate.etaRendered}
          />
        )}
      </div>
    </div>
  );
}

interface DownloadingPanelProps {
  label: 'downloading' | 'waiting';
  pct: number;
  bytes: number;
  total: number;
  etaRendered: string;
}

function DownloadingPanel({ label, pct, bytes, total, etaRendered }: DownloadingPanelProps) {
  const labelText =
    label === 'waiting'
      ? WIZARD_STRINGS.progress_label_waiting
      : WIZARD_STRINGS.progress_label_downloading;

  return (
    <>
      <h2
        id="wizard-progress-title"
        className="text-2xl font-semibold tracking-tight text-foreground"
      >
        {labelText}
      </h2>

      <div
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={pct}
        aria-label={labelText}
        className="mt-6 h-2 w-full overflow-hidden rounded-full bg-muted"
      >
        <div
          className="h-full bg-primary transition-all duration-500 ease-out"
          style={{ width: `${Math.max(0, Math.min(100, pct))}%` }}
        />
      </div>

      <div className="mt-3 flex items-center justify-between text-xs tabular-nums text-muted-foreground">
        <span>{formatBytesSwedish(bytes, total)}</span>
        <span aria-label="estimerad återstående tid">{etaRendered}</span>
      </div>

      <button
        type="button"
        onClick={() => void cancelModelPull()}
        className="mt-8 inline-flex h-10 w-full items-center justify-center rounded-md
                   border border-border bg-transparent px-4 text-sm font-medium
                   text-foreground hover:bg-muted/60 transition-colors
                   focus-visible:outline-none focus-visible:ring-2
                   focus-visible:ring-ring focus-visible:ring-offset-1"
      >
        {WIZARD_STRINGS.progress_cancel_button}
      </button>
    </>
  );
}

interface ErrorPanelProps {
  visibleStatus: ReturnType<typeof useStatusStore.getState>['status']['visible'];
}

function ErrorPanel({ visibleStatus }: ErrorPanelProps) {
  // Re-render the canonical Swedish copy from status-store. FR-009 +
  // existing spec 002 vocabulary owns the actual error strings.
  const message = statusMessage({
    visible: visibleStatus,
    sidecar: 'ready',
    model: 'download_failed',
    progress_percent: null,
    consent: 'fortsatt',
  });

  return (
    <>
      <h2
        id="wizard-progress-title"
        className="text-2xl font-semibold tracking-tight text-destructive"
      >
        {message}
      </h2>

      <p className="mt-3 text-sm leading-relaxed text-muted-foreground">
        Kontrollera nätverket eller diskutrymmet och försök igen.
      </p>

      <div className="mt-8 flex flex-col gap-3">
        <button
          type="button"
          onClick={() => void giveConsent()}
          className="inline-flex h-10 items-center justify-center rounded-md
                     bg-primary px-4 text-sm font-medium text-primary-foreground
                     hover:bg-primary/90 transition-colors
                     focus-visible:outline-none focus-visible:ring-2
                     focus-visible:ring-ring focus-visible:ring-offset-1"
        >
          {WIZARD_STRINGS.progress_error_retry}
        </button>
        {/* DRIFT-1 / TLA+ finding — `error → welcome` transition needs
            a UI affordance so the user isn't stuck retrying. Calling
            cancelConsent flips consent.choice = avbryt, which the
            wizard truth table maps to welcome on the next render. */}
        <button
          type="button"
          onClick={() => void cancelConsent()}
          className="inline-flex h-10 items-center justify-center rounded-md
                     border border-border bg-transparent px-4 text-sm font-medium
                     text-foreground hover:bg-muted/60 transition-colors
                     focus-visible:outline-none focus-visible:ring-2
                     focus-visible:ring-ring focus-visible:ring-offset-1"
        >
          {WIZARD_STRINGS.welcome_cta_secondary}
        </button>
      </div>
    </>
  );
}
