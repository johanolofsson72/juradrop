import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { WelcomeCard } from '../components/WelcomeCard';

describe('WelcomeCard', () => {
  it('renders the JuraDrop title', () => {
    // FC-002
    render(<WelcomeCard />);
    expect(screen.getByText('JuraDrop')).toBeInTheDocument();
  });

  it('renders the Swedish subtitle exactly', () => {
    // FC-002 + Principle V — copy MUST match the clarified spec answer.
    render(<WelcomeCard />);
    expect(screen.getByText('Lokal AI för svenska juriststudenter')).toBeInTheDocument();
  });

  it('renders a disabled shadcn Button with shadcn class names', () => {
    // FC-004: a shadcn Button component is wired and renders. Shadcn's button.tsx
    // composes classes that include inline-flex, rounded-md, and text-sm (per
    // the new-york preset registered in components.json).
    render(<WelcomeCard />);
    const button = screen.getByRole('button', { name: 'Kom igång' });
    expect(button).toBeDisabled();
    expect(button.getAttribute('aria-disabled')).toBe('true');
    expect(button.className).toMatch(/inline-flex/);
    expect(button.className).toMatch(/rounded-md/);
  });

  it('uses Tailwind utility classes on the card', () => {
    // FC-003: Tailwind utilities are applied (not raw inline styles).
    const { container } = render(<WelcomeCard />);
    const card = container.querySelector('[class*="rounded"]');
    expect(card).not.toBeNull();
  });
});
