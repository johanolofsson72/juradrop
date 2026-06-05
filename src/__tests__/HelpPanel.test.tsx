// Spec 013 / FR-019 + FR-020 — functional coverage for the HelpPanel.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. Panel renders all zones (ZONE_ORDER) with title + short + long.
//  2. Panel renders format badges (Generera = TXT/MD; others = the
//     six-format set — spec 043 purged the PAGES badge that outlived
//     spec 028's .pages removal, and THIS file's old assertion that
//     actively pinned the bug).
//  3. Esc closes the panel.
//  4. Close-X button closes the panel.
//  5. Scrim click closes the panel.
//  6. visibility=closed renders nothing.

import { fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async () => () => {}) }));

import { HelpPanel } from '@/components/HelpPanel';
import { ZONE_IDENTITIES, ZONE_ORDER } from '@/components/DropZone.identity';
import { ZONE_HELP_STRINGS } from '@/lib/help-strings';

afterEach(() => {
  /* RTL auto-cleanup via globals */
});

describe('HelpPanel', () => {
  it('renders every zone with title, short and long help', () => {
    render(<HelpPanel visibility="open" onClose={() => {}} />);
    for (const id of ZONE_ORDER) {
      expect(screen.getByText(ZONE_IDENTITIES[id].title)).toBeInTheDocument();
      expect(screen.getByText(ZONE_HELP_STRINGS[id].short)).toBeInTheDocument();
      expect(screen.getByText(ZONE_HELP_STRINGS[id].long)).toBeInTheDocument();
    }
  });

  it('renders one list item per zone', () => {
    render(<HelpPanel visibility="open" onClose={() => {}} />);
    const panel = screen.getByRole('dialog');
    expect(within(panel).getAllByRole('listitem')).toHaveLength(ZONE_ORDER.length);
  });

  it('shows only TXT/MD badges for Generera but the full set elsewhere', () => {
    render(<HelpPanel visibility="open" onClose={() => {}} />);
    const items = screen.getAllByRole('listitem');
    const generera = items[ZONE_ORDER.indexOf('generera')]!;
    expect(within(generera).getByText('TXT')).toBeInTheDocument();
    expect(within(generera).getByText('MD')).toBeInTheDocument();
    expect(within(generera).queryByText('DOCX')).toBeNull();

    const sammanfatta = items[ZONE_ORDER.indexOf('sammanfatta')]!;
    for (const fmt of ['DOCX', 'PDF', 'TXT', 'MD', 'RTF', 'ODT']) {
      expect(within(sammanfatta).getByText(fmt)).toBeInTheDocument();
    }
  });

  // Spec 043 FR-002 / SC-001 — the PAGES badge outlived spec 028's
  // .pages removal because the OLD version of this very test asserted
  // its presence. This pin makes a second silent survival impossible:
  // no badge anywhere in the panel may say PAGES.
  it('no format badge anywhere says PAGES (spec 028 purge, spec 043 pin)', () => {
    render(<HelpPanel visibility="open" onClose={() => {}} />);
    expect(screen.queryByText('PAGES')).toBeNull();
  });

  it('closes on Escape', () => {
    const onClose = vi.fn();
    render(<HelpPanel visibility="open" onClose={onClose} />);
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('closes when the close-X button is clicked', () => {
    const onClose = vi.fn();
    render(<HelpPanel visibility="open" onClose={onClose} />);
    fireEvent.click(screen.getByText('✕'));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('closes when the scrim is clicked', () => {
    const onClose = vi.fn();
    render(<HelpPanel visibility="open" onClose={onClose} />);
    // The scrim is the first close-labelled button (aria-label "Stäng").
    const closers = screen.getAllByLabelText('Stäng');
    fireEvent.click(closers[0]!);
    expect(onClose).toHaveBeenCalled();
  });

  it('renders nothing when closed', () => {
    const { container } = render(<HelpPanel visibility="closed" onClose={() => {}} />);
    expect(container.firstChild).toBeNull();
  });
});
