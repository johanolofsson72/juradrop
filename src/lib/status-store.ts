import { create } from 'zustand';
import {
  cancelConsent as bridgeCancel,
  giveConsent as bridgeGive,
  type AppStatus,
} from './tauri-bridge';

const initialStatus: AppStatus = {
  visible: 'startar',
  sidecar: 'not_started',
  model: 'not_present',
  progress_percent: null,
  consent: 'not_asked',
};

interface StatusStore {
  status: AppStatus;
  setStatus: (next: AppStatus) => void;
  setProgress: (percent: number) => void;
  giveConsent: () => Promise<void>;
  cancelConsent: () => Promise<void>;
}

export const useStatusStore = create<StatusStore>((set) => ({
  status: initialStatus,
  setStatus: (next) => set({ status: next }),
  setProgress: (percent) =>
    set((s) => ({ status: { ...s.status, progress_percent: percent } })),
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
      return 'AI redo';
    case 'laddar_ner_modell': {
      const pct = status.progress_percent;
      if (pct === null || pct === undefined) {
        return 'Laddar ner AI-modell...';
      }
      return `Laddar ner AI-modell... ${pct}%`;
    }
    case 'begar_samtycke':
      return 'Väntar på ditt godkännande för nedladdning.';
    case 'fel_kunde_inte_starta':
      return 'AI-motorn kunde inte starta. Starta om JuraDrop.';
    case 'fel_porten_upptagen':
      return 'Porten är upptagen. Stäng andra AI-program och starta om.';
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
