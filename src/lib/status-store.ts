import { create } from 'zustand';
import {
  cancelConsent as bridgeCancel,
  giveConsent as bridgeGive,
  type AppStatus,
  type ZoneSnapshot,
} from './tauri-bridge';

const initialStatus: AppStatus = {
  visible: 'startar',
  sidecar: 'not_started',
  model: 'not_present',
  progress_percent: null,
  consent: 'not_asked',
};

// Spec 003 — initial zone snapshot before any Rust-side emit lands.
// `disabled: true` reflects the boot-time state — the zone is not
// drop-ready until the spec 002 sidecar reaches `Klar`.
const initialZone: ZoneSnapshot = {
  state: 'idle',
  disabled: true,
  failure: null,
  job_id: null,
  progress_hint: null,
};

interface StatusStore {
  status: AppStatus;
  zone: ZoneSnapshot;
  setStatus: (next: AppStatus) => void;
  setProgress: (percent: number) => void;
  setZone: (next: ZoneSnapshot) => void;
  giveConsent: () => Promise<void>;
  cancelConsent: () => Promise<void>;
}

export const useStatusStore = create<StatusStore>((set) => ({
  status: initialStatus,
  zone: initialZone,
  setStatus: (next) => set({ status: next }),
  setProgress: (percent) =>
    set((s) => ({ status: { ...s.status, progress_percent: percent } })),
  setZone: (next) => set({ zone: next }),
  giveConsent: async () => {
    await bridgeGive();
  },
  cancelConsent: async () => {
    await bridgeCancel();
  },
}));

export function statusMessage(status: AppStatus): string {
  switch (status.visible) {
    case 'startar':
      return 'Startar AI...';
    case 'klar':
      return 'AI är redo';
    case 'laddar_ner_modell': {
      const pct = status.progress_percent;
      if (pct === null || pct === undefined) {
        return 'Laddar ner AI-modell...';
      }
      return `Laddar ner AI-modell... ${pct}%`;
    }
    case 'begar_samtycke':
      return 'Väntar på att du godkänner nedladdningen.';
    case 'fel_kunde_inte_starta':
      return 'AI-motorn kunde inte starta. Starta om JuraDrop.';
    case 'fel_porten_upptagen':
      return 'Ett annat AI-program använder anslutningen. Stäng det och starta om JuraDrop.';
    case 'fel_disk_full':
      return 'Inte tillräckligt med diskutrymme. Frigör minst 4 GB.';
    case 'fel_modellnedladdning_avbroten':
      return 'Modellnedladdningen avbröts. Försök igen.';
    case 'fel_ovantat':
      return 'Något gick fel med AI-motorn. Starta om JuraDrop.';
    case 'modell_saknas_avbruten':
      return 'AI-modell saknas. Starta om JuraDrop för att försöka igen.';
  }
}
