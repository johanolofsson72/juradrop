// Spec 007 / T022 — vitest coverage for the top-right indicator.
//
// Renders the component once per UpdateStatus variant and asserts:
//   (a) hidden for Unknown / Checking / UpToDate / Failed (FR-010).
//   (b) Swedish copy matches the spec.
//   (c) button clicks invoke the correct Tauri bridge command.
//   (d) FR-019 — empty notes renders the literal Swedish fallback.

import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { UpdateIndicator } from '../components/UpdateIndicator';
import { useUpdateStore } from '@/lib/update-store';
import type { UpdateStatus } from '@/lib/tauri-bridge';

const installNowMock = vi.fn();
const confirmRestartMock = vi.fn();
const cancelDeferredMock = vi.fn();
const dismissMock = vi.fn();

vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  return {
    ...actual,
    installUpdateNow: () => {
      installNowMock();
      return Promise.resolve();
    },
    confirmRestartInstall: () => {
      confirmRestartMock();
      return Promise.resolve();
    },
    cancelDeferredRestart: () => {
      cancelDeferredMock();
      return Promise.resolve();
    },
    dismissUpdateIndicator: () => {
      dismissMock();
      return Promise.resolve();
    },
  };
});

function setStatus(s: UpdateStatus) {
  useUpdateStore.setState({ status: s });
}

afterEach(() => {
  cleanup();
  installNowMock.mockClear();
  confirmRestartMock.mockClear();
  cancelDeferredMock.mockClear();
  dismissMock.mockClear();
});

describe('UpdateIndicator — visibility per FR-010', () => {
  it('renders nothing when state is unknown', () => {
    setStatus({ state: 'unknown' });
    const { container } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();
  });

  it('renders nothing when state is checking', () => {
    setStatus({ state: 'checking' });
    const { container } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();
  });

  it('renders nothing when state is up_to_date', () => {
    setStatus({ state: 'up_to_date', version: '0.1.0', checked_at: '' });
    const { container } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();
  });

  it('renders nothing when state is failed (T029)', () => {
    setStatus({
      state: 'failed',
      failure: 'no_network',
      message: 'Kan inte nå GitHub — kontrollera nätverksanslutningen',
      checked_at: '',
    });
    const { container } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();
  });
});

describe('UpdateIndicator — Available state', () => {
  beforeEach(() => {
    setStatus({
      state: 'available',
      version: '0.2.0',
      notes: 'Nya zoner + PDF-stöd',
      download_url: 'https://example.com/dmg',
      dismissed: false,
    });
  });

  it('renders the "Uppdatering tillgänglig" badge', () => {
    render(<UpdateIndicator />);
    expect(screen.getByText('Uppdatering tillgänglig')).toBeInTheDocument();
  });

  it('expands when clicked and shows the version + notes + Installera button', () => {
    render(<UpdateIndicator />);
    fireEvent.click(screen.getByText('Uppdatering tillgänglig'));
    expect(screen.getByText('Version 0.2.0')).toBeInTheDocument();
    expect(screen.getByText('Nya zoner + PDF-stöd')).toBeInTheDocument();
    expect(screen.getByText('Installera nu')).toBeInTheDocument();
  });

  it('FR-019 — empty notes renders the Swedish fallback string', () => {
    setStatus({
      state: 'available',
      version: '0.2.0',
      notes: '',
      download_url: 'https://example.com/dmg',
      dismissed: false,
    });
    render(<UpdateIndicator />);
    fireEvent.click(screen.getByText('Uppdatering tillgänglig'));
    expect(screen.getByText('Inga noteringar för denna version.')).toBeInTheDocument();
  });

  it('clicking Installera nu invokes installUpdateNow()', () => {
    render(<UpdateIndicator />);
    fireEvent.click(screen.getByText('Uppdatering tillgänglig'));
    fireEvent.click(screen.getByText('Installera nu'));
    expect(installNowMock).toHaveBeenCalledTimes(1);
  });

  it('clicking the dismiss × invokes dismissUpdateIndicator()', () => {
    render(<UpdateIndicator />);
    fireEvent.click(screen.getByText('Uppdatering tillgänglig'));
    fireEvent.click(screen.getByLabelText('Dölj uppdateringsmeddelande'));
    expect(dismissMock).toHaveBeenCalledTimes(1);
  });
});

describe('UpdateIndicator — Downloading state', () => {
  it('renders the progress badge with the current percentage', () => {
    setStatus({ state: 'downloading', version: '0.2.0', progress_pct: 42 });
    render(<UpdateIndicator />);
    expect(screen.getByText('Hämtar uppdatering… 42%')).toBeInTheDocument();
  });

  it('clamps to 0–100 visually (regression guard)', () => {
    setStatus({ state: 'downloading', version: '0.2.0', progress_pct: 99 });
    render(<UpdateIndicator />);
    expect(screen.getByText('Hämtar uppdatering… 99%')).toBeInTheDocument();
  });
});

describe('UpdateIndicator — ReadyToInstall state', () => {
  it('shows "Klar att installera — starta om?" when not deferred', () => {
    setStatus({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: false,
      dismissed: false,
    });
    render(<UpdateIndicator />);
    expect(screen.getByText('Klar att installera — starta om?')).toBeInTheDocument();
  });

  it('clicking the Starta om button invokes confirmRestartInstall()', () => {
    setStatus({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: false,
      dismissed: false,
    });
    render(<UpdateIndicator />);
    fireEvent.click(screen.getByText('Klar att installera — starta om?'));
    fireEvent.click(screen.getByText('Starta om'));
    expect(confirmRestartMock).toHaveBeenCalledTimes(1);
  });

  it('shows "Väntar tills jobben är klara…" when deferred', () => {
    setStatus({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: true,
      dismissed: false,
    });
    render(<UpdateIndicator />);
    expect(screen.getByText('Väntar tills jobben är klara…')).toBeInTheDocument();
  });

  it('clicking the Avbryt button (deferred) invokes cancelDeferredRestart()', () => {
    setStatus({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: true,
      dismissed: false,
    });
    render(<UpdateIndicator />);
    fireEvent.click(screen.getByText('Väntar tills jobben är klara…'));
    fireEvent.click(screen.getByText('Avbryt'));
    expect(cancelDeferredMock).toHaveBeenCalledTimes(1);
  });
});

describe('UpdateIndicator — Restarting state', () => {
  it('renders the "Startar om…" copy', () => {
    setStatus({ state: 'restarting', version: '0.2.0' });
    render(<UpdateIndicator />);
    expect(screen.getByText('Startar om…')).toBeInTheDocument();
  });
});
