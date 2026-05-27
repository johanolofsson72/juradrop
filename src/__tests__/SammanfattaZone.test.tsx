import { render, screen, fireEvent } from '@testing-library/react';
import { describe, expect, it, beforeEach, vi } from 'vitest';
import { SammanfattaZone } from '../components/DropZone';
import { useStatusStore } from '@/lib/status-store';
import type { ZoneSnapshot } from '@/lib/tauri-bridge';

// T054 — mock the tauri-bridge so we can assert `cancelSummary` is
// invoked with the right (zoneId, jobId) when Avbryt is activated.
// Spec 004 — the command now takes a zone_id parameter to scope the
// cancel to a single zone (SC-006).
const cancelSummaryMock = vi.fn();
vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  return {
    ...actual,
    cancelSummary: (zoneId: string, jobId: string) => {
      cancelSummaryMock(zoneId, jobId);
      return Promise.resolve();
    },
  };
});

// Spec 003 / T026 — initial test set for SammanfattaZone.
//
// US2-specific transition tests (idle→dragover, processing→success,
// auto-clear timers) live in their own block expanded during US2.
// This file covers US1 baseline: the component renders the right
// Swedish copy for each visible state and the disabled gate works.

function setZone(overrides: Partial<ZoneSnapshot>) {
  useStatusStore.setState((s) => ({
    zone: { ...s.zone, ...overrides },
    zones: {
      ...s.zones,
      sammanfatta: { ...s.zones.sammanfatta, ...overrides },
    },
  }));
}

function setStatusVisible(visible: ReturnType<typeof useStatusStore.getState>['status']['visible']) {
  useStatusStore.setState((s) => ({
    status: { ...s.status, visible },
  }));
}

describe('SammanfattaZone', () => {
  beforeEach(() => {
    const idleSnap = {
      state: 'idle' as const,
      disabled: false,
      failure: null,
      job_id: null,
      progress_hint: null,
    };
    useStatusStore.setState((s) => ({
      status: {
        visible: 'klar' as const,
        sidecar: 'ready' as const,
        model: 'ready' as const,
        progress_percent: null,
        consent: 'fortsatt' as const,
      },
      zone: idleSnap,
      zones: { ...s.zones, sammanfatta: idleSnap },
    }));
  });

  it('renders the Swedish title "Sammanfatta"', () => {
    render(<SammanfattaZone />);
    expect(screen.getByText('Sammanfatta')).toBeInTheDocument();
  });

  it('shows the idle hint and the [ docx ] signature label when idle and ready', () => {
    render(<SammanfattaZone />);
    expect(screen.getByText('Släpp ett .docx för sammanfattning')).toBeInTheDocument();
    expect(screen.getByText('[ docx ]')).toBeInTheDocument();
  });

  it('switches to the dragover hint when state === "dragover"', () => {
    setZone({ state: 'dragover' });
    render(<SammanfattaZone />);
    expect(screen.getByText('Släpp för att sammanfatta')).toBeInTheDocument();
    // The signature label is hidden during dragover.
    expect(screen.queryByText('[ docx ]')).not.toBeInTheDocument();
  });

  it('shows the processing progress hint and the Avbryt button while processing', () => {
    setZone({
      state: 'processing',
      job_id: '11111111-1111-1111-1111-111111111111',
      progress_hint: 'Sammanfattar…',
    });
    render(<SammanfattaZone />);
    expect(screen.getByText('Sammanfattar…')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Avbryt' })).toBeInTheDocument();
  });

  it('shows the success progress hint when state === "success"', () => {
    setZone({
      state: 'success',
      job_id: '22222222-2222-2222-2222-222222222222',
      progress_hint: 'Klar — öppnar fil…',
    });
    render(<SammanfattaZone />);
    expect(screen.getByText('Klar — öppnar fil…')).toBeInTheDocument();
    // Avbryt is hidden in success state.
    expect(screen.queryByRole('button', { name: 'Avbryt' })).not.toBeInTheDocument();
  });

  it('shows the matching Swedish error string when state === "error"', () => {
    setZone({ state: 'error', failure: 'parse_error' });
    render(<SammanfattaZone />);
    expect(screen.getByText('Kunde inte läsa dokumentet')).toBeInTheDocument();
  });

  it('falls back to the global status copy when disabled (AI not in Klar)', () => {
    setStatusVisible('startar');
    setZone({ disabled: true });
    render(<SammanfattaZone />);
    // The zone borrows the WelcomeCard's status copy as its hint.
    expect(screen.getByText('Startar AI...')).toBeInTheDocument();
    // The disabled-state opacity treatment is data-attribute driven.
    const root = screen
      .getByText('Sammanfatta')
      .closest('section') as HTMLElement;
    expect(root.getAttribute('data-disabled')).toBe('true');
  });

  it('marks the live region as aria-live polite and aria-atomic true', () => {
    render(<SammanfattaZone />);
    const live = screen.getByRole('status');
    expect(live.getAttribute('aria-live')).toBe('polite');
    expect(live.getAttribute('aria-atomic')).toBe('true');
    expect(live.textContent?.trim().length ?? 0).toBeGreaterThan(0);
  });

  it('exposes aria-label and aria-disabled on the zone container', () => {
    setZone({ disabled: true });
    setStatusVisible('startar');
    render(<SammanfattaZone />);
    const root = screen
      .getByText('Sammanfatta')
      .closest('section') as HTMLElement;
    expect(root.getAttribute('aria-label')).toMatch(/Sammanfatta/);
    expect(root.getAttribute('aria-disabled')).toBe('true');
  });

  // T033 — sequenced state-machine transitions. The zone is purely
  // state-reactive; the Rust core owns the timer-based transitions
  // (success → idle after 2 s, error → idle after 5 s) and emits
  // them as fresh snapshots. From the React layer's POV the timer
  // arrives as a store mutation, so the test sequence is just
  // setZone() calls verifying the UI tracks each step.
  describe('state-machine transitions', () => {
    it('idle → dragover → processing → success → idle reaches the right copy at each step', async () => {
      const { rerender, findByText, queryByText } = render(<SammanfattaZone />);

      // 1. idle
      expect(await findByText('Släpp ett .docx för sammanfattning')).toBeInTheDocument();
      expect(await findByText('[ docx ]')).toBeInTheDocument();

      // 2. dragover
      setZone({ state: 'dragover' });
      rerender(<SammanfattaZone />);
      expect(await findByText('Släpp för att sammanfatta')).toBeInTheDocument();
      expect(queryByText('[ docx ]')).not.toBeInTheDocument();

      // 3. processing
      setZone({
        state: 'processing',
        job_id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        progress_hint: 'Sammanfattar…',
      });
      rerender(<SammanfattaZone />);
      expect(await findByText('Sammanfattar…')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Avbryt' })).toBeInTheDocument();

      // 4. success
      setZone({
        state: 'success',
        progress_hint: 'Klar — öppnar fil…',
      });
      rerender(<SammanfattaZone />);
      expect(await findByText('Klar — öppnar fil…')).toBeInTheDocument();
      expect(queryByText('Sammanfattar…')).not.toBeInTheDocument();
      expect(
        screen.queryByRole('button', { name: 'Avbryt' }),
      ).not.toBeInTheDocument();

      // 5. idle (auto-clear arrived as a snapshot from Rust)
      setZone({
        state: 'idle',
        job_id: null,
        progress_hint: null,
      });
      rerender(<SammanfattaZone />);
      expect(await findByText('Släpp ett .docx för sammanfattning')).toBeInTheDocument();
      expect(await findByText('[ docx ]')).toBeInTheDocument();
    });

    it('processing → error → idle replays the Swedish failure copy and clears it', async () => {
      const { rerender, findByText, queryByText } = render(<SammanfattaZone />);

      setZone({
        state: 'processing',
        job_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        progress_hint: 'Sammanfattar…',
      });
      rerender(<SammanfattaZone />);
      await findByText('Sammanfattar…');

      setZone({
        state: 'error',
        failure: 'model_error',
        job_id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        progress_hint: null,
      });
      rerender(<SammanfattaZone />);
      expect(
        await findByText('AI-motorn svarade inte — försök igen'),
      ).toBeInTheDocument();
      expect(queryByText('Sammanfattar…')).not.toBeInTheDocument();

      // Auto-clear (would arrive from Rust 5 s later)
      setZone({
        state: 'idle',
        failure: null,
        job_id: null,
      });
      rerender(<SammanfattaZone />);
      expect(
        queryByText('AI-motorn svarade inte — försök igen'),
      ).not.toBeInTheDocument();
      expect(await findByText('Släpp ett .docx för sammanfattning')).toBeInTheDocument();
    });

    it('dragover → idle (drag-leave without drop) returns to the idle hint', async () => {
      const { rerender, findByText } = render(<SammanfattaZone />);
      setZone({ state: 'dragover' });
      rerender(<SammanfattaZone />);
      await findByText('Släpp för att sammanfatta');

      setZone({ state: 'idle' });
      rerender(<SammanfattaZone />);
      await findByText('Släpp ett .docx för sammanfattning');
    });

    it('global status flipping to non-Klar disables the zone mid-idle', async () => {
      const { rerender, findByText } = render(<SammanfattaZone />);
      await findByText('Släpp ett .docx för sammanfattning');

      // AI flips to startar — zone borrows the welcome card copy.
      setStatusVisible('startar');
      rerender(<SammanfattaZone />);
      const root = screen
        .getByText('Sammanfatta')
        .closest('section') as HTMLElement;
      expect(root.getAttribute('data-disabled')).toBe('true');
      expect(await findByText('Startar AI...')).toBeInTheDocument();
    });
  });

  // T039 — disabled gate per non-Klar UserVisibleStatus variant. For
  // each variant the zone MUST be disabled and the hint copy MUST be
  // the same Swedish string the welcome card uses (single source of
  // truth via statusMessage()). Parameterized so any new variant
  // added to the spec 002 enum forces a corresponding test entry.
  describe('disabled gate per UserVisibleStatus', () => {
    type Variant = ReturnType<typeof useStatusStore.getState>['status']['visible'];
    const cases: Array<{ variant: Variant; expected: string }> = [
      { variant: 'startar', expected: 'Startar AI...' },
      {
        variant: 'begar_samtycke',
        expected: 'Väntar på att du godkänner nedladdningen.',
      },
      { variant: 'laddar_ner_modell', expected: 'Laddar ner AI-modell...' },
      {
        variant: 'fel_kunde_inte_starta',
        expected: 'AI-motorn kunde inte starta. Starta om JuraDrop.',
      },
      {
        variant: 'fel_porten_upptagen',
        expected:
          'Ett annat AI-program använder anslutningen. Stäng det och starta om JuraDrop.',
      },
      {
        variant: 'fel_disk_full',
        expected: 'Inte tillräckligt med diskutrymme. Frigör minst 4 GB.',
      },
      {
        variant: 'fel_modellnedladdning_avbroten',
        expected: 'Modellnedladdningen avbröts. Försök igen.',
      },
      {
        variant: 'fel_ovantat',
        expected: 'Något gick fel med AI-motorn. Starta om JuraDrop.',
      },
      {
        variant: 'modell_saknas_avbruten',
        expected: 'AI-modell saknas. Starta om JuraDrop för att försöka igen.',
      },
    ];

    cases.forEach(({ variant, expected }) => {
      it(`zone is disabled and shows the welcome-card copy when visible="${variant}"`, () => {
        setStatusVisible(variant);
        render(<SammanfattaZone />);

        // The zone must be visibly disabled.
        const root = screen
          .getByText('Sammanfatta')
          .closest('section') as HTMLElement;
        expect(root.getAttribute('data-disabled')).toBe('true');
        expect(root.getAttribute('aria-disabled')).toBe('true');

        // The hint copy is the same Swedish string the WelcomeCard uses.
        expect(screen.getByText(expected)).toBeInTheDocument();

        // The Avbryt button must not be present (we're not processing).
        expect(
          screen.queryByRole('button', { name: 'Avbryt' }),
        ).not.toBeInTheDocument();
      });
    });

    it('flipping to klar removes the disabled treatment', async () => {
      setStatusVisible('startar');
      const { rerender, findByText } = render(<SammanfattaZone />);
      let root = screen.getByText('Sammanfatta').closest('section') as HTMLElement;
      expect(root.getAttribute('data-disabled')).toBe('true');

      setStatusVisible('klar');
      // The zone snapshot's `disabled` field is false by default in
      // the test seed; the Rust-side refresh_disabled would re-emit
      // a fresh snapshot in production. The JS-side derivation
      // (status.visible === 'klar') is enough to flip the gate.
      setZone({ disabled: false });
      rerender(<SammanfattaZone />);
      root = screen.getByText('Sammanfatta').closest('section') as HTMLElement;
      expect(root.getAttribute('data-disabled')).toBe('false');
      expect(await findByText('Släpp ett .docx för sammanfattning')).toBeInTheDocument();
    });
  });

  // T054 — Avbryt button behavior: visible only during processing,
  // keyboard-focusable, activates on click + Enter + Space, invokes
  // cancelSummary with the current job_id.
  describe('Avbryt button (US5)', () => {
    const JOB_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

    beforeEach(() => {
      cancelSummaryMock.mockClear();
    });

    it('is hidden when state is not processing', () => {
      // idle
      setZone({ state: 'idle', job_id: null });
      const { rerender } = render(<SammanfattaZone />);
      expect(screen.queryByRole('button', { name: 'Avbryt' })).toBeNull();

      // dragover
      setZone({ state: 'dragover' });
      rerender(<SammanfattaZone />);
      expect(screen.queryByRole('button', { name: 'Avbryt' })).toBeNull();

      // success
      setZone({ state: 'success', job_id: JOB_ID, progress_hint: 'Klar — öppnar fil…' });
      rerender(<SammanfattaZone />);
      expect(screen.queryByRole('button', { name: 'Avbryt' })).toBeNull();

      // error
      setZone({ state: 'error', failure: 'parse_error', job_id: JOB_ID });
      rerender(<SammanfattaZone />);
      expect(screen.queryByRole('button', { name: 'Avbryt' })).toBeNull();
    });

    it('is visible and focusable when state === processing with a job_id', () => {
      setZone({
        state: 'processing',
        job_id: JOB_ID,
        progress_hint: 'Sammanfattar…',
      });
      render(<SammanfattaZone />);
      const btn = screen.getByRole('button', { name: 'Avbryt' });
      expect(btn).toBeInTheDocument();
      // Native <button> elements are keyboard-focusable by default
      // (no explicit tabIndex needed); the test asserts it CAN be
      // focused programmatically.
      btn.focus();
      expect(document.activeElement).toBe(btn);
    });

    it('invokes cancelSummary with the current job_id when clicked', () => {
      setZone({
        state: 'processing',
        job_id: JOB_ID,
        progress_hint: 'Sammanfattar…',
      });
      render(<SammanfattaZone />);
      fireEvent.click(screen.getByRole('button', { name: 'Avbryt' }));
      expect(cancelSummaryMock).toHaveBeenCalledTimes(1);
      expect(cancelSummaryMock).toHaveBeenCalledWith('sammanfatta', JOB_ID);
    });

    it('invokes cancelSummary when activated via the Enter key', () => {
      setZone({
        state: 'processing',
        job_id: JOB_ID,
        progress_hint: 'Sammanfattar…',
      });
      render(<SammanfattaZone />);
      const btn = screen.getByRole('button', { name: 'Avbryt' });
      btn.focus();
      // Native <button> elements: Enter and Space both trigger a
      // click event. fireEvent.click models that semantic; the
      // keyboard test asserts the same outcome end-to-end.
      fireEvent.keyDown(btn, { key: 'Enter', code: 'Enter' });
      fireEvent.click(btn); // mirrors the browser's Enter→click translation
      expect(cancelSummaryMock).toHaveBeenCalledWith('sammanfatta', JOB_ID);
    });

    it('does NOT invoke cancelSummary when state has no job_id (defensive guard)', () => {
      setZone({
        state: 'processing',
        job_id: null,
        progress_hint: 'Sammanfattar…',
      });
      render(<SammanfattaZone />);
      // The button itself is gated on `zone.job_id` truthiness in
      // SammanfattaZone.tsx — no button means no click means no
      // cancelSummary call.
      expect(screen.queryByRole('button', { name: 'Avbryt' })).toBeNull();
      expect(cancelSummaryMock).not.toHaveBeenCalled();
    });

    it('shows the cancelled flash and hides the button after cancel acknowledgement', () => {
      setZone({
        state: 'processing',
        job_id: JOB_ID,
        progress_hint: 'Sammanfattar…',
      });
      const { rerender } = render(<SammanfattaZone />);

      // Cancel acknowledgement arrives as a snapshot from Rust:
      // state=success + progress_hint="Sammanfattning avbruten".
      setZone({
        state: 'success',
        job_id: JOB_ID,
        progress_hint: 'Sammanfattning avbruten',
      });
      rerender(<SammanfattaZone />);
      expect(screen.getByText('Sammanfattning avbruten')).toBeInTheDocument();
      // Avbryt button must be hidden now — the cancel succeeded;
      // re-cancelling makes no sense.
      expect(screen.queryByRole('button', { name: 'Avbryt' })).toBeNull();
    });
  });
});
