// Spec 042 T005 — PrivacyBadge functional coverage.
//
// ===== FUNCTIONAL COVERAGE INVENTORY (component scope) =====
// 1. Renders the fact-base text verbatim (one source of truth)
// 2. Non-interactive: no links/buttons/tabindex inside (P-2)
// 3. Exposed to assistive tech as content (not aria-hidden)
// ===========================================================

import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import { PrivacyBadge } from '../components/PrivacyBadge';
import { PRIVACY_BADGE_TEXT } from '@/lib/privacy-facts';

describe('PrivacyBadge', () => {
  it('renders the fact-base claim verbatim', () => {
    render(<PrivacyBadge />);
    expect(screen.getByText(PRIVACY_BADGE_TEXT)).toBeInTheDocument();
  });

  it('is non-interactive: no focusable or clickable descendants (P-2)', () => {
    const { container } = render(<PrivacyBadge />);
    expect(container.querySelectorAll('a, button, [tabindex]')).toHaveLength(0);
    const badge = container.querySelector('[data-privacy-badge]');
    expect(badge?.tagName).toBe('P');
  });

  it('is exposed as content to assistive technology', () => {
    const { container } = render(<PrivacyBadge />);
    const badge = container.querySelector('[data-privacy-badge]');
    expect(badge?.getAttribute('aria-hidden')).toBeNull();
  });
});
