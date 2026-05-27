import { render, screen } from '@testing-library/react';
import { describe, expect, it, beforeEach } from 'vitest';
import { SammanfattaZone } from '../components/SammanfattaZone';
import { useStatusStore } from '@/lib/status-store';
import type { ZoneSnapshot } from '@/lib/tauri-bridge';

// Spec 003 / T026 — initial test set for SammanfattaZone.
//
// US2-specific transition tests (idle→dragover, processing→success,
// auto-clear timers) live in their own block expanded during US2.
// This file covers US1 baseline: the component renders the right
// Swedish copy for each visible state and the disabled gate works.

function setZone(overrides: Partial<ZoneSnapshot>) {
  useStatusStore.setState((s) => ({
    zone: { ...s.zone, ...overrides },
  }));
}

function setStatusVisible(visible: ReturnType<typeof useStatusStore.getState>['status']['visible']) {
  useStatusStore.setState((s) => ({
    status: { ...s.status, visible },
  }));
}

describe('SammanfattaZone', () => {
  beforeEach(() => {
    useStatusStore.setState({
      status: {
        visible: 'klar',
        sidecar: 'ready',
        model: 'ready',
        progress_percent: null,
        consent: 'fortsatt',
      },
      zone: {
        state: 'idle',
        disabled: false,
        failure: null,
        job_id: null,
        progress_hint: null,
      },
    });
  });

  it('renders the Swedish title "Sammanfatta"', () => {
    render(<SammanfattaZone />);
    expect(screen.getByText('Sammanfatta')).toBeInTheDocument();
  });

  it('shows the idle hint and the [ docx ] signature label when idle and ready', () => {
    render(<SammanfattaZone />);
    expect(screen.getByText('Släpp ett .docx-dokument här')).toBeInTheDocument();
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
      expect(await findByText('Släpp ett .docx-dokument här')).toBeInTheDocument();
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
      expect(await findByText('Släpp ett .docx-dokument här')).toBeInTheDocument();
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
      expect(await findByText('Släpp ett .docx-dokument här')).toBeInTheDocument();
    });

    it('dragover → idle (drag-leave without drop) returns to the idle hint', async () => {
      const { rerender, findByText } = render(<SammanfattaZone />);
      setZone({ state: 'dragover' });
      rerender(<SammanfattaZone />);
      await findByText('Släpp för att sammanfatta');

      setZone({ state: 'idle' });
      rerender(<SammanfattaZone />);
      await findByText('Släpp ett .docx-dokument här');
    });

    it('global status flipping to non-Klar disables the zone mid-idle', async () => {
      const { rerender, findByText } = render(<SammanfattaZone />);
      await findByText('Släpp ett .docx-dokument här');

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
});
