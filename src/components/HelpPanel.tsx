// Spec 013 / FR-019 + FR-020 + FR-023 — slide-in help panel.
//
// Right-edge slide-in with scrim, mirroring SettingsPanel.tsx (spec 010)
// exactly: same container, scrim, header, Esc / scrim / close-X dismiss,
// 380px width, 200ms ease-out slide. Lists all 9 zones in canonical
// order with title, short helper, long explanation, and accepted-format
// badges (FR-020). Mutual exclusion with the settings panel is wired in
// App.tsx (FR-023).

import { useEffect } from 'react';

import { ZONE_IDENTITIES, ZONE_ORDER } from '@/components/DropZone.identity';
import {
  HELP_CHROME_STRINGS,
  INSTRUCTION_HELP,
  ZONE_HELP_STRINGS,
} from '@/lib/help-strings';
import type { PanelVisibility } from '@/lib/settings-types';
import type { ZoneId } from '@/lib/tauri-bridge';

interface Props {
  visibility: PanelVisibility;
  onClose: () => void;
}

// FR-020 — accepted-format badges. Generera takes only instruction files;
// every other zone takes the full spec-009 seven-format set.
const ALL_FORMATS = ['DOCX', 'PDF', 'TXT', 'MD', 'RTF', 'PAGES', 'ODT'];
const GENERERA_FORMATS = ['TXT', 'MD'];

function formatsFor(zone: ZoneId): readonly string[] {
  return zone === 'generera' ? GENERERA_FORMATS : ALL_FORMATS;
}

export function HelpPanel({ visibility, onClose }: Props) {
  // Esc closes from any focused element inside the panel (mirrors FR-003).
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
      aria-labelledby="help-panel-title"
      className="fixed inset-0 z-50"
      data-help-panel
      data-help-visibility={visibility}
    >
      {/* Scrim — click closes. */}
      <button
        type="button"
        aria-label={HELP_CHROME_STRINGS.close_label}
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
            id="help-panel-title"
            className="text-lg font-semibold text-foreground"
          >
            {HELP_CHROME_STRINGS.panel_title}
          </h1>
          <button
            type="button"
            aria-label={HELP_CHROME_STRINGS.close_label}
            onClick={onClose}
            className="text-foreground/70 hover:text-foreground"
          >
            ✕
          </button>
        </header>

        <div className="flex-1 overflow-y-auto px-6 py-5">
          {/* Spec 041 — chrome-level entry for the instruction field,
              above the zone list (it applies to every zone). */}
          <section
            data-instruction-help
            className="mb-6 flex flex-col gap-1.5 border-b border-border pb-6"
          >
            <h2 className="text-base font-semibold text-foreground">
              {INSTRUCTION_HELP.title}
            </h2>
            <p className="text-sm leading-relaxed text-foreground/80">
              {INSTRUCTION_HELP.body}
            </p>
          </section>
          <ul className="flex flex-col gap-6">
            {ZONE_ORDER.map((id) => (
              <li key={id} className="flex flex-col gap-1.5">
                <h2 className="text-base font-semibold text-foreground">
                  {ZONE_IDENTITIES[id].title}
                </h2>
                <p className="text-sm text-foreground/60">
                  {ZONE_HELP_STRINGS[id].short}
                </p>
                <p className="text-sm leading-relaxed text-foreground/80">
                  {ZONE_HELP_STRINGS[id].long}
                </p>
                <div className="mt-1 flex flex-wrap gap-1">
                  {formatsFor(id).map((fmt) => (
                    <span
                      key={fmt}
                      className="rounded border border-border px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-[0.16em] text-foreground/50"
                    >
                      {fmt}
                    </span>
                  ))}
                </div>
              </li>
            ))}
          </ul>
        </div>
      </aside>
    </div>
  );
}
