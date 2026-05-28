import { render, screen, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { App } from '../App';
import { useStatusStore } from '@/lib/status-store';

// Spec 008 — App now branches on useWizardState(). When consent is
// not_asked OR the model isn't ready, the wizard covers the
// WelcomeCard + zone-grid. These tests assert the zone-grid path; the
// wizard path is covered by WelcomeWizard.test.tsx + Wizard-specific
// suites.
function setReadyState() {
  useStatusStore.setState((s) => ({
    status: {
      ...s.status,
      visible: 'klar',
      sidecar: 'ready',
      model: 'ready',
      consent: 'fortsatt',
      progress_percent: null,
    },
  }));
}

describe('App', () => {
  beforeEach(() => {
    setReadyState();
  });

  afterEach(() => {
    cleanup();
  });

  it('renders the JuraDrop welcome title', () => {
    // FC-002: the placeholder welcome card renders inside App.
    render(<App />);
    expect(screen.getByText('JuraDrop')).toBeInTheDocument();
  });

  it('renders the Swedish subtitle', () => {
    // FC-002 + Constitution Principle V (Swedish-First UI).
    render(<App />);
    expect(screen.getByText('Lokal AI för svenska juriststudenter')).toBeInTheDocument();
  });

  it('renders inside a semantic main landmark', () => {
    // FC-006 + accessibility: the App provides a single <main> landmark.
    render(<App />);
    expect(screen.getByRole('main')).toBeInTheDocument();
  });

  it('applies Tailwind utility classes to the layout root', () => {
    // FC-003: at least one Tailwind utility class resolves on the root element.
    const { container } = render(<App />);
    const main = container.querySelector('main');
    expect(main).not.toBeNull();
    expect(main?.className).toMatch(/min-h-screen/);
    expect(main?.className).toMatch(/bg-background/);
  });
});

// Spec 008 / GAP-D — FR-005 + FR-018 mutual-exclusion: App.tsx must
// never render both <Wizard /> and the zone-grid simultaneously.
// Verified structurally via the wizard-visible vs zone-grid-visible
// tree probe.
describe('App — FR-005 + FR-018 wizard/zones mutual exclusion (GAP-D)', () => {
  afterEach(() => {
    cleanup();
  });

  it('renders the zones (NOT the wizard) when consent=fortsatt + model=ready', () => {
    useStatusStore.setState((s) => ({
      status: {
        ...s.status,
        visible: 'klar',
        sidecar: 'ready',
        model: 'ready',
        consent: 'fortsatt',
        progress_percent: null,
      },
    }));
    const { container } = render(<App />);
    // Zone-grid: identified by the Swedish aria-label.
    expect(container.querySelector('section[aria-label="Drop-zoner"]')).not.toBeNull();
    // Wizard: identified by role="dialog" + aria-labelledby="wizard-title" OR "wizard-progress-title".
    expect(container.querySelector('[aria-labelledby="wizard-title"]')).toBeNull();
    expect(container.querySelector('[aria-labelledby="wizard-progress-title"]')).toBeNull();
  });

  it('renders the wizard (NOT the zone-grid) on fresh install (consent=not_asked)', () => {
    useStatusStore.setState((s) => ({
      status: {
        ...s.status,
        visible: 'startar',
        sidecar: 'starting',
        model: 'not_present',
        consent: 'not_asked',
        progress_percent: null,
      },
    }));
    const { container } = render(<App />);
    // Wizard mounted (welcome phase).
    expect(container.querySelector('[aria-labelledby="wizard-title"]')).not.toBeNull();
    // Zone-grid absent.
    expect(container.querySelector('section[aria-label="Drop-zoner"]')).toBeNull();
  });

  it('renders the wizard (NOT the zone-grid) during progress phase', () => {
    useStatusStore.setState((s) => ({
      status: {
        ...s.status,
        visible: 'laddar_ner_modell',
        sidecar: 'ready',
        model: 'downloading',
        consent: 'fortsatt',
        progress_percent: 50,
      },
    }));
    const { container } = render(<App />);
    expect(container.querySelector('[aria-labelledby="wizard-progress-title"]')).not.toBeNull();
    expect(container.querySelector('section[aria-label="Drop-zoner"]')).toBeNull();
  });
});
