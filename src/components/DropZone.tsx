import { useEffect } from 'react';
import { Loader2 } from 'lucide-react';
import {
  cancelSummary,
  pickFileForZone,
  subscribeZone,
  type ZoneFailure,
  type ZoneId,
} from '@/lib/tauri-bridge';
import { useStatusStore, statusMessage } from '@/lib/status-store';
import { SWEDISH_ZONE_ERROR } from './DropZone.errors';
import { ZONE_IDENTITIES } from './DropZone.identity';
import { ZoneHelpPopover } from './ZoneHelpPopover';

// Spec 003 / T021 + spec 004 / T023 — per-zone drop zone component.
//
// Aesthetic: refined macOS editorial, consistent with WelcomeCard.
// The dashed border is the load-bearing graphic; state transitions
// are color + opacity, not movement (Principle VI).
//
// Per-zone identity (title, hint, processing verb, disclaimer) comes
// from ZONE_IDENTITIES[zoneId] — the TS mirror of the Rust ZoneId
// enum. The component is purely state-reactive: it subscribes to
// `juradrop://zone/<slug>` on mount and renders whatever the store
// has for its slot.

interface DropZoneProps {
  zoneId: ZoneId;
}

export function DropZone({ zoneId }: DropZoneProps) {
  const identity = ZONE_IDENTITIES[zoneId];

  const zoneSnap = useStatusStore((s) => s.zones[zoneId]);
  const status = useStatusStore((s) => s.status);
  const setZone = useStatusStore((s) => s.setZone);

  // Subscribe to this zone's snapshots. The Rust core emits per-zone
  // events on `juradrop://zone/<slug>`.
  useEffect(() => {
    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
    if (!inTauri) return;

    let unlisten: (() => void) | undefined;
    void subscribeZone(zoneId, (snap) => setZone(zoneId, snap)).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, [zoneId, setZone]);

  // Spec 026 — single readiness truth. The zone is disabled iff the GLOBAL
  // status is not Klar. We deliberately do NOT consult zoneSnap.disabled:
  // that per-zone flag rides a backend event that races the zone
  // subscription at startup (there is no initial per-zone pull, unlike the
  // global get_status on mount), so it gets stuck at its seed `true` even
  // when the AI is genuinely ready — which silently disabled every zone
  // behind an "AI är redo" header. The global status IS reliably synced
  // (get_status on mount + subscribeStatus), so it is the one trustworthy
  // gate (FR-004 / SC-002).
  const disabled = status.visible !== 'klar';

  const handleCancel = () => {
    if (zoneSnap.job_id) void cancelSummary(zoneId, zoneSnap.job_id);
  };

  // Spec 016 — open the native file picker for this zone (accessible
  // alternative to drag-drop). No-op while the zone is disabled.
  const handlePick = () => {
    if (disabled) return;
    void pickFileForZone(zoneId);
  };

  // (state, failure, disabled) → the Swedish phrase the live region reads.
  const announcement = ((): string => {
    if (disabled) return statusMessage(status);
    if (zoneSnap.state === 'error' && zoneSnap.failure) {
      return SWEDISH_ZONE_ERROR[zoneSnap.failure as ZoneFailure];
    }
    if (zoneSnap.progress_hint) return zoneSnap.progress_hint;
    if (zoneSnap.state === 'dragover') return `Släpp för att ${dragoverVerb(zoneId)}`;
    return identity.hintCopy;
  })();

  return (
    <section
      data-zone-id={zoneId}
      aria-label={`${identity.title} — ${identity.hintCopy}`}
      aria-disabled={disabled}
      data-state={zoneSnap.state}
      data-disabled={disabled}
      className={[
        'group relative flex w-full select-none flex-col items-center justify-center',
        'rounded-lg border-2 border-dashed border-border bg-transparent px-5 py-5',
        'transition-[border-color,background-color,opacity] duration-150 ease-out',
        'data-[state=dragover]:border-[#007aff] dark:data-[state=dragover]:border-[#0a84ff]',
        'data-[state=dragover]:bg-[#007aff]/5 dark:data-[state=dragover]:bg-[#0a84ff]/5',
        'data-[state=dragover]:animate-pulse',
        'data-[state=processing]:border-[#007aff] dark:data-[state=processing]:border-[#0a84ff]',
        'data-[state=processing]:bg-[#007aff]/[0.04] dark:data-[state=processing]:bg-[#0a84ff]/[0.04]',
        'data-[state=success]:border-solid data-[state=success]:border-emerald-500',
        'data-[state=success]:bg-emerald-500/[0.08]',
        'data-[state=error]:border-solid data-[state=error]:border-destructive',
        'data-[state=error]:bg-destructive/[0.08]',
        'data-[disabled=true]:cursor-not-allowed data-[disabled=true]:opacity-60',
      ].join(' ')}
      style={{ minHeight: '9.5rem' }}
    >
      {/* FR-018 — per-zone help popover, top-right corner. */}
      <ZoneHelpPopover zoneId={zoneId} />

      {(zoneSnap.state === 'idle' || disabled) && (
        <span
          aria-hidden="true"
          className="mb-2 font-mono text-[10px] uppercase tracking-[0.32em] text-muted-foreground"
        >
          [ docx ]
        </span>
      )}

      {zoneSnap.state === 'processing' && !disabled && (
        <div className="mb-2 flex items-center gap-2 text-muted-foreground">
          <Loader2
            aria-hidden="true"
            className="h-3.5 w-3.5 animate-spin text-[#007aff] dark:text-[#0a84ff]"
            strokeWidth={2.25}
          />
          <span className="font-mono text-[10px] uppercase tracking-[0.32em]">arbetar</span>
        </div>
      )}

      <h2 className="text-center text-lg font-semibold leading-tight tracking-tight text-foreground">
        {identity.title}
      </h2>

      <p
        role="status"
        aria-live="polite"
        aria-atomic="true"
        data-state={zoneSnap.state}
        className={[
          'mt-2 text-center text-xs transition-colors duration-150',
          'text-muted-foreground',
          'data-[state=success]:text-emerald-600 dark:data-[state=success]:text-emerald-400',
          'data-[state=error]:text-destructive',
        ].join(' ')}
      >
        {announcement}
      </p>

      {zoneSnap.state === 'processing' && zoneSnap.job_id && !disabled && (
        <button
          type="button"
          onClick={handleCancel}
          className={[
            'mt-3 cursor-pointer text-xs font-normal',
            'text-muted-foreground underline-offset-4',
            'hover:text-foreground hover:underline',
            'focus-visible:text-foreground focus-visible:underline focus-visible:outline-none',
            'transition-colors duration-150',
          ].join(' ')}
        >
          Avbryt
        </button>
      )}

      {/* Spec 016 — keyboard/accessible alternative to drag-drop. Sibling
          of the cancel link; opens the native picker. Hidden during
          processing (the cancel link owns that slot). */}
      {zoneSnap.state !== 'processing' && (
        <button
          type="button"
          onClick={handlePick}
          disabled={disabled}
          aria-label={`Välj fil för ${identity.title}`}
          data-zone-pick={zoneId}
          className={[
            'mt-3 text-xs font-normal underline-offset-4',
            'text-muted-foreground transition-colors duration-150',
            disabled
              ? 'cursor-not-allowed opacity-40'
              : 'cursor-pointer hover:text-foreground hover:underline focus-visible:text-foreground focus-visible:underline focus-visible:outline-none',
          ].join(' ')}
        >
          Välj fil
        </button>
      )}
    </section>
  );
}

/// Per-zone infinitive used in the dragover hint "Släpp för att <verb>".
function dragoverVerb(zoneId: ZoneId): string {
  switch (zoneId) {
    case 'sammanfatta':
      return 'sammanfatta';
    case 'tillengelska':
      return 'översätta till engelska';
    case 'tillsvenska':
      return 'översätta till svenska';
    case 'punktlista':
      return 'göra punktlista';
    case 'anonymisera':
      return 'anonymisera';
    case 'forenkla':
      return 'förenkla';
    // Spec 013 — three new zones.
    case 'kontakter':
      return 'plocka ut kontaktuppgifter';
    case 'generera':
      return 'generera juridisk text';
    case 'kallor':
      return 'göra källförteckning';
  }
}

// Spec 003 compat — the old SammanfattaZone name still resolves via
// this thin wrapper so existing tests pass without rewrites. Removed
// in T049 (Phase 7 cleanup).
export function SammanfattaZone() {
  return <DropZone zoneId="sammanfatta" />;
}
