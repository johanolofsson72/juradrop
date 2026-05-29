// Spec 004 / T022 + spec 013 — per-zone identity (TS mirror of ZoneId).
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
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för sammanfattning',
    sidecarSuffix: 'sammanfatta',
    processingHint: 'Sammanfattar…',
    hasDisclaimer: false,
  },
  tillengelska: {
    slug: 'tillengelska',
    title: 'Till engelska',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för engelsk översättning',
    sidecarSuffix: 'tillengelska',
    processingHint: 'Översätter…',
    hasDisclaimer: false,
  },
  tillsvenska: {
    slug: 'tillsvenska',
    title: 'Till svenska',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för svensk översättning',
    sidecarSuffix: 'tillsvenska',
    processingHint: 'Översätter…',
    hasDisclaimer: false,
  },
  punktlista: {
    slug: 'punktlista',
    title: 'Punktlista',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för punktlista',
    sidecarSuffix: 'punktlista',
    processingHint: 'Listar…',
    hasDisclaimer: false,
  },
  anonymisera: {
    slug: 'anonymisera',
    title: 'Anonymisera',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för anonymisering',
    // Past-participle adjective — matches Rust's ZoneId::sidecar_suffix.
    sidecarSuffix: 'anonymiserad',
    processingHint: 'Anonymiserar…',
    hasDisclaimer: true,
  },
  forenkla: {
    slug: 'forenkla',
    title: 'Förenkla',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för klarspråk',
    sidecarSuffix: 'forenkla',
    processingHint: 'Förenklar…',
    hasDisclaimer: true,
  },
  // Spec 013 — three new zones (3×3 grid)
  kontakter: {
    slug: 'kontakter',
    title: 'Plocka ut kontaktuppgifter',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för kontaktuppgifter',
    sidecarSuffix: 'kontakter',
    processingHint: 'Plockar ut kontaktuppgifter…',
    hasDisclaimer: false,
  },
  generera: {
    slug: 'generera',
    title: 'Generera juridisk text',
    hintCopy: 'Släpp .txt eller .md med instruktioner för juridisk text',
    sidecarSuffix: 'generera',
    processingHint: 'Genererar juridisk text…',
    hasDisclaimer: true,
  },
  kallor: {
    slug: 'kallor',
    title: 'Källförteckning',
    hintCopy: 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för källförteckning',
    sidecarSuffix: 'kallor',
    processingHint: 'Bygger källförteckning…',
    hasDisclaimer: false,
  },
} as const satisfies Record<ZoneId, ZoneIdentity>;

/// Reading order across the 3×3 grid (row 1, row 2, row 3).
/// Spec 013 expanded the order from 6 to 9 zones.
export const ZONE_ORDER: readonly ZoneId[] = [
  'sammanfatta',
  'tillengelska',
  'tillsvenska',
  'punktlista',
  'anonymisera',
  'forenkla',
  'kontakter',
  'generera',
  'kallor',
];
