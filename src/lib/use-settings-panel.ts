// Spec 010 / T013 — panel visibility state machine + the gear-disabled
// derived predicate.
//
// 4 states, 6 transitions (data-model.md § PanelVisibility):
//   closed → opening   (gear click / Cmd+, while closed)
//   opening → open     (animation completes)
//   open → closing     (close-X / Esc / scrim / Cmd+, while open)
//   closing → closed   (animation completes)
//   opening → closing  (Esc mid-animation — reverse)
//   closing → opening  (repeated open intent during slide-out)
//
// The hook coalesces repeated open intents — at most one panel
// instance is ever open (CoalescedRepeatedOpenIntents invariant).
//
// The `gearIconEnabled` predicate is FALSE when either the spec 008
// first-run wizard is visible OR the spec 007 deferred-restart
// dialog is up. Mounted callers gate the gear click + the Cmd+,
// handler on this predicate.

import { useCallback, useEffect, useRef, useState } from 'react';

import type { PanelVisibility } from './settings-types';
import { useStatusStore } from './status-store';
import { useUpdateStore } from './update-store';

const OPEN_ANIMATION_MS = 220;
const CLOSE_ANIMATION_MS = 180;

export interface UseSettingsPanel {
  visibility: PanelVisibility;
  gearIconEnabled: boolean;
  openPanel: () => void;
  closePanel: () => void;
  togglePanel: () => void;
}

export function useSettingsPanel(): UseSettingsPanel {
  const [visibility, setVisibility] = useState<PanelVisibility>('closed');
  const timerRef = useRef<number | null>(null);

  // FR-005a — disabled while spec 008 wizard OR spec 007 restart
  // dialog is up. The wizard's visibility is derived from the status
  // store's user-visible state (begar_samtycke / laddar_ner_modell
  // are the wizard-up states); the restart dialog is the updater's
  // `ready_to_install` deferred state with consent pending.
  const wizardUp = useStatusStore((s) => {
    const v = s.status.visible;
    return v === 'begar_samtycke' || v === 'laddar_ner_modell';
  });
  const restartUp = useUpdateStore((s) => s.status.state === 'ready_to_install');
  const gearIconEnabled = !wizardUp && !restartUp;

  const clearTimer = useCallback(() => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const openPanel = useCallback(() => {
    if (!gearIconEnabled) return;
    setVisibility((current) => {
      if (current === 'open' || current === 'opening') return current;
      clearTimer();
      timerRef.current = window.setTimeout(() => {
        setVisibility((v) => (v === 'opening' ? 'open' : v));
        timerRef.current = null;
      }, OPEN_ANIMATION_MS);
      return 'opening';
    });
  }, [gearIconEnabled, clearTimer]);

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
    if (!gearIconEnabled) return;
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
  }, [gearIconEnabled, clearTimer]);

  useEffect(() => () => clearTimer(), [clearTimer]);

  return {
    visibility,
    gearIconEnabled,
    openPanel,
    closePanel,
    togglePanel,
  };
}
