// Spec 010 / T020 — slide-in panel container.
//
// Right-edge slide-in with scrim. Esc / scrim click / close-X
// dismiss (FR-003). Mounted while `visibility !== 'closed'`; CSS
// drives the slide animation via tailwindcss-animate utilities.

import { useEffect } from 'react';

import { AboutSection } from '@/components/SettingsPanelAbout';
import { AppearanceSection } from '@/components/SettingsPanelAppearance';
import { DiagnosticsSection } from '@/components/SettingsPanelDiagnostics';
import { ModelTierSection } from '@/components/SettingsPanelModelTier';
import { SETTINGS_PANEL_STRINGS } from '@/lib/settings-panel-strings';
import type { PanelVisibility } from '@/lib/settings-types';

interface Props {
  visibility: PanelVisibility;
  onClose: () => void;
}

export function SettingsPanel({ visibility, onClose }: Props) {
  // FR-003 — Esc closes from any focused element inside the panel.
  useEffect(() => {
    if (visibility === 'closed') return;
    const handler = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [visibility, onClose]);

  if (visibility === 'closed') return null;

  const visible = visibility === 'open' || visibility === 'opening';

  return (
    <div
      role="dialog"
      aria-modal="false"
      aria-labelledby="settings-panel-title"
      className="fixed inset-0 z-50"
      data-settings-panel
      data-settings-visibility={visibility}
    >
      {/* Scrim — click closes. */}
      <button
        type="button"
        aria-label={SETTINGS_PANEL_STRINGS.close_label}
        onClick={onClose}
        className={[
          'absolute inset-0 bg-black/30 transition-opacity duration-200',
          visible ? 'opacity-100' : 'opacity-0',
        ].join(' ')}
        tabIndex={-1}
      />
      {/* Panel — slide-in from right. */}
      <aside
        className={[
          'absolute right-0 top-0 flex h-full w-[380px] flex-col',
          'border-l border-border bg-background shadow-xl',
          'transition-transform duration-200 ease-out',
          visible ? 'translate-x-0' : 'translate-x-full',
        ].join(' ')}
      >
        <header className="flex items-center justify-between border-b border-border px-6 py-4">
          <h1
            id="settings-panel-title"
            className="text-lg font-semibold text-foreground"
          >
            {SETTINGS_PANEL_STRINGS.panel_title}
          </h1>
          <button
            type="button"
            aria-label={SETTINGS_PANEL_STRINGS.close_label}
            onClick={onClose}
            className="text-foreground/70 hover:text-foreground"
          >
            ✕
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-6 py-5">
          <ModelTierSection />
          <AppearanceSection />
          <DiagnosticsSection />
          <AboutSection />
        </div>
      </aside>
    </div>
  );
}
