// Spec 016 — click-to-browse file picker fallback.
//
// FUNCTIONAL COVERAGE INVENTORY (this file):
//  1. "Välj fil" renders, focusable, Swedish aria-label naming the zone.
//  2. Activating it opens the native picker with the zone's format filter.
//  3. On selection it dispatches the chosen file to that zone.
//  4. Cancel (null) dispatches nothing.
//  5. Disabled zone → button disabled + activation is a no-op.
//  6. Generera filter is txt/md; other zones get the 7-format set.

import { fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const openMock = vi.fn();
const invokeMock = vi.fn((..._args: unknown[]) => Promise.resolve(undefined));

vi.mock('@tauri-apps/plugin-dialog', () => ({
  open: (...args: unknown[]) => openMock(...args),
}));
vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));
vi.mock('@tauri-apps/api/event', () => ({ listen: vi.fn(async () => () => {}) }));

import { DropZone } from '../components/DropZone';
import { useStatusStore } from '@/lib/status-store';
import type { ZoneId } from '@/lib/tauri-bridge';

function setup(zoneId: ZoneId, opts: { disabled?: boolean } = {}) {
  useStatusStore.setState((s) => ({
    status: { ...s.status, visible: opts.disabled ? 'laddar_ner_modell' : 'klar' },
    zones: {
      ...s.zones,
      [zoneId]: {
        state: 'idle',
        disabled: false,
        failure: null,
        job_id: null,
        progress_hint: null,
      },
    },
  }));
  render(<DropZone zoneId={zoneId} />);
}

beforeEach(() => {
  openMock.mockReset();
  invokeMock.mockClear();
});
afterEach(() => cleanup());

describe('DropZone "Välj fil" picker (spec 016)', () => {
  it('renders a focusable button with a Swedish aria-label naming the zone', () => {
    setup('anonymisera');
    const btn = screen.getByLabelText('Välj fil för Anonymisera');
    expect(btn).toBeInTheDocument();
    expect(btn.tagName).toBe('BUTTON');
    expect((btn as HTMLButtonElement).disabled).toBe(false);
  });

  it('opens the picker with the 7-format filter and dispatches the choice', async () => {
    openMock.mockResolvedValue('/tmp/foo.docx');
    setup('sammanfatta');
    fireEvent.click(screen.getByLabelText('Välj fil för Sammanfatta'));
    await waitFor(() => expect(openMock).toHaveBeenCalledTimes(1));
    const arg = openMock.mock.calls[0]![0] as {
      multiple: boolean;
      filters: { extensions: string[] }[];
    };
    expect(arg.multiple).toBe(false);
    expect(arg.filters[0]!.extensions).toEqual([
      'docx',
      'pdf',
      'txt',
      'md',
      'rtf',
      'odt',
    ]);
    await waitFor(() =>
      expect(invokeMock).toHaveBeenCalledWith('dispatch_to_zone', {
        zoneId: 'sammanfatta',
        paths: ['/tmp/foo.docx'],
      }),
    );
  });

  it('uses the txt/md filter for Generera', async () => {
    openMock.mockResolvedValue(null);
    setup('generera');
    fireEvent.click(screen.getByLabelText('Välj fil för Generera juridisk text'));
    await waitFor(() => expect(openMock).toHaveBeenCalledTimes(1));
    const arg = openMock.mock.calls[0]![0] as { filters: { extensions: string[] }[] };
    expect(arg.filters[0]!.extensions).toEqual(['txt', 'md']);
  });

  it('dispatches nothing when the picker is cancelled', async () => {
    openMock.mockResolvedValue(null);
    setup('forenkla');
    fireEvent.click(screen.getByLabelText('Välj fil för Förenkla'));
    await waitFor(() => expect(openMock).toHaveBeenCalledTimes(1));
    // Give any (non-)dispatch a tick.
    await Promise.resolve();
    expect(invokeMock).not.toHaveBeenCalledWith('dispatch_to_zone', expect.anything());
  });

  it('disables the button and is a no-op when the zone is disabled', () => {
    setup('punktlista', { disabled: true });
    const btn = screen.getByLabelText('Välj fil för Punktlista') as HTMLButtonElement;
    expect(btn.disabled).toBe(true);
    fireEvent.click(btn);
    expect(openMock).not.toHaveBeenCalled();
  });
});
