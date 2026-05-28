// Spec 013 / FR-019 + FR-022 — chrome-bar help button.
//
// Sits LEFT of the spec 010 gear icon. Canonical chrome order, left to
// right: help (right-24), gear (right-14), update-indicator (right-3).
// Disabled (aria-disabled + reduced opacity + no click) while the spec
// 008 wizard OR the spec 007 restart dialog is up (FR-022). Mirrors
// GearIcon.tsx exactly so the two chrome buttons feel identical.

import { HelpCircle } from 'lucide-react';

import { HELP_CHROME_STRINGS } from '@/lib/help-strings';

interface Props {
  enabled: boolean;
  onClick: () => void;
}

export function HelpIcon({ enabled, onClick }: Props) {
  const handleClick = () => {
    if (!enabled) return;
    onClick();
  };
  return (
    <button
      type="button"
      aria-label={HELP_CHROME_STRINGS.help_icon_label}
      aria-disabled={!enabled}
      disabled={!enabled}
      onClick={handleClick}
      className={[
        'fixed right-24 top-3 z-40',
        'flex h-9 w-9 items-center justify-center rounded-md',
        'text-foreground/80 transition-colors',
        enabled
          ? 'hover:bg-muted hover:text-foreground'
          : 'cursor-not-allowed opacity-40',
      ].join(' ')}
      data-help-icon
    >
      <HelpCircle className="h-5 w-5" aria-hidden="true" />
    </button>
  );
}
