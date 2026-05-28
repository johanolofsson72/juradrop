// Spec 013 FR-019/FR-022/FR-023 — HelpPanel visibility state machine.
//
// Cloned from use-settings-panel.ts (spec 010): same 4-state machine,
// same animation timings, same modal-gating predicate. The chrome-bar
// (?) is disabled while the spec 008 first-run wizard OR the spec 007
// deferred-restart dialog is up (FR-022). Mutual exclusion with the
// settings panel (FR-023) is wired by the caller in App.tsx.

import { useCallback, useEffect, useRef, useState } from 'react';

import type { PanelVisibility } from './settings-types';
import { useStatusStore } from './status-store';
import { useUpdateStore } from './update-store';

const OPEN_ANIMATION_MS = 220;
const CLOSE_ANIMATION_MS = 180;

export interface UseHelpPanel {
  visibility: PanelVisibility;
  helpIconEnabled: boolean;
  openPanel: () => void;
  closePanel: () => void;
  togglePanel: () => void;
}

export function useHelpPanel(): UseHelpPanel {
  const [visibility, setVisibility] = useState<PanelVisibility>('closed');
  const timerRef = useRef<number | null>(null);

  // FR-022 — disabled while spec 008 wizard OR spec 007 restart dialog
  // is up (same predicate as the gear icon's gearIconEnabled).
  const wizardUp = useStatusStore((s) => {
    const v = s.status.visible;
    return v === 'begar_samtycke' || v === 'laddar_ner_modell';
  });
  const restartUp = useUpdateStore((s) => s.status.state === 'ready_to_install');
  const helpIconEnabled = !wizardUp && !restartUp;

  const clearTimer = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const openPanel = useCallback(() => {
    if (!helpIconEnabled) return;
    setVisibility((current) => {
      if (current === 'open' || current === 'opening') return current;
      clearTimer();
      timerRef.current = window.setTimeout(() => {
        setVisibility((v) => (v === 'opening' ? 'open' : v));
        timerRef.current = null;
      }, OPEN_ANIMATION_MS);
      return 'opening';
    });
  }, [helpIconEnabled, clearTimer]);

  const closePanel = useCallback(() => {
    setVisibility((current) => {
      if (current === 'closed' || current === 'closing') return current;
      clearTimer();
      timerRef.current = window.setTimeout(() => {
        setVisibility((v) => (v === 'closing' ? 'closed' : v));
        timerRef.current = null;
      }, CLOSE_ANIMATION_MS);
      return 'closing';
    });
  }, [clearTimer]);

  const togglePanel = useCallback(() => {
    if (!helpIconEnabled) return;
    setVisibility((current) => {
      clearTimer();
      if (current === 'closed' || current === 'closing') {
        timerRef.current = window.setTimeout(() => {
          setVisibility((v) => (v === 'opening' ? 'open' : v));
          timerRef.current = null;
        }, OPEN_ANIMATION_MS);
        return 'opening';
      }
      timerRef.current = window.setTimeout(() => {
        setVisibility((v) => (v === 'closing' ? 'closed' : v));
        timerRef.current = null;
      }, CLOSE_ANIMATION_MS);
      return 'closing';
    });
  }, [helpIconEnabled, clearTimer]);

  useEffect(() => () => clearTimer(), [clearTimer]);

  return { visibility, helpIconEnabled, openPanel, closePanel, togglePanel };
}
