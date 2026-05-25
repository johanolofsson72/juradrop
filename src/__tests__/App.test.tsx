import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { App } from '../App';

describe('App', () => {
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
