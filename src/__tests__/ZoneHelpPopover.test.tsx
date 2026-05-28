// Spec 013 / FR-018 — functional coverage for the per-zone help popover.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. (?) button renders with a Swedish aria-label.
//  2. Click opens the popover (role=tooltip) with the short help.
//  3. Re-click closes it.
//  4. Esc closes it.
//  5. Outside-click closes it.
//  6. Clicking the (?) stops propagation (does not bubble to the card).

import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { ZoneHelpPopover } from '@/components/ZoneHelpPopover';
import { ZONE_HELP_STRINGS } from '@/lib/help-strings';

describe('ZoneHelpPopover', () => {
  it('renders the (?) button with a Swedish aria-label', () => {
    render(<ZoneHelpPopover zoneId="anonymisera" />);
    expect(screen.getByLabelText('Hjälp om Anonymisera')).toBeInTheDocument();
  });

  it('opens a tooltip with the short help on click', () => {
    render(<ZoneHelpPopover zoneId="anonymisera" />);
    expect(screen.queryByRole('tooltip')).toBeNull();
    fireEvent.click(screen.getByLabelText('Hjälp om Anonymisera'));
    const tip = screen.getByRole('tooltip');
    expect(tip).toHaveTextContent(ZONE_HELP_STRINGS.anonymisera.short);
  });

  it('re-click closes the popover', () => {
    render(<ZoneHelpPopover zoneId="kallor" />);
    const btn = screen.getByLabelText('Hjälp om Källförteckning');
    fireEvent.click(btn);
    expect(screen.getByRole('tooltip')).toBeInTheDocument();
    fireEvent.click(btn);
    expect(screen.queryByRole('tooltip')).toBeNull();
  });

  it('Escape closes the popover', () => {
    render(<ZoneHelpPopover zoneId="generera" />);
    fireEvent.click(screen.getByLabelText('Hjälp om Generera juridisk text'));
    expect(screen.getByRole('tooltip')).toBeInTheDocument();
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.queryByRole('tooltip')).toBeNull();
  });

  it('outside-click closes the popover', () => {
    render(
      <div>
        <ZoneHelpPopover zoneId="forenkla" />
        <button type="button">utanför</button>
      </div>,
    );
    fireEvent.click(screen.getByLabelText('Hjälp om Förenkla'));
    expect(screen.getByRole('tooltip')).toBeInTheDocument();
    fireEvent.mouseDown(screen.getByText('utanför'));
    expect(screen.queryByRole('tooltip')).toBeNull();
  });

  it('stops click propagation so it does not reach the drop card', () => {
    const cardClick = vi.fn();
    render(
      <div onClick={cardClick}>
        <ZoneHelpPopover zoneId="punktlista" />
      </div>,
    );
    fireEvent.click(screen.getByLabelText('Hjälp om Punktlista'));
    expect(cardClick).not.toHaveBeenCalled();
  });
});
