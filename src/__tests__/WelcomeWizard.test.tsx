// Spec 008 / T018 — vitest for the WelcomeWizard component.

import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { WelcomeWizard } from '../components/WelcomeWizard';
import { useStatusStore } from '@/lib/status-store';
import { WIZARD_STRINGS } from '@/lib/wizard-strings';
import type { SidecarStatus } from '@/lib/tauri-bridge';

const giveConsentMock = vi.fn();
const cancelConsentMock = vi.fn();

vi.mock('@/lib/tauri-bridge', async () => {
  const actual =
    await vi.importActual<typeof import('@/lib/tauri-bridge')>('@/lib/tauri-bridge');
  return {
    ...actual,
    giveConsent: () => {
      giveConsentMock();
      return Promise.resolve();
    },
    cancelConsent: () => {
      cancelConsentMock();
      return Promise.resolve();
    },
  };
});

function setSidecar(s: SidecarStatus) {
  useStatusStore.setState((state) => ({
    status: { ...state.status, sidecar: s },
  }));
}

afterEach(() => {
  cleanup();
  giveConsentMock.mockClear();
  cancelConsentMock.mockClear();
});

beforeEach(() => {
  setSidecar('ready');
});

describe('WelcomeWizard — Swedish copy', () => {
  it('renders the welcome title', () => {
    render(<WelcomeWizard />);
    expect(screen.getByText(WIZARD_STRINGS.welcome_title)).toBeInTheDocument();
  });

  it('renders the body paragraph with all six zone verbs', () => {
    render(<WelcomeWizard />);
    const para = screen.getByText(WIZARD_STRINGS.welcome_paragraph);
    expect(para).toBeInTheDocument();
    expect(para.textContent?.toLowerCase()).toContain('sammanfatta');
    expect(para.textContent?.toLowerCase()).toContain('översätta');
    expect(para.textContent?.toLowerCase()).toContain('anonymisera');
    expect(para.textContent?.toLowerCase()).toContain('punktlista');
    expect(para.textContent?.toLowerCase()).toContain('förenkla');
  });

  it('renders the privacy line', () => {
    render(<WelcomeWizard />);
    expect(screen.getByText(WIZARD_STRINGS.welcome_privacy_line)).toBeInTheDocument();
  });

  it('renders the download note', () => {
    render(<WelcomeWizard />);
    expect(screen.getByText(WIZARD_STRINGS.welcome_download_note)).toBeInTheDocument();
  });

  it('renders both CTAs', () => {
    render(<WelcomeWizard />);
    expect(screen.getByText(WIZARD_STRINGS.welcome_cta_primary)).toBeInTheDocument();
    expect(screen.getByText(WIZARD_STRINGS.welcome_cta_secondary)).toBeInTheDocument();
  });
});

describe('WelcomeWizard — sidecar boot helper (clarification 4)', () => {
  it('shows the helper line when sidecar !== ready', () => {
    setSidecar('starting');
    render(<WelcomeWizard />);
    expect(screen.getByText(WIZARD_STRINGS.welcome_sidecar_helper)).toBeInTheDocument();
  });

  it('hides the helper line when sidecar === ready', () => {
    setSidecar('ready');
    render(<WelcomeWizard />);
    expect(
      screen.queryByText(WIZARD_STRINGS.welcome_sidecar_helper),
    ).not.toBeInTheDocument();
  });

  it('disables Fortsätt when sidecar !== ready', () => {
    setSidecar('starting');
    render(<WelcomeWizard />);
    const btn = screen.getByText(WIZARD_STRINGS.welcome_cta_primary) as HTMLButtonElement;
    expect(btn.disabled).toBe(true);
  });

  it('enables Fortsätt when sidecar === ready', () => {
    setSidecar('ready');
    render(<WelcomeWizard />);
    const btn = screen.getByText(WIZARD_STRINGS.welcome_cta_primary) as HTMLButtonElement;
    expect(btn.disabled).toBe(false);
  });
});

describe('WelcomeWizard — interactions', () => {
  it('Fortsätt click invokes giveConsent()', () => {
    render(<WelcomeWizard />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.welcome_cta_primary));
    expect(giveConsentMock).toHaveBeenCalledTimes(1);
  });

  it('Avbryt click invokes cancelConsent()', () => {
    render(<WelcomeWizard />);
    fireEvent.click(screen.getByText(WIZARD_STRINGS.welcome_cta_secondary));
    expect(cancelConsentMock).toHaveBeenCalledTimes(1);
  });

  it('Escape key invokes cancelConsent (FR-011)', () => {
    render(<WelcomeWizard />);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(cancelConsentMock).toHaveBeenCalledTimes(1);
  });
});

describe('WelcomeWizard — accessibility', () => {
  it('has role=dialog with aria-modal and labelledby', () => {
    render(<WelcomeWizard />);
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAttribute('aria-labelledby', 'wizard-title');
  });

  it('focuses Fortsätt on mount when sidecar is ready (FR-017)', async () => {
    setSidecar('ready');
    render(<WelcomeWizard />);
    // Allow the useEffect to run.
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(document.activeElement?.textContent).toBe(WIZARD_STRINGS.welcome_cta_primary);
  });
});
