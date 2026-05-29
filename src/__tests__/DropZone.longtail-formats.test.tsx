// Spec 009 (+ spec 028) — TS-side coverage for the long-tail format matrix.
//
// Spec 028 removed `.pages`: the supported set is now six formats
// (.docx, .pdf, .txt, .md, .rtf, .odt) and the Pages error became an
// actionable "not supported" message (`pages_unsupported`).
//
// Asserts:
//   - Hint copy for every zone lists all six supported formats in the
//     slash-separated canonical order (FR-011 / SC-006).
//   - The format-named long-tail keys (rtf/odt) map to the pinned Swedish
//     strings and survive cross-language drift; pages_unsupported is its
//     own actionable message.
//   - The updated invalid_format copy lists all six extensions, never .pages.
//   - When the zone enters `error`, the rendered copy is the right string.
//   - Regression: unsupported extensions still surface InvalidFormat.

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

const HINT_PREFIX = 'Släpp .docx/.pdf/.txt/.md/.rtf/.odt för ';
const REQUIRED_EXTENSIONS = ['.docx', '.pdf', '.txt', '.md', '.rtf', '.odt'] as const;

// Spec 013 — `generera` takes only .txt/.md instructions, so it's
// exempt from the supported-format slash-prefix invariant. All OTHER
// zones still satisfy the full six-format hint copy.
const SIX_FORMAT_ZONES = Object.keys(ZONE_IDENTITIES).filter((id) => id !== 'generera');

describe('Spec 028 — hint copy lists all six supported formats', () => {
  it('every zone hint (except generera) starts with the canonical slash-separated six-format prefix', () => {
    for (const id of SIX_FORMAT_ZONES) {
      const entry = ZONE_IDENTITIES[id as keyof typeof ZONE_IDENTITIES];
      expect(
        entry.hintCopy.startsWith(HINT_PREFIX),
        `${id} hintCopy does not start with ${HINT_PREFIX}: ${entry.hintCopy}`,
      ).toBe(true);
    }
  });

  it('every zone hint (except generera) contains all six supported extensions and not .pages', () => {
    for (const id of SIX_FORMAT_ZONES) {
      const entry = ZONE_IDENTITIES[id as keyof typeof ZONE_IDENTITIES];
      REQUIRED_EXTENSIONS.forEach((ext) => {
        expect(
          entry.hintCopy.includes(ext),
          `${id} hintCopy missing ${ext}: ${entry.hintCopy}`,
        ).toBe(true);
      });
      expect(
        entry.hintCopy.includes('.pages'),
        `${id} hintCopy must not list the removed .pages: ${entry.hintCopy}`,
      ).toBe(false);
    }
  });

  it('every zone hint is ≤ 80 chars (SwedishCopy invariant, SC-006)', () => {
    for (const id of Object.keys(ZONE_IDENTITIES)) {
      const entry = ZONE_IDENTITIES[id as keyof typeof ZONE_IDENTITIES];
      expect(entry.hintCopy.length).toBeLessThanOrEqual(80);
    }
  });

  it('the longest hint (engelsk översättning) is exactly 60 chars after dropping .pages', () => {
    // Was 67 with .pages/ (spec 009); spec 028 removes ".pages/" (7 chars).
    expect(ZONE_IDENTITIES.tillengelska.hintCopy.length).toBe(60);
  });
});

describe('Spec 028 — long-tail + Pages-unsupported Swedish error strings', () => {
  it('SWEDISH_ZONE_ERROR maps the rtf/odt parse errors and the Pages-unsupported message', () => {
    expect(SWEDISH_ZONE_ERROR.rtf_parse_error).toBe('Kunde inte läsa .rtf-filen');
    expect(SWEDISH_ZONE_ERROR.odt_parse_error).toBe('Kunde inte läsa .odt-filen');
    expect(SWEDISH_ZONE_ERROR.pages_unsupported).toBe(
      'Pages-filer stöds inte — exportera till Word eller PDF först',
    );
  });

  it('every long-tail error key matches the JSON fixture byte-for-byte', () => {
    const fixture = JSON.parse(fs.readFileSync(ERROR_FIXTURE, 'utf-8'));
    expect(SWEDISH_ZONE_ERROR.rtf_parse_error).toBe(fixture.rtf_parse_error);
    expect(SWEDISH_ZONE_ERROR.pages_unsupported).toBe(fixture.pages_unsupported);
    expect(SWEDISH_ZONE_ERROR.odt_parse_error).toBe(fixture.odt_parse_error);
  });

  it('the updated invalid_format copy lists all six extensions and not .pages', () => {
    const fixture = JSON.parse(fs.readFileSync(ERROR_FIXTURE, 'utf-8'));
    REQUIRED_EXTENSIONS.forEach((ext) => {
      expect(fixture.invalid_format).toContain(ext);
      expect(SWEDISH_ZONE_ERROR.invalid_format).toContain(ext);
    });
    expect(fixture.invalid_format).not.toContain('.pages');
    expect(SWEDISH_ZONE_ERROR.invalid_format).not.toContain('.pages');
    expect(SWEDISH_ZONE_ERROR.invalid_format).toBe(fixture.invalid_format);
  });

  it('rtf/odt parse-error strings are ≤ 80 chars and start with "Kunde inte läsa"', () => {
    const longTail: ZoneFailure[] = ['rtf_parse_error', 'odt_parse_error'];
    longTail.forEach((key) => {
      const value = SWEDISH_ZONE_ERROR[key];
      expect(value.length).toBeLessThanOrEqual(80);
      expect(value.startsWith('Kunde inte läsa')).toBe(true);
    });
  });

  it('the Pages-unsupported message names Pages, is actionable, ≤ 80 chars, no path leak', () => {
    const value = SWEDISH_ZONE_ERROR.pages_unsupported;
    expect(value.length).toBeLessThanOrEqual(80);
    expect(value).toContain('Pages');
    expect(value.toLowerCase()).toMatch(/word|pdf/);
    expect(value.includes('.pages')).toBe(false);
    expect(value.includes('/')).toBe(false);
    expect(value.includes('\\')).toBe(false);
  });

  it('rtf/odt Swedish strings do not contain forward slash or backslash (no path leak)', () => {
    const longTail: ZoneFailure[] = ['rtf_parse_error', 'odt_parse_error'];
    longTail.forEach((key) => {
      const value = SWEDISH_ZONE_ERROR[key];
      expect(value.includes('/')).toBe(false);
      expect(value.includes('\\')).toBe(false);
    });
  });
});

describe('Spec 028 — long-tail zone identity fixture mirror', () => {
  it('every zone identity fixture row (except generera) uses the slash-separated hint prefix', () => {
    const fixture = JSON.parse(fs.readFileSync(IDENTITY_FIXTURE, 'utf-8'));
    for (const id of SIX_FORMAT_ZONES) {
      const row = fixture[id];
      expect(row, `${id} missing from fixture`).toBeTruthy();
      expect(row.hint_copy.startsWith(HINT_PREFIX)).toBe(true);
    }
  });
});

describe('Spec 028 — error state renders the right Swedish copy', () => {
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

  it('renders the actionable Pages-unsupported copy when zone.failure === "pages_unsupported"', () => {
    setFailure('pages_unsupported');
    render(<SammanfattaZone />);
    expect(
      screen.getByText('Pages-filer stöds inte — exportera till Word eller PDF först'),
    ).toBeInTheDocument();
  });

  it('renders odt_parse_error copy when zone.failure === "odt_parse_error"', () => {
    setFailure('odt_parse_error');
    render(<SammanfattaZone />);
    expect(screen.getByText('Kunde inte läsa .odt-filen')).toBeInTheDocument();
  });

  it('renders the updated six-format InvalidFormat copy on invalid_format failures (regression)', () => {
    setFailure('invalid_format');
    render(<SammanfattaZone />);
    const expected =
      'Filformatet stöds inte — dra ett .docx, .pdf, .txt, .md, .rtf eller .odt';
    expect(screen.getByText(expected)).toBeInTheDocument();
  });
});
