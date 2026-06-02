// Spec 033 — canned backend state served by the mock Tauri bridge.
//
// Deterministic, per-test-overridable data. Shapes mirror the production
// types in src/lib/tauri-bridge.ts and src/lib/settings-types.ts so the
// unmodified frontend renders against believable values. No document
// content ever appears here (Principle I) — only status enums, ids, paths.

export type UserVisibleStatus =
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

export interface AppStatus {
  visible: UserVisibleStatus;
  sidecar: 'not_started' | 'starting' | 'ready' | 'crashed' | 'stopping' | 'stopped';
  model: 'not_present' | 'downloading' | 'ready' | 'download_failed';
  progress_percent: number | null;
  consent: 'not_asked' | 'fortsatt' | 'avbryt';
}

export interface SettingsSnapshot {
  schema_version: 1;
  model_tier: 'Snabb' | 'Smart' | 'Stor';
}

export interface TierPullState {
  snabb_pulled: boolean;
  smart_pulled: boolean;
  stor_pulled: boolean;
}

export interface DiagnosticsStatus {
  enabled: boolean;
  log_path: string | null;
}

export interface CannedState {
  status: AppStatus;
  settings: SettingsSnapshot;
  tierPull: TierPullState;
  /** TierDownloadEvent | null — null means "no download in flight". */
  tierDownload: unknown | null;
  diagnostics: DiagnosticsStatus;
  appVersion: string;
  /** plugin:dialog|open result — a path string, or null when cancelled. */
  pickerResult: string | null;
}

/** Default = the happy "ready" boot: wizard collapses, the 3×3 grid renders. */
export function defaultCanned(): CannedState {
  return {
    status: {
      visible: 'klar',
      sidecar: 'ready',
      model: 'ready',
      progress_percent: null,
      consent: 'fortsatt',
    },
    settings: { schema_version: 1, model_tier: 'Smart' },
    tierPull: { snabb_pulled: false, smart_pulled: true, stor_pulled: false },
    tierDownload: null,
    diagnostics: { enabled: false, log_path: null },
    appVersion: '0.1.0',
    pickerResult: null,
  };
}

/** Shallow-merge a per-test override onto the defaults (status merged deeply). */
export function withCanned(override: DeepPartial<CannedState>): CannedState {
  const base = defaultCanned();
  return {
    ...base,
    ...override,
    status: { ...base.status, ...(override.status ?? {}) },
    settings: { ...base.settings, ...(override.settings ?? {}) },
    tierPull: { ...base.tierPull, ...(override.tierPull ?? {}) },
    diagnostics: { ...base.diagnostics, ...(override.diagnostics ?? {}) },
  } as CannedState;
}

export type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends object ? Partial<T[P]> : T[P];
};
