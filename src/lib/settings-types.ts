// Spec 010 / T005 — shared types between the Rust Tauri commands and
// the React layer. Mirrors `src-tauri/src/settings/{snapshot,tier_map}.rs`.

export type ModelTier = 'Snabb' | 'Smart' | 'Stor';

export const MODEL_TIERS: readonly ModelTier[] = ['Snabb', 'Smart', 'Stor'] as const;

export interface SettingsSnapshot {
  readonly schema_version: 1;
  readonly model_tier: ModelTier;
}

export interface TierPullState {
  readonly snabb_pulled: boolean;
  readonly smart_pulled: boolean;
  readonly stor_pulled: boolean;
}

export type PanelVisibility = 'closed' | 'opening' | 'open' | 'closing';

export type TierRowMode = 'radio_selectable' | 'download_button';

/** Map a ModelTier to its pull-state field name on TierPullState. */
export function isTierPulled(
  state: TierPullState | undefined | null,
  tier: ModelTier,
): boolean {
  if (!state) return false;
  switch (tier) {
    case 'Snabb':
      return state.snabb_pulled;
    case 'Smart':
      return state.smart_pulled;
    case 'Stor':
      return state.stor_pulled;
  }
}

export function tierRowMode(
  state: TierPullState | undefined | null,
  tier: ModelTier,
): TierRowMode {
  return isTierPulled(state, tier) ? 'radio_selectable' : 'download_button';
}
