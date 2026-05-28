// Spec 007 / T033 — dismiss → hide → state-transition → re-show.
//
// Asserts the full dismissal lifecycle through the Zustand store:
//   1. Available + dismissed=false → indicator visible.
//   2. Available + dismissed=true → indicator hidden (FR-018).
//   3. A subsequent transition into Available with dismissed=false
//      (the Rust lifecycle clears the flag on fresh arrival) makes
//      the indicator re-appear.
//   4. Same contract for ReadyToInstall.

import { render, screen, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { UpdateIndicator } from '../components/UpdateIndicator';
import { useUpdateStore } from '@/lib/update-store';
import type { UpdateStatus } from '@/lib/tauri-bridge';

function setStatus(s: UpdateStatus) {
  useUpdateStore.setState({ status: s });
}

afterEach(() => cleanup());

describe('UpdateIndicator — dismissal lifecycle (T033)', () => {
  it('Available + dismissed=false → badge visible', () => {
    setStatus({
      state: 'available',
      version: '0.2.0',
      notes: '',
      download_url: 'https://example/dmg',
      dismissed: false,
    });
    render(<UpdateIndicator />);
    expect(screen.getByText('Uppdatering tillgänglig')).toBeInTheDocument();
  });

  it('Available + dismissed=true → badge hidden', () => {
    setStatus({
      state: 'available',
      version: '0.2.0',
      notes: '',
      download_url: 'https://example/dmg',
      dismissed: true,
    });
    const { container } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();
  });

  it('fresh Available transition (dismissed=false again) re-shows the badge', () => {
    setStatus({
      state: 'available',
      version: '0.2.0',
      notes: '',
      download_url: 'https://example/dmg',
      dismissed: true,
    });
    const { container, rerender } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();

    // Simulate a fresh emit from Rust where the lifecycle reset cleared
    // the dismissed flag (e.g. the 4h tick found a newer version).
    setStatus({
      state: 'available',
      version: '0.3.0',
      notes: '',
      download_url: 'https://example/dmg',
      dismissed: false,
    });
    rerender(<UpdateIndicator />);
    expect(screen.getByText('Uppdatering tillgänglig')).toBeInTheDocument();
  });

  it('ReadyToInstall + dismissed=true → badge hidden', () => {
    setStatus({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: false,
      dismissed: true,
    });
    const { container } = render(<UpdateIndicator />);
    expect(container.firstChild).toBeNull();
  });

  it('ReadyToInstall + dismissed=false → badge visible', () => {
    setStatus({
      state: 'ready_to_install',
      version: '0.2.0',
      deferred: false,
      dismissed: false,
    });
    render(<UpdateIndicator />);
    expect(screen.getByText('Klar att installera — starta om?')).toBeInTheDocument();
  });
});
