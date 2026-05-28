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

  it('renders nothing when state is klar (post-spec-012 polish — happy path is silent)', () => {
    setStore({ visible: 'klar', sidecar: 'ready', model: 'ready', consent: 'fortsatt' });
    const { container } = render(<WelcomeCard />);
    expect(container.firstChild).toBeNull();
    expect(screen.queryByText('AI är redo')).toBeNull();
    expect(screen.queryByText('JuraDrop')).toBeNull();
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

  // T065 / DT-010 — screen readers must announce status changes. `polite`
  // queues the announcement behind in-progress speech; `atomic` makes the
  // whole region the announcement unit so a percent flipping from 41% to
  // 42% reads the full sentence, not just the digit. Both pieces are
  // load-bearing for VoiceOver UX.
  it('marks the status paragraph as aria-live polite and atomic for screen readers', () => {
    const { container } = render(<WelcomeCard />);
    const live = container.querySelector('[aria-live="polite"]');
    expect(live).not.toBeNull();
    expect(live?.getAttribute('aria-atomic')).toBe('true');
    expect(live?.textContent?.trim().length ?? 0).toBeGreaterThan(0);
  });

  it('uses Tailwind utility classes on the card', () => {
    const { container } = render(<WelcomeCard />);
    const card = container.querySelector('[class*="rounded"]');
    expect(card).not.toBeNull();
  });
});
