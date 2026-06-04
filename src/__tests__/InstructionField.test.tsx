// Spec 041 T009 — InstructionField functional coverage.
//
// ===== FUNCTIONAL COVERAGE INVENTORY (component scope) =====
// 1. Renders with accessible Swedish label + placeholder
// 2. Counter appears with content and tracks length live
// 3. Input refuses text past 500 chars (store clamp)
// 4. Clear (×) empties the field
// 5. Field enabled regardless of zone/sidecar state (FR-015)
// 6. Counter + clear hidden when empty (no idle noise)
// ===========================================================

import { beforeEach, describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { InstructionField } from '../components/InstructionField';
import { useInstructionStore } from '@/lib/instruction-store';
import { useStatusStore } from '@/lib/status-store';

beforeEach(() => {
  useInstructionStore.getState().clear();
});

const input = () =>
  screen.getByLabelText('Egna instruktioner för nästa dokument') as HTMLInputElement;

describe('InstructionField', () => {
  it('renders an accessible Swedish label and placeholder', () => {
    render(<InstructionField />);
    const el = input();
    expect(el).toBeInTheDocument();
    expect(el.placeholder).toContain('nästa dokument');
    expect(el.placeholder).toContain('valfritt');
  });

  it('typing updates the store and the live counter', () => {
    render(<InstructionField />);
    fireEvent.change(input(), { target: { value: 'behåll citaten på svenska' } });
    expect(useInstructionStore.getState().instruction).toBe('behåll citaten på svenska');
    const counter = document.querySelector('[data-instruction-counter]');
    expect(counter?.textContent).toBe('25/500');
  });

  it('refuses text past 500 chars (maxLength + store clamp)', () => {
    render(<InstructionField />);
    // Programmatic change bypasses the DOM maxLength — the store clamp
    // is the second line of defense the test pins.
    fireEvent.change(input(), { target: { value: 'x'.repeat(600) } });
    expect(useInstructionStore.getState().instruction).toHaveLength(500);
    expect(input().maxLength).toBe(500);
    const counter = document.querySelector('[data-instruction-counter]');
    expect(counter?.textContent).toBe('500/500');
  });

  it('clear (×) empties the field', () => {
    render(<InstructionField />);
    fireEvent.change(input(), { target: { value: 'hemlig strategi' } });
    fireEvent.click(screen.getByLabelText('Rensa instruktionen'));
    expect(useInstructionStore.getState().instruction).toBe('');
    expect(input().value).toBe('');
  });

  it('counter and clear are hidden when the field is empty', () => {
    render(<InstructionField />);
    expect(document.querySelector('[data-instruction-counter]')).toBeNull();
    expect(screen.queryByLabelText('Rensa instruktionen')).toBeNull();
  });

  it('stays enabled regardless of app/zone status (FR-015)', () => {
    // Simulate the most locked-down app state — zones disabled, sidecar
    // not started. The field must not consult it at all.
    useStatusStore.setState((s) => ({
      status: { ...s.status, visible: 'startar', sidecar: 'not_started' },
    }));
    render(<InstructionField />);
    expect(input().disabled).toBe(false);
    fireEvent.change(input(), { target: { value: 'fungerar ändå' } });
    expect(useInstructionStore.getState().instruction).toBe('fungerar ändå');
  });
});
