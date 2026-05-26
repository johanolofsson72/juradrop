import { describe, expect, it, beforeEach, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { ConsentModal } from '../components/ConsentModal';
import { useStatusStore } from '@/lib/status-store';
import type { AppStatus } from '@/lib/tauri-bridge';

vi.mock('@/lib/tauri-bridge', async () => {
  const actual = await vi.importActual<typeof import('@/lib/tauri-bridge')>(
    '@/lib/tauri-bridge',
  );
  return {
    ...actual,
    giveConsent: vi.fn().mockResolvedValue(undefined),
    cancelConsent: vi.fn().mockResolvedValue(undefined),
  };
});

import * as bridge from '@/lib/tauri-bridge';

const baseStatus: AppStatus = {
  visible: 'startar',
  sidecar: 'not_started',
  model: 'not_present',
  progress_percent: null,
  consent: 'not_asked',
};

const setStore = (overrides: Partial<AppStatus>) => {
  useStatusStore.setState((s) => ({ status: { ...s.status, ...overrides } }));
};

describe('ConsentModal', () => {
  beforeEach(() => {
    useStatusStore.setState({ status: { ...baseStatus } });
    vi.clearAllMocks();
  });

  it('does not render when consent has already been given', () => {
    setStore({
      visible: 'laddar_ner_modell',
      sidecar: 'ready',
      model: 'downloading',
      consent: 'fortsatt',
    });
    render(<ConsentModal />);
    expect(screen.queryByText('Ladda ner AI-modell')).toBeNull();
  });

  it('does not render when the user has cancelled previously', () => {
    setStore({
      visible: 'modell_saknas_avbruten',
      sidecar: 'ready',
      model: 'not_present',
      consent: 'avbryt',
    });
    render(<ConsentModal />);
    expect(screen.queryByText('Ladda ner AI-modell')).toBeNull();
  });

  it('does not render when the model is already present', () => {
    setStore({
      visible: 'klar',
      sidecar: 'ready',
      model: 'ready',
      consent: 'fortsatt',
    });
    render(<ConsentModal />);
    expect(screen.queryByText('Ladda ner AI-modell')).toBeNull();
  });

  it('renders exactly when visible=begar_samtycke AND consent=not_asked', () => {
    setStore({
      visible: 'begar_samtycke',
      sidecar: 'ready',
      model: 'not_present',
      consent: 'not_asked',
    });
    render(<ConsentModal />);
    expect(screen.getByText('Ladda ner AI-modell')).toBeInTheDocument();
  });

  it('shows the Swedish body copy mentioning ollama.com', () => {
    setStore({
      visible: 'begar_samtycke',
      consent: 'not_asked',
    });
    render(<ConsentModal />);
    const body = screen.getByText(/ollama\.com/);
    expect(body).toBeInTheDocument();
    expect(body.textContent).toContain('~3 GB');
    expect(body.textContent).toContain('enda gången');
  });

  it('renders both Fortsätt and Avbryt buttons', () => {
    setStore({
      visible: 'begar_samtycke',
      consent: 'not_asked',
    });
    render(<ConsentModal />);
    expect(screen.getByRole('button', { name: 'Fortsätt' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Avbryt' })).toBeInTheDocument();
  });

  it('invokes the give_consent bridge when Fortsätt is clicked', () => {
    setStore({
      visible: 'begar_samtycke',
      consent: 'not_asked',
    });
    render(<ConsentModal />);
    fireEvent.click(screen.getByRole('button', { name: 'Fortsätt' }));
    expect(bridge.giveConsent).toHaveBeenCalledTimes(1);
    expect(bridge.cancelConsent).not.toHaveBeenCalled();
  });

  it('invokes the cancel_consent bridge when Avbryt is clicked', () => {
    setStore({
      visible: 'begar_samtycke',
      consent: 'not_asked',
    });
    render(<ConsentModal />);
    fireEvent.click(screen.getByRole('button', { name: 'Avbryt' }));
    expect(bridge.cancelConsent).toHaveBeenCalledTimes(1);
    expect(bridge.giveConsent).not.toHaveBeenCalled();
  });

  it('exposes the dialog with a describedby pointing at the body', () => {
    setStore({
      visible: 'begar_samtycke',
      consent: 'not_asked',
    });
    const { container } = render(<ConsentModal />);
    const described = container.ownerDocument.querySelector('[aria-describedby="consent-body"]');
    expect(described).not.toBeNull();
  });
});
