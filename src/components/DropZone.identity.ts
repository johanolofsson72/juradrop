// Spec 004 / T022 — per-zone identity (TS mirror of ZoneId).
//
// Mirror of Rust's `ZoneId::associated()` functions. Drift between
// the two sides is caught by a drift-assertion vitest test that
// reads the same fixture the Rust side reads.

import type { ZoneId } from '@/lib/tauri-bridge';

export interface ZoneIdentity {
  slug: ZoneId;
  title: string;
  hintCopy: string;
  sidecarSuffix: string;
  processingHint: string;
  hasDisclaimer: boolean;
}

export const ZONE_IDENTITIES = {
  sammanfatta: {
    slug: 'sammanfatta',
    title: 'Sammanfatta',
    hintCopy: 'Släpp ett .docx för sammanfattning',
    sidecarSuffix: 'sammanfatta',
    processingHint: 'Sammanfattar…',
    hasDisclaimer: false,
  },
  tillengelska: {
    slug: 'tillengelska',
    title: 'Till engelska',
    hintCopy: 'Släpp ett .docx för engelsk översättning',
    sidecarSuffix: 'tillengelska',
    processingHint: 'Översätter…',
    hasDisclaimer: false,
  },
  tillsvenska: {
    slug: 'tillsvenska',
    title: 'Till svenska',
    hintCopy: 'Släpp ett .docx för svensk översättning',
    sidecarSuffix: 'tillsvenska',
    processingHint: 'Översätter…',
    hasDisclaimer: false,
  },
  punktlista: {
    slug: 'punktlista',
    title: 'Punktlista',
    hintCopy: 'Släpp ett .docx för punktlista',
    sidecarSuffix: 'punktlista',
    processingHint: 'Listar…',
    hasDisclaimer: false,
  },
  anonymisera: {
    slug: 'anonymisera',
    title: 'Anonymisera',
    hintCopy: 'Släpp ett .docx för anonymisering',
    // Past-participle adjective — matches Rust's ZoneId::sidecar_suffix.
    sidecarSuffix: 'anonymiserad',
    processingHint: 'Anonymiserar…',
    hasDisclaimer: true,
  },
  forenkla: {
    slug: 'forenkla',
    title: 'Förenkla',
    hintCopy: 'Släpp ett .docx för klarspråk',
    sidecarSuffix: 'forenkla',
    processingHint: 'Förenklar…',
    hasDisclaimer: true,
  },
} as const satisfies Record<ZoneId, ZoneIdentity>;

/// Reading order across the 2×3 grid (row 1 then row 2).
export const ZONE_ORDER: readonly ZoneId[] = [
  'sammanfatta',
  'tillengelska',
  'tillsvenska',
  'punktlista',
  'anonymisera',
  'forenkla',
];
