// Spec 023 — frontend error boundary.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. A child that throws on render → Swedish fallback + "Starta om" button.
//  2. The raw error message / stack is NOT in the fallback DOM (Principle VIII).
//  3. A non-throwing child renders transparently (no fallback).

import { render, screen, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { ErrorBoundary } from '@/components/ErrorBoundary';

const SECRET_ERROR = 'TOPSECRET-stacktrace-marker-9001';

function Throws(): never {
  throw new Error(SECRET_ERROR);
}

beforeEach(() => {
  // React logs caught render errors to console.error; silence the expected
  // noise so the test output stays clean.
  vi.spyOn(console, 'error').mockImplementation(() => {});
});
afterEach(() => {
  vi.restoreAllMocks();
  cleanup();
});

describe('ErrorBoundary', () => {
  it('shows the Swedish fallback + restart button when a child throws', () => {
    render(
      <ErrorBoundary>
        <Throws />
      </ErrorBoundary>,
    );
    expect(screen.getByText('Något gick fel i appen')).toBeInTheDocument();
    expect(
      screen.getByText(/Dina dokument är orörda och ingenting har skickats/),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Starta om' })).toBeInTheDocument();
  });

  it('never leaks the raw error message or stack to the DOM (Principle VIII)', () => {
    const { container } = render(
      <ErrorBoundary>
        <Throws />
      </ErrorBoundary>,
    );
    expect(container.textContent).not.toContain(SECRET_ERROR);
  });

  it('renders a non-throwing child transparently', () => {
    render(
      <ErrorBoundary>
        <p>allt fungerar</p>
      </ErrorBoundary>,
    );
    expect(screen.getByText('allt fungerar')).toBeInTheDocument();
    expect(screen.queryByText('Något gick fel i appen')).toBeNull();
  });
});
