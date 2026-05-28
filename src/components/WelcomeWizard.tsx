// Spec 008 / T012 — welcome screen for the first-launch wizard.
//
// Centered card. Title + body paragraph + privacy line + download
// note + Fortsätt/Avbryt CTAs + sidecar-boot helper. Full-screen
// overlay layout owned by `Wizard.tsx`'s parent flex container.
//
// FR-002 — exact Swedish copy from the wizard-strings fixture.
// FR-003 — Fortsätt → giveConsent, Avbryt → cancelConsent.
// FR-011 — Escape key fires Avbryt.
// FR-017 — Fortsätt receives initial focus; Tab order Fortsätt → Avbryt.
// FR-002 clarification — Fortsätt disabled while sidecar.status !== 'ready';
//                        italic helper "Förbereder AI-motorn…" visible during boot.

import { useEffect, useRef } from 'react';

import { cancelConsent, giveConsent } from '@/lib/tauri-bridge';
import { useStatusStore } from '@/lib/status-store';
import { WIZARD_STRINGS } from '@/lib/wizard-strings';

export function WelcomeWizard() {
  const sidecar = useStatusStore((s) => s.status.sidecar);
  const fortsattRef = useRef<HTMLButtonElement | null>(null);
  const sidecarReady = sidecar === 'ready';

  // FR-017 — focus Fortsätt on mount so Enter activates immediately.
  useEffect(() => {
    if (sidecarReady && fortsattRef.current) {
      fortsattRef.current.focus();
    }
  }, [sidecarReady]);

  // FR-011 + FR-017 — Escape on welcome fires Avbryt.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        void cancelConsent();
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, []);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="wizard-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-background p-8"
    >
      <div
        className="w-full max-w-md rounded-xl border border-border bg-card p-8 shadow-sm
                   animate-in fade-in-0 slide-in-from-bottom-2 duration-300"
      >
        <h1
          id="wizard-title"
          className="text-3xl font-semibold tracking-tight text-foreground"
        >
          {WIZARD_STRINGS.welcome_title}
        </h1>

        <p
          aria-live="polite"
          className="mt-6 text-base leading-relaxed text-foreground"
        >
          {WIZARD_STRINGS.welcome_paragraph}
        </p>

        <p className="mt-4 text-sm font-medium text-foreground/90">
          {WIZARD_STRINGS.welcome_privacy_line}
        </p>

        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
          {WIZARD_STRINGS.welcome_download_note}
        </p>

        <div className="mt-8 flex flex-col gap-3">
          <button
            ref={fortsattRef}
            type="button"
            disabled={!sidecarReady}
            aria-keyshortcuts="Enter"
            onClick={() => void giveConsent()}
            className="inline-flex h-10 items-center justify-center rounded-md
                       bg-primary px-4 text-sm font-medium text-primary-foreground
                       hover:bg-primary/90 transition-colors
                       focus-visible:outline-none focus-visible:ring-2
                       focus-visible:ring-ring focus-visible:ring-offset-1
                       disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {WIZARD_STRINGS.welcome_cta_primary}
          </button>
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

        {!sidecarReady && (
          <p className="mt-4 text-xs italic text-muted-foreground">
            {WIZARD_STRINGS.welcome_sidecar_helper}
          </p>
        )}
      </div>
    </div>
  );
}
