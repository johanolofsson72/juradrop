import { useEffect } from 'react';
import { Loader2 } from 'lucide-react';
import { cancelSummary, subscribeZone, type ZoneFailure } from '@/lib/tauri-bridge';
import { useStatusStore, statusMessage } from '@/lib/status-store';
import { SWEDISH_ZONE_ERROR } from './SammanfattaZone.errors';

// Spec 003 / T021 — Sammanfatta drop zone.
//
// Aesthetic: refined macOS editorial, consistent with WelcomeCard. The
// dashed border is the load-bearing graphic (per design-system/MASTER.md
// — "Resize Images macOS utility, dashed-border drop zones"); state
// transitions are expressed through color + opacity, not movement
// (Principle VI — no bouncing, no shake-on-error). One signature
// detail: a monospace `[ docx ]` label in the idle state that
// disappears once the zone is doing real work.
//
// Color tokens: shadcn semantic (`text-foreground`, `text-muted-foreground`,
// `text-destructive`, `border-border`) for the calm baseline; the macOS
// system blue (`#007aff` light / `#0a84ff` dark) is reused literally from
// MASTER.md's `--color-border-active` for the dragover / processing
// accent. Emerald 500 is the success color (the only non-shadcn color)
// because shadcn's default palette lacks a system-green equivalent.

export function SammanfattaZone() {
  const zone = useStatusStore((s) => s.zone);
  const status = useStatusStore((s) => s.status);
  const setZone = useStatusStore((s) => s.setZone);

  // Subscribe to the Rust-side zone snapshots. The store seeds an initial
  // `disabled: true` (boot state) until the first emit arrives.
  useEffect(() => {
    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
    if (!inTauri) return;

    let unlisten: (() => void) | undefined;
    void subscribeZone(setZone).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, [setZone]);

  // Reactive disabled gate — the zone is disabled whenever the spec 002
  // sidecar isn't in `Klar`. Mirrors the Rust SidecarStatusBecame* rules
  // and keeps the UI honest even before the first Rust-side emit lands.
  const disabled = zone.disabled || status.visible !== 'klar';

  const handleCancel = () => {
    if (zone.job_id) void cancelSummary(zone.job_id);
  };

  // Map (state, failure, disabled) → the Swedish phrase the status
  // announcer reads. Single source of truth for the zone's current text.
  const announcement = ((): string => {
    if (disabled) return statusMessage(status);
    if (zone.state === 'error' && zone.failure) {
      return SWEDISH_ZONE_ERROR[zone.failure as ZoneFailure];
    }
    if (zone.progress_hint) return zone.progress_hint;
    if (zone.state === 'dragover') return 'Släpp för att sammanfatta';
    return 'Släpp ett .docx-dokument här';
  })();

  return (
    <section
      aria-label="Sammanfatta — släpp ett .docx för att sammanfatta"
      aria-disabled={disabled}
      data-state={zone.state}
      data-disabled={disabled}
      className={[
        'group relative mx-auto flex w-full max-w-md select-none flex-col items-center justify-center',
        'rounded-lg border-2 border-dashed border-border bg-transparent px-12 py-16',
        'transition-[border-color,background-color,opacity] duration-150 ease-out',
        // Dragover — macOS system blue (light) / SF blue (dark)
        'data-[state=dragover]:border-[#007aff] dark:data-[state=dragover]:border-[#0a84ff]',
        'data-[state=dragover]:bg-[#007aff]/5 dark:data-[state=dragover]:bg-[#0a84ff]/5',
        'data-[state=dragover]:animate-pulse',
        // Processing — accent border, very faint tint, no movement
        'data-[state=processing]:border-[#007aff] dark:data-[state=processing]:border-[#0a84ff]',
        'data-[state=processing]:bg-[#007aff]/[0.04] dark:data-[state=processing]:bg-[#0a84ff]/[0.04]',
        // Success — emerald (no shadcn equivalent), solid border
        'data-[state=success]:border-solid data-[state=success]:border-emerald-500',
        'data-[state=success]:bg-emerald-500/[0.08]',
        // Error — destructive (shadcn token), solid border
        'data-[state=error]:border-solid data-[state=error]:border-destructive',
        'data-[state=error]:bg-destructive/[0.08]',
        // Disabled — dim everything, no drop affordance
        'data-[disabled=true]:cursor-not-allowed data-[disabled=true]:opacity-60',
      ].join(' ')}
      style={{ minHeight: '18rem' }}
    >
      {/* Signature detail — the monospace bracket label. Visible only when
          the zone is idle/disabled, replaced by the spinner row when
          something is happening. The bracket-and-spacing pattern echoes
          a CLI prompt, telegraphing the format constraint without
          shouting. */}
      {(zone.state === 'idle' || disabled) && (
        <span
          aria-hidden="true"
          className="mb-6 font-mono text-[11px] uppercase tracking-[0.32em] text-muted-foreground"
        >
          [ docx ]
        </span>
      )}

      {/* Processing row — spinner + small label, side by side, restrained. */}
      {zone.state === 'processing' && !disabled && (
        <div className="mb-6 flex items-center gap-3 text-muted-foreground">
          <Loader2
            aria-hidden="true"
            className="h-4 w-4 animate-spin text-[#007aff] dark:text-[#0a84ff]"
            strokeWidth={2.25}
          />
          <span className="font-mono text-[11px] uppercase tracking-[0.32em]">arbetar</span>
        </div>
      )}

      {/* Title — matches WelcomeCard's typography rhythm exactly
          (text-2xl, font-semibold, tracking-tight) so the two surfaces
          read as peer-level elements. */}
      <h2 className="text-2xl font-semibold tracking-tight text-foreground">Sammanfatta</h2>

      {/* The live region — the load-bearing accessibility surface.
          aria-live="polite" + aria-atomic="true" makes screen readers
          re-read the full sentence on each state change instead of just
          the changed character. */}
      <p
        role="status"
        aria-live="polite"
        aria-atomic="true"
        data-state={zone.state}
        className={[
          'mt-3 text-center text-sm transition-colors duration-150',
          'text-muted-foreground',
          'data-[state=success]:text-emerald-600 dark:data-[state=success]:text-emerald-400',
          'data-[state=error]:text-destructive',
        ].join(' ')}
      >
        {announcement}
      </p>

      {/* Avbryt — a quiet underline link, NOT a heavy button. Visible
          only during processing. Keyboard-focusable; underlines on
          hover AND focus. Single Swedish word, matches the restrained
          tone of the rest of the zone. */}
      {zone.state === 'processing' && zone.job_id && !disabled && (
        <button
          type="button"
          onClick={handleCancel}
          className={[
            'mt-6 cursor-pointer text-sm font-normal',
            'text-muted-foreground underline-offset-4',
            'hover:text-foreground hover:underline',
            'focus-visible:text-foreground focus-visible:underline focus-visible:outline-none',
            'transition-colors duration-150',
          ].join(' ')}
        >
          Avbryt
        </button>
      )}
    </section>
  );
}
