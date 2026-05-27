import { create } from 'zustand';
import {
  cancelConsent as bridgeCancel,
  giveConsent as bridgeGive,
  type AppStatus,
  type ZoneId,
  type ZoneSnapshot,
} from './tauri-bridge';

const initialStatus: AppStatus = {
  visible: 'startar',
  sidecar: 'not_started',
  model: 'not_present',
  progress_percent: null,
  consent: 'not_asked',
};

// Spec 004 — initial per-zone snapshot. `disabled: true` reflects
// the boot-time state — every zone is disabled until the spec 002
// sidecar reaches `Klar`.
const seedSnapshot = (): ZoneSnapshot => ({
  state: 'idle',
  disabled: true,
  failure: null,
  job_id: null,
  progress_hint: null,
});

const initialZones: Record<ZoneId, ZoneSnapshot> = {
  sammanfatta: seedSnapshot(),
  tillengelska: seedSnapshot(),
  tillsvenska: seedSnapshot(),
  punktlista: seedSnapshot(),
  anonymisera: seedSnapshot(),
  forenkla: seedSnapshot(),
};

interface StatusStore {
  status: AppStatus;
  zones: Record<ZoneId, ZoneSnapshot>;
  // Spec 003 compat — `zone` keeps the Sammanfatta snapshot for the
  // old test suite. Removed in T049 (Phase 7 cleanup) once spec 003
  // tests are deleted/migrated.
  zone: ZoneSnapshot;
  setStatus: (next: AppStatus) => void;
  setProgress: (percent: number) => void;
  setZone: (id: ZoneId, next: ZoneSnapshot) => void;
  giveConsent: () => Promise<void>;
  cancelConsent: () => Promise<void>;
}

export const useStatusStore = create<StatusStore>((set) => ({
  status: initialStatus,
  zones: initialZones,
  zone: initialZones.sammanfatta,
  setStatus: (next) => set({ status: next }),
  setProgress: (percent) =>
    set((s) => ({ status: { ...s.status, progress_percent: percent } })),
  setZone: (id, next) =>
    set((s) => ({
      zones: { ...s.zones, [id]: next },
      // Spec 003 compat — mirror the sammanfatta slot into the
      // legacy `zone` field so the old tests keep working.
      zone: id === 'sammanfatta' ? next : s.zone,
    })),
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
