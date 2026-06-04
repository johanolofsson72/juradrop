// Spec 042 — the privacy colophon (FR-001/002/010, contract P-1/P-2).
//
// T001 frontend-design decisions (recorded per the design gate):
// - A COLOPHON: legal documents close with an attestation line; this
//   window closes with its standing fact. One centered text-xs
//   muted sentence under the grid — the only centered micro-line in
//   the window, which is what makes it read as a fact rather than
//   chrome. Quietness IS the design: no icon, no border, no
//   background, no trust-seal theater.
// - Human-sentence voice (normal tracking), NOT the mono-uppercase
//   micro-label voice — that register means "machine label" in this
//   app (zone format badges); this line is a promise to a person.
// - Deliberately non-interactive (clarified 2026-06-04): no link, no
//   tabIndex, no handlers, no hover state. Exposed to assistive tech
//   as regular content (no aria-hidden).
// - ≈20 px tall; mounted in the same conditional branch as the grid,
//   so BadgeAlwaysWithGrid holds by co-location, not synchronization.

import { PRIVACY_BADGE_TEXT } from '@/lib/privacy-facts';

export function PrivacyBadge() {
  return (
    <p
      data-privacy-badge
      className="w-full text-center text-xs text-muted-foreground"
    >
      {PRIVACY_BADGE_TEXT}
    </p>
  );
}
