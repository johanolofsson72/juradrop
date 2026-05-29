// Spec 023 — top-level React error boundary.
//
// A render crash anywhere in the tree would otherwise blank the WKWebView
// (white screen, no explanation). This boundary catches it and shows a
// calm Swedish fallback + a restart button instead — the frontend half of
// Principle VIII (honest failure states). The actual error goes to
// console.error only; it is NEVER rendered (no stack-trace leak) and never
// leaves the device (Principle I).
//
// Error boundaries must be class components — getDerivedStateFromError /
// componentDidCatch have no hooks equivalent.

import { Component, type ErrorInfo, type ReactNode } from 'react';

import { Button } from '@/components/ui/button';

// Swedish fallback copy (humanizer-reviewed). Reassures the user that the
// privacy promise still holds — nothing was lost, nothing was sent.
const FALLBACK = {
  title: 'Något gick fel i appen',
  body: 'Dina dokument är orörda och ingenting har skickats någonstans. Starta om appen så försöker vi igen.',
  restart: 'Starta om',
} as const;

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
}

export class ErrorBoundary extends Component<Props, State> {
  override state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  override componentDidCatch(error: Error, info: ErrorInfo): void {
    // Local console only — never to the UI, never off-device.
    console.error('[ErrorBoundary] render crash:', error, info.componentStack);
  }

  override render(): ReactNode {
    if (!this.state.hasError) return this.props.children;

    return (
      <main
        role="alert"
        data-error-boundary-fallback
        className="flex min-h-screen flex-col items-center justify-center gap-6 bg-background p-6 text-center text-foreground"
      >
        <div className="flex max-w-sm flex-col gap-3">
          <h1 className="text-xl font-semibold tracking-tight text-foreground">
            {FALLBACK.title}
          </h1>
          <p className="text-sm leading-relaxed text-muted-foreground">{FALLBACK.body}</p>
        </div>
        <Button onClick={() => window.location.reload()}>{FALLBACK.restart}</Button>
      </main>
    );
  }
}
