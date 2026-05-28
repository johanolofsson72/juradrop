// Spec 013 / FR-019 + FR-020 — functional coverage for the HelpPanel.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. Panel renders all 9 zones with title + short + long.
//  2. Panel renders format badges (Generera = TXT/MD; others = 7).
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
  it('renders all 9 zones with title, short and long help', () => {
    render(<HelpPanel visibility="open" onClose={() => {}} />);
    for (const id of ZONE_ORDER) {
      expect(screen.getByText(ZONE_IDENTITIES[id].title)).toBeInTheDocument();
      expect(screen.getByText(ZONE_HELP_STRINGS[id].short)).toBeInTheDocument();
      expect(screen.getByText(ZONE_HELP_STRINGS[id].long)).toBeInTheDocument();
    }
  });

  it('renders 9 zone list items', () => {
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
    expect(within(sammanfatta).getByText('DOCX')).toBeInTheDocument();
    expect(within(sammanfatta).getByText('PAGES')).toBeInTheDocument();
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
