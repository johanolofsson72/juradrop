// Spec 008 / T019 — vitest for the FirstRunProgress component.

import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { FirstRunProgress } from '../components/FirstRunProgress';
import { useStatusStore } from '@/lib/status-store';
import { WIZARD_STRINGS } from '@/lib/wizard-strings';
import type { UserVisibleStatus } from '@/lib/tauri-bridge';

const cancelModelPullMock = vi.fn();
const giveConsentMock = vi.fn();

vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  return {
    ...actual,
    cancelModelPull: () => {
      cancelModelPullMock();
      return Promise.resolve();
    },
    giveConsent: () => {
      giveConsentMock();
      return Promise.resolve();
    },
  };
});

function setStatus(opts: { visible: UserVisibleStatus; percent?: number | null }) {
  useStatusStore.setState((s) => ({
    status: {
      ...s.status,
      visible: opts.visible,
      progress_percent: opts.percent ?? null,
    },
  }));
}

afterEach(() => {
  cleanup();
  cancelModelPullMock.mockClear();
  giveConsentMock.mockClear();
});

describe('FirstRunProgress — downloading phase', () => {
  it('renders the downloading label by default', () => {
    setStatus({ visible: 'laddar_ner_modell', percent: 17 });
    render(<FirstRunProgress />);
    expect(
      screen.getByText(WIZARD_STRINGS.progress_label_downloading),
    ).toBeInTheDocument();
  });

  it('renders the progressbar role with aria-valuenow reflecting percent', () => {
    setStatus({ visible: 'laddar_ner_modell', percent: 42 });
    render(<FirstRunProgress />);
    const bar = screen.getByRole('progressbar');
    expect(bar).toHaveAttribute('aria-valuenow', '42');
    expect(bar).toHaveAttribute('aria-valuemin', '0');
    expect(bar).toHaveAttribute('aria-valuemax', '100');
  });

  it('renders the Cancel button with the right Swedish copy', () => {
    setStatus({ visible: 'laddar_ner_modell', percent: 10 });
    render(<FirstRunProgress />);
    expect(
      screen.getByText(WIZARD_STRINGS.progress_cancel_button),
    ).toBeInTheDocument();
  });

  it('Cancel click invokes cancelModelPull()', () => {
    setStatus({ visible: 'laddar_ner_modell', percent: 10 });
    render(<FirstRunProgress />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.progress_cancel_button));
    expect(cancelModelPullMock).toHaveBeenCalledTimes(1);
  });

  it('Escape key invokes cancelModelPull (FR-017)', () => {
    setStatus({ visible: 'laddar_ner_modell', percent: 10 });
    render(<FirstRunProgress />);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(cancelModelPullMock).toHaveBeenCalledTimes(1);
  });
});

describe('FirstRunProgress — error phase', () => {
  it('disk-full visible status renders the destructive heading', () => {
    setStatus({ visible: 'fel_disk_full' });
    render(<FirstRunProgress />);
    // Both the heading AND the helper paragraph contain "diskutrymme";
    // scope the assertion to the heading via its role.
    expect(
      screen.getByRole('heading', { name: /diskutrymme/i }),
    ).toBeInTheDocument();
  });

  it('error phase shows the "Försök igen" button', () => {
    setStatus({ visible: 'fel_modellnedladdning_avbroten' });
    render(<FirstRunProgress />);
    expect(
      screen.getByText(WIZARD_STRINGS.progress_error_retry),
    ).toBeInTheDocument();
  });

  it('"Försök igen" click invokes giveConsent()', () => {
    setStatus({ visible: 'fel_modellnedladdning_avbroten' });
    render(<FirstRunProgress />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.progress_error_retry));
    expect(giveConsentMock).toHaveBeenCalledTimes(1);
  });

  it('error phase does NOT fire cancelModelPull on Escape', () => {
    setStatus({ visible: 'fel_disk_full' });
    render(<FirstRunProgress />);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(cancelModelPullMock).not.toHaveBeenCalled();
  });
});

describe('FirstRunProgress — accessibility', () => {
  it('has role=dialog with aria-modal', () => {
    setStatus({ visible: 'laddar_ner_modell', percent: 10 });
    render(<FirstRunProgress />);
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAttribute('aria-labelledby', 'wizard-progress-title');
  });
});
