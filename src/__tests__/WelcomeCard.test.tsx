import { render, screen } from '@testing-library/react';
import { describe, expect, it, beforeEach } from 'vitest';
import { WelcomeCard } from '../components/WelcomeCard';
import { useStatusStore } from '@/lib/status-store';

const setStore = (overrides: Partial<ReturnType<typeof useStatusStore.getState>['status']>) => {
  useStatusStore.setState((s) => ({
    status: { ...s.status, ...overrides },
  }));
};

describe('WelcomeCard', () => {
  beforeEach(() => {
    useStatusStore.setState({
      status: {
        visible: 'startar',
        sidecar: 'not_started',
        model: 'not_present',
        progress_percent: null,
        consent: 'not_asked',
      },
    });
  });

  it('renders the JuraDrop title', () => {
    render(<WelcomeCard />);
    expect(screen.getByText('JuraDrop')).toBeInTheDocument();
  });

  it('renders the Swedish subtitle exactly', () => {
    render(<WelcomeCard />);
    expect(screen.getByText('Lokal AI för svenska juriststudenter')).toBeInTheDocument();
  });

  it('shows the starting message at boot', () => {
    render(<WelcomeCard />);
    expect(screen.getByText('Startar AI...')).toBeInTheDocument();
  });

  it('shows "AI redo" when ready', () => {
    setStore({ visible: 'klar', sidecar: 'ready', model: 'ready', consent: 'fortsatt' });
    render(<WelcomeCard />);
    expect(screen.getByText('AI redo')).toBeInTheDocument();
  });

  it('shows the download progress including percent', () => {
    setStore({
      visible: 'laddar_ner_modell',
      sidecar: 'ready',
      model: 'downloading',
      progress_percent: 42,
      consent: 'fortsatt',
    });
    render(<WelcomeCard />);
    expect(screen.getByText('Laddar ner AI-modell... 42%')).toBeInTheDocument();
  });

  it('shows the Swedish error string when the sidecar cannot start', () => {
    setStore({
      visible: 'fel_kunde_inte_starta',
      sidecar: 'crashed',
      model: 'not_present',
      consent: 'not_asked',
    });
    render(<WelcomeCard />);
    expect(
      screen.getByText('AI-motorn kunde inte starta. Starta om JuraDrop.'),
    ).toBeInTheDocument();
  });

  it('marks the status paragraph as aria-live polite', () => {
    const { container } = render(<WelcomeCard />);
    const live = container.querySelector('[aria-live="polite"]');
    expect(live).not.toBeNull();
  });

  it('uses Tailwind utility classes on the card', () => {
    const { container } = render(<WelcomeCard />);
    const card = container.querySelector('[class*="rounded"]');
    expect(card).not.toBeNull();
  });
});
