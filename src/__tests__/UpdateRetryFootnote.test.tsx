// Spec 007 / T028 — vitest coverage for the bottom-right footnote.
//
// Asserts (a) every UpdateFailure variant's Swedish copy is rendered
// when the user expands the footnote in the Failed state, (b) the
// "Sök efter uppdateringar igen" button invokes checkForUpdatesNow(),
// (c) non-Failed states render only the timestamp without the popover.

import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { UpdateRetryFootnote } from '../components/UpdateRetryFootnote';
import { SWEDISH_UPDATE_FAILURE } from '../components/DropZone.update-errors';
import { useUpdateStore } from '@/lib/update-store';
import type { UpdateFailureVariant, UpdateStatus } from '@/lib/tauri-bridge';

const checkMock = vi.fn();
vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  return {
    ...actual,
    checkForUpdatesNow: () => {
      checkMock();
      return Promise.resolve();
    },
  };
});

function setStatus(s: UpdateStatus) {
  useUpdateStore.setState({ status: s });
}

afterEach(() => {
  cleanup();
  checkMock.mockClear();
});

describe('UpdateRetryFootnote — non-Failed states', () => {
  it('renders the "Inte kontrollerad än" placeholder when status is unknown', () => {
    setStatus({ state: 'unknown' });
    render(<UpdateRetryFootnote />);
    expect(screen.getByText('Inte kontrollerad än')).toBeInTheDocument();
  });

  it('renders the Senast-kollat timestamp when status is up_to_date', () => {
    setStatus({
      state: 'up_to_date',
      version: '0.1.0',
      checked_at: '2026-05-28T08:30:00Z',
    });
    render(<UpdateRetryFootnote />);
    expect(screen.getByText(/Senast sökt:/)).toBeInTheDocument();
  });

  it('does not render the failure popover when not in Failed state', () => {
    setStatus({
      state: 'up_to_date',
      version: '0.1.0',
      checked_at: '2026-05-28T08:30:00Z',
    });
    render(<UpdateRetryFootnote />);
    fireEvent.click(screen.getByText(/Senast sökt:/));
    expect(
      screen.queryByText('Sök efter uppdateringar igen'),
    ).not.toBeInTheDocument();
  });
});

describe('UpdateRetryFootnote — Failed state per variant', () => {
  const variants: UpdateFailureVariant[] = [
    'no_network',
    'manifest_malformed',
    'signature_invalid',
    'download_interrupted',
    'install_failed',
    'unsupported_platform',
  ];

  beforeEach(() => {
    cleanup();
  });

  it.each(variants)('renders the Swedish copy for %s when expanded', (variant) => {
    setStatus({
      state: 'failed',
      failure: variant,
      message: SWEDISH_UPDATE_FAILURE[variant],
      checked_at: '2026-05-28T08:30:00Z',
    });
    render(<UpdateRetryFootnote />);
    fireEvent.click(screen.getByText(/Senast sökt:/));
    expect(screen.getByText(SWEDISH_UPDATE_FAILURE[variant])).toBeInTheDocument();
  });

  it('clicking "Sök efter uppdateringar igen" invokes checkForUpdatesNow()', () => {
    setStatus({
      state: 'failed',
      failure: 'no_network',
      message: SWEDISH_UPDATE_FAILURE.no_network,
      checked_at: '2026-05-28T08:30:00Z',
    });
    render(<UpdateRetryFootnote />);
    fireEvent.click(screen.getByText(/Senast sökt:/));
    fireEvent.click(screen.getByText('Sök efter uppdateringar igen'));
    expect(checkMock).toHaveBeenCalledTimes(1);
  });
});
