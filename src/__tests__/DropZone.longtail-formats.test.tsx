// Spec 009 — TS-side coverage for the long-tail format additions.
//
// Asserts:
//   - Hint copy for every zone lists all seven supported formats in
//     the slash-separated canonical order (FR-011 / SC-006).
//   - The three new SWEDISH_ZONE_ERROR keys map to the pinned Swedish
//     strings and survive cross-language drift (FR-013 / SC-005).
//   - The updated invalid_format copy lists all seven extensions
//     (FR-012).
//   - When the zone enters `error` with a long-tail failure variant,
//     the rendered copy is the format-named Swedish string (US-2 / FR-007).
//   - Regression: unsupported extensions still surface InvalidFormat
//     with the 7-format Swedish copy (US-4 / FR-018).

import { render, screen } from '@testing-library/react';
import { describe, expect, it, beforeEach } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { SammanfattaZone } from '../components/DropZone';
import { SWEDISH_ZONE_ERROR } from '../components/DropZone.errors';
import { ZONE_IDENTITIES } from '../components/DropZone.identity';
import { useStatusStore } from '@/lib/status-store';
import type { ZoneFailure } from '@/lib/tauri-bridge';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ERROR_FIXTURE = path.resolve(
  __dirname,
  '../../src-tauri/tests/fixtures/zone-error-strings.json',
);
const IDENTITY_FIXTURE = path.resolve(
  __dirname,
  '../../src-tauri/tests/fixtures/zone-identity.json',
);

const HINT_PREFIX = 'Släpp .docx/.pdf/.txt/.md/.rtf/.pages/.odt för ';
const REQUIRED_EXTENSIONS = [
  '.docx',
  '.pdf',
  '.txt',
  '.md',
  '.rtf',
  '.pages',
  '.odt',
] as const;

// Spec 013 — `generera` takes only .txt/.md instructions, so it's
// exempt from the 7-format slash-prefix invariant inherited from
// spec 009. All OTHER zones still satisfy the full 7-format hint copy.
const SEVEN_FORMAT_ZONES = Object.keys(ZONE_IDENTITIES).filter(
  (id) => id !== 'generera',
);

describe('Spec 009 — hint copy lists all seven supported formats', () => {
  it('every zone hint (except generera) starts with the canonical slash-separated 7-format prefix', () => {
    for (const id of SEVEN_FORMAT_ZONES) {
      const entry = ZONE_IDENTITIES[id as keyof typeof ZONE_IDENTITIES];
      expect(
        entry.hintCopy.startsWith(HINT_PREFIX),
        `${id} hintCopy does not start with ${HINT_PREFIX}: ${entry.hintCopy}`,
      ).toBe(true);
    }
  });

  it('every zone hint (except generera) contains all seven supported extensions', () => {
    for (const id of SEVEN_FORMAT_ZONES) {
      const entry = ZONE_IDENTITIES[id as keyof typeof ZONE_IDENTITIES];
      REQUIRED_EXTENSIONS.forEach((ext) => {
        expect(
          entry.hintCopy.includes(ext),
          `${id} hintCopy missing ${ext}: ${entry.hintCopy}`,
        ).toBe(true);
      });
    }
  });

  it('every zone hint is ≤ 80 chars (SwedishCopy invariant, SC-006)', () => {
    for (const id of Object.keys(ZONE_IDENTITIES)) {
      const entry = ZONE_IDENTITIES[id as keyof typeof ZONE_IDENTITIES];
      expect(entry.hintCopy.length).toBeLessThanOrEqual(80);
    }
  });

  it('the longest hint (engelsk översättning) is exactly 67 chars', () => {
    // Pins the per-zone budget calculation in spec.md FR-011 +
    // research.md R-009.
    expect(ZONE_IDENTITIES.tillengelska.hintCopy.length).toBe(67);
  });
});

describe('Spec 009 — long-tail Swedish error strings', () => {
  it('SWEDISH_ZONE_ERROR has the three new format-named keys', () => {
    expect(SWEDISH_ZONE_ERROR.rtf_parse_error).toBe('Kunde inte läsa .rtf-filen');
    expect(SWEDISH_ZONE_ERROR.pages_parse_error).toBe('Kunde inte läsa .pages-filen');
    expect(SWEDISH_ZONE_ERROR.odt_parse_error).toBe('Kunde inte läsa .odt-filen');
  });

  it('every long-tail error key matches the JSON fixture byte-for-byte', () => {
    const fixture = JSON.parse(fs.readFileSync(ERROR_FIXTURE, 'utf-8'));
    expect(SWEDISH_ZONE_ERROR.rtf_parse_error).toBe(fixture.rtf_parse_error);
    expect(SWEDISH_ZONE_ERROR.pages_parse_error).toBe(fixture.pages_parse_error);
    expect(SWEDISH_ZONE_ERROR.odt_parse_error).toBe(fixture.odt_parse_error);
  });

  it('the updated invalid_format copy lists all seven extensions', () => {
    const fixture = JSON.parse(fs.readFileSync(ERROR_FIXTURE, 'utf-8'));
    REQUIRED_EXTENSIONS.forEach((ext) => {
      expect(fixture.invalid_format).toContain(ext);
      expect(SWEDISH_ZONE_ERROR.invalid_format).toContain(ext);
    });
    expect(SWEDISH_ZONE_ERROR.invalid_format).toBe(fixture.invalid_format);
  });

  it('long-tail Swedish strings are ≤ 80 chars and start with "Kunde inte läsa"', () => {
    const longTail: ZoneFailure[] = [
      'rtf_parse_error',
      'pages_parse_error',
      'odt_parse_error',
    ];
    longTail.forEach((key) => {
      const value = SWEDISH_ZONE_ERROR[key];
      expect(value.length).toBeLessThanOrEqual(80);
      expect(value.startsWith('Kunde inte läsa')).toBe(true);
    });
  });

  it('long-tail Swedish strings do not contain forward slash or backslash (no path leak)', () => {
    // FR-017 — mirror of the Rust no_format_named_error_leaks_path test.
    // Catches a refactor that introduces a `{path}` placeholder.
    const longTail: ZoneFailure[] = [
      'rtf_parse_error',
      'pages_parse_error',
      'odt_parse_error',
    ];
    longTail.forEach((key) => {
      const value = SWEDISH_ZONE_ERROR[key];
      expect(value.includes('/')).toBe(false);
      expect(value.includes('\\')).toBe(false);
    });
  });
});

describe('Spec 009 — long-tail zone identity fixture mirror', () => {
  it('every zone identity fixture row (except generera) uses the slash-separated hint prefix', () => {
    const fixture = JSON.parse(fs.readFileSync(IDENTITY_FIXTURE, 'utf-8'));
    for (const id of SEVEN_FORMAT_ZONES) {
      const row = fixture[id];
      expect(row, `${id} missing from fixture`).toBeTruthy();
      expect(row.hint_copy.startsWith(HINT_PREFIX)).toBe(true);
    }
  });
});

describe('Spec 009 — error state renders the long-tail Swedish copy', () => {
  beforeEach(() => {
    const idleSnap = {
      state: 'idle' as const,
      disabled: false,
      failure: null,
      job_id: null,
      progress_hint: null,
    };
    useStatusStore.setState((s) => ({
      status: {
        visible: 'klar' as const,
        sidecar: 'ready' as const,
        model: 'ready' as const,
        progress_percent: null,
        consent: 'fortsatt' as const,
      },
      zone: idleSnap,
      zones: { ...s.zones, sammanfatta: idleSnap },
    }));
  });

  function setFailure(failure: ZoneFailure) {
    useStatusStore.setState((s) => {
      const errorSnap = {
        ...s.zone,
        state: 'error' as const,
        disabled: false,
        failure,
        job_id: 'test-job',
        progress_hint: null,
      };
      return {
        status: { ...s.status, visible: 'klar' as const },
        zone: errorSnap,
        zones: { ...s.zones, sammanfatta: errorSnap },
      };
    });
  }

  it('renders rtf_parse_error copy when zone.failure === "rtf_parse_error"', () => {
    setFailure('rtf_parse_error');
    render(<SammanfattaZone />);
    expect(screen.getByText('Kunde inte läsa .rtf-filen')).toBeInTheDocument();
  });

  it('renders pages_parse_error copy when zone.failure === "pages_parse_error"', () => {
    setFailure('pages_parse_error');
    render(<SammanfattaZone />);
    expect(screen.getByText('Kunde inte läsa .pages-filen')).toBeInTheDocument();
  });

  it('renders odt_parse_error copy when zone.failure === "odt_parse_error"', () => {
    setFailure('odt_parse_error');
    render(<SammanfattaZone />);
    expect(screen.getByText('Kunde inte läsa .odt-filen')).toBeInTheDocument();
  });

  it('renders the updated 7-format InvalidFormat copy on invalid_format failures (US-4 regression)', () => {
    setFailure('invalid_format');
    render(<SammanfattaZone />);
    const expected =
      'Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf, .pages eller .odt';
    expect(screen.getByText(expected)).toBeInTheDocument();
  });
});
