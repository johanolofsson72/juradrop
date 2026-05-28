// Spec 008 / T006 + T011 — pure derivation of the wizard phase from
// the existing AppStatus snapshot, plus the minimum-visible-time hold.
//
// useWizardState is a one-liner pure function of useStatusStore. No
// useState, no useEffect, no subscription — every render recomputes
// the phase from the current AppStatus. Subsequent launches with
// (consent=fortsatt, model=ready) collapse to 'hidden' immediately,
// matching SC-002.

import { useEffect, useRef, useState } from 'react';

import { useStatusStore } from './status-store';

export type WizardPhase = 'welcome' | 'progress' | 'error' | 'hidden';

/**
 * R-001 truth table — derives the wizard phase from (consent, model,
 * visible). The sidecar status is used in `WelcomeWizard` itself to
 * gate the Fortsätt button, not in this derivation.
 */
export function deriveWizardPhase(args: {
  consent: 'not_asked' | 'fortsatt' | 'avbryt';
  model: 'not_present' | 'downloading' | 'ready' | 'download_failed';
  visible:
    | 'startar'
    | 'klar'
    | 'laddar_ner_modell'
    | 'begar_samtycke'
    | 'fel_kunde_inte_starta'
    | 'fel_porten_upptagen'
    | 'fel_disk_full'
    | 'fel_modellnedladdning_avbroten'
    | 'fel_ovantat'
    | 'modell_saknas_avbruten';
}): WizardPhase {
  const { consent, model, visible } = args;

  // FR-001 — fresh install OR previous Avbryt → welcome.
  if (consent === 'not_asked' || consent === 'avbryt') {
    return 'welcome';
  }

  // FR-012 — model missing or previously aborted → welcome re-shows.
  if (model === 'not_present' || visible === 'modell_saknas_avbruten') {
    return 'welcome';
  }

  // FR-009 — terminal failure surfaces in the error phase. This
  // includes both download failures and disk-full conditions; the
  // progress UI's error sub-state renders the right Swedish copy
  // per `visible`.
  if (
    model === 'download_failed' ||
    visible === 'fel_disk_full' ||
    visible === 'fel_modellnedladdning_avbroten' ||
    visible === 'fel_kunde_inte_starta' ||
    visible === 'fel_ovantat' ||
    visible === 'fel_porten_upptagen'
  ) {
    return 'error';
  }

  // FR-005 — model is downloading → progress phase.
  if (model === 'downloading' || visible === 'laddar_ner_modell') {
    return 'progress';
  }

  // FR-006 — model is ready + consent is fortsatt → wizard collapses.
  if (model === 'ready') {
    return 'hidden';
  }

  // Defensive fallback — stay on welcome rather than render zones with
  // an inconsistent state.
  return 'welcome';
}

/** Hook wrapper — reads the live status snapshot. */
export function useWizardState(): WizardPhase {
  const status = useStatusStore((s) => s.status);
  return deriveWizardPhase({
    consent: status.consent,
    model: status.model,
    visible: status.visible,
  });
}

/**
 * FR-019 — hold the previous phase for at least `minMs` after a change.
 * Used in `Wizard.tsx` to prevent the welcome screen from flashing
 * for less than 300 ms when the model pull completes instantly (e.g.
 * cached install or a unit-test fake clock).
 */
export function useMinVisibleHold(actual: WizardPhase, minMs = 300): WizardPhase {
  const [held, setHeld] = useState(actual);
  const heldRef = useRef(actual);
  const mountedAt = useRef(Date.now());

  useEffect(() => {
    if (actual === heldRef.current) return;
    const elapsed = Date.now() - mountedAt.current;
    if (elapsed >= minMs) {
      heldRef.current = actual;
      mountedAt.current = Date.now();
      setHeld(actual);
      return;
    }
    const timer = setTimeout(() => {
      heldRef.current = actual;
      mountedAt.current = Date.now();
      setHeld(actual);
    }, minMs - elapsed);
    return () => clearTimeout(timer);
  }, [actual, minMs]);

  return held;
}
