// Spec 010 / T024 — top-right chrome gear button.
//
// Lives left of the spec 007 UpdateIndicator per Clarification Q5.
// Disabled (aria-disabled + reduced opacity + no click handler) while
// the spec 008 wizard OR the spec 007 restart dialog is up (FR-005a).
// The SF-style cog glyph is a lucide Settings icon.

import { Settings } from 'lucide-react';

import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';

interface Props {
  enabled: boolean;
  onClick: () => void;
}

export function GearIcon({ enabled, onClick }: Props) {
  const handleClick = () => {
    if (!enabled) return;
    onClick();
  };
  return (
    <button
      type="button"
      aria-label={SETTINGS_PANEL_STRINGS.gear_label}
      aria-disabled={!enabled}
      disabled={!enabled}
      onClick={handleClick}
      className={[
        'fixed right-14 top-3 z-40',
        'flex h-9 w-9 items-center justify-center rounded-md',
        'text-foreground/80 transition-colors',
        enabled
          ? 'hover:bg-muted hover:text-foreground'
          : 'cursor-not-allowed opacity-40',
      ].join(' ')}
      data-settings-gear
    >
      <Settings className="h-5 w-5" aria-hidden="true" />
    </button>
  );
}
