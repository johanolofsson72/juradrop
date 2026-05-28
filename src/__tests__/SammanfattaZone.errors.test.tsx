import { render, screen } from '@testing-library/react';
import { describe, expect, it, beforeEach } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SammanfattaZone } from '../components/DropZone';
import { SWEDISH_ZONE_ERROR } from '../components/DropZone.errors';
import { useStatusStore } from '@/lib/status-store';
import type { ZoneFailure } from '@/lib/tauri-bridge';

// Spec 003 / T047 — explicit Swedish-copy assertions for every
// ZoneFailure variant rendered by SammanfattaZone.
// Spec 003 / T048 — cross-language drift assertion: vitest reads the
// same `zone-error-strings.json` fixture the Rust test reads (see
// src-tauri/tests/zone_docx_robustness.rs::every_zone_failure_string_matches_the_cross_language_fixture)
// and verifies SWEDISH_ZONE_ERROR matches byte-for-byte. If a future
// PR drifts one side of the boundary, this test fails loudly.

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = path.resolve(
  __dirname,
  '../../src-tauri/tests/fixtures/zone-error-strings.json',
);

interface Fixture {
  invalid_format: string;
  multiple_files: string;
  zone_busy: string;
  zone_disabled: string;
  parse_error: string;
  password_protected: string;
  empty_text: string;
  model_error: string;
  save_error: string;
  // Spec 005 — PDF-only + .txt/.md-encoding variants.
  no_extractable_text: string;
  unsupported_encoding: string;
  // Spec 009 — format-named long-tail variants.
  rtf_parse_error: string;
  pages_parse_error: string;
  odt_parse_error: string;
}

function loadFixture(): Fixture {
  const raw = fs.readFileSync(FIXTURE_PATH, 'utf-8');
  return JSON.parse(raw) as Fixture;
}

function setStateForFailure(failure: ZoneFailure) {
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

describe('SammanfattaZone — Swedish error copy (T047)', () => {
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

  const variants: ZoneFailure[] = [
    'invalid_format',
    'multiple_files',
    'zone_busy',
    'zone_disabled',
    'parse_error',
    'password_protected',
    'empty_text',
    'model_error',
    'save_error',
    // Spec 005 — PDF-only + .txt/.md-encoding variants.
    'no_extractable_text',
    'unsupported_encoding',
    // Spec 009 — format-named long-tail variants.
    'rtf_parse_error',
    'pages_parse_error',
    'odt_parse_error',
  ];

  variants.forEach((failure) => {
    it(`renders SWEDISH_ZONE_ERROR[${failure}] when zone.failure === "${failure}"`, () => {
      setStateForFailure(failure);
      render(<SammanfattaZone />);
      const expected = SWEDISH_ZONE_ERROR[failure];
      expect(screen.getByText(expected)).toBeInTheDocument();
    });
  });

  it('no rendered failure string starts with "Error:" — Allium NoEnglishPrefix invariant', () => {
    variants.forEach((failure) => {
      const copy = SWEDISH_ZONE_ERROR[failure];
      expect(copy.startsWith('Error:')).toBe(false);
      expect(copy.toLowerCase()).not.toMatch(/\berror\b/);
    });
  });

  it('every failure string is ≤ 80 characters — Allium LengthBounded invariant', () => {
    variants.forEach((failure) => {
      const copy = SWEDISH_ZONE_ERROR[failure];
      expect(copy.length).toBeLessThanOrEqual(80);
      expect(copy.length).toBeGreaterThan(0);
    });
  });

  it('renders the error string into the role="status" live region (SC-007)', () => {
    setStateForFailure('parse_error');
    render(<SammanfattaZone />);
    const live = screen.getByRole('status');
    expect(live.getAttribute('aria-live')).toBe('polite');
    expect(live.getAttribute('aria-atomic')).toBe('true');
    expect(live.textContent).toBe(SWEDISH_ZONE_ERROR.parse_error);
  });

  // SC-002 check — the error string must appear within 3 s of the
  // trigger. The component is purely state-reactive (no async work
  // between store-mutate and render), so this is effectively a
  // < 100 ms assertion. The explicit timing assertion documents the
  // SC-002 contract in the test source.
  it('error string appears within the SC-002 3-second budget', async () => {
    render(<SammanfattaZone />);
    expect(screen.queryByText(SWEDISH_ZONE_ERROR.model_error)).toBeNull();

    const start = performance.now();
    setStateForFailure('model_error');
    const live = await screen.findByText(
      SWEDISH_ZONE_ERROR.model_error,
      undefined,
      { timeout: 3000 },
    );
    const elapsed = performance.now() - start;
    expect(live).toBeInTheDocument();
    expect(elapsed).toBeLessThan(3000);
  });
});

describe('Cross-language Swedish copy drift (T048)', () => {
  // Loads the same JSON fixture the Rust drift test loads. Any change
  // to a Rust ZoneFailure::Display string or a TS SWEDISH_ZONE_ERROR
  // entry that doesn't also update the fixture fails one of the two
  // sides — forcing the human to keep all three in sync.

  it('fixture file is on disk where both languages expect it', () => {
    expect(fs.existsSync(FIXTURE_PATH)).toBe(true);
  });

  it('every TS SWEDISH_ZONE_ERROR entry matches the fixture byte-for-byte', () => {
    const fixture = loadFixture();
    const expectedKeys: Array<keyof Fixture> = [
      'invalid_format',
      'multiple_files',
      'zone_busy',
      'zone_disabled',
      'parse_error',
      'password_protected',
      'empty_text',
      'model_error',
      'save_error',
      // Spec 005 — PDF-only + .txt/.md-encoding variants.
      'no_extractable_text',
      'unsupported_encoding',
      // Spec 009 — format-named long-tail variants.
      'rtf_parse_error',
      'pages_parse_error',
      'odt_parse_error',
    ];

    expectedKeys.forEach((key) => {
      expect(SWEDISH_ZONE_ERROR[key]).toBe(fixture[key]);
    });
  });

  it('SWEDISH_ZONE_ERROR has exactly the 14 expected ZoneFailure keys (no extras)', () => {
    // Spec 003 introduced 9 variants; spec 005 added two more
    // (no_extractable_text + unsupported_encoding) for the four-format
    // input matrix; spec 009 added three format-named long-tail
    // variants (rtf_parse_error, pages_parse_error, odt_parse_error).
    const tsKeys = Object.keys(SWEDISH_ZONE_ERROR).sort();
    const expected = [
      'empty_text',
      'invalid_format',
      'model_error',
      'multiple_files',
      'no_extractable_text',
      'odt_parse_error',
      'pages_parse_error',
      'parse_error',
      'password_protected',
      'rtf_parse_error',
      'save_error',
      'unsupported_encoding',
      'zone_busy',
      'zone_disabled',
    ];
    expect(tsKeys).toEqual(expected);
  });
});
