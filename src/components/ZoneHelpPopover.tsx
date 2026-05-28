// Spec 013 / FR-018 — per-zone help popover.
//
// A small (?) button at the top-right corner of a DropZone card. Click
// toggles a popover (CSS-absolute, no portal) showing the zone's short
// Swedish help string. Dismiss: re-click, Esc, or click outside.
// role="tooltip" on the popover; the button carries a Swedish aria-label.
//
// The button stops click propagation so it can never be mistaken for
// part of the drop surface.

import { useEffect, useRef, useState } from 'react';
import { HelpCircle } from 'lucide-react';

import { HELP_CHROME_STRINGS, ZONE_HELP_STRINGS } from '@/lib/help-strings';
import { ZONE_IDENTITIES } from '@/components/DropZone.identity';
import type { ZoneId } from '@/lib/tauri-bridge';

interface Props {
  zoneId: ZoneId;
}

export function ZoneHelpPopover({ zoneId }: Props) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        setOpen(false);
      }
    };
    const onPointer = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onPointer);
    return () => {
      window.removeEventListener('keydown', onKey);
      document.removeEventListener('mousedown', onPointer);
    };
  }, [open]);

  const title = ZONE_IDENTITIES[zoneId].title;

  return (
    <div ref={rootRef} className="absolute right-2 top-2 z-10">
      <button
        type="button"
        aria-label={HELP_CHROME_STRINGS.zone_help_icon_label(title)}
        aria-expanded={open}
        onClick={(e) => {
          e.stopPropagation();
          setOpen((v) => !v);
        }}
        className={[
          'flex h-6 w-6 items-center justify-center rounded-full',
          'text-muted-foreground/70 transition-colors',
          'hover:bg-muted hover:text-foreground',
          'focus-visible:text-foreground focus-visible:outline-none',
        ].join(' ')}
        data-zone-help-icon={zoneId}
      >
        <HelpCircle className="h-4 w-4" aria-hidden="true" />
      </button>

      {open && (
        <div
          role="tooltip"
          className={[
            'absolute right-0 top-8 w-56 rounded-md',
            'border border-border bg-background p-3 shadow-lg',
            'text-left text-xs leading-relaxed text-foreground/80',
          ].join(' ')}
          data-zone-help-popover={zoneId}
        >
          {ZONE_HELP_STRINGS[zoneId].short}
        </div>
      )}
    </div>
  );
}
