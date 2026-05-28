// Spec 008 / T008 — rolling-window ETA estimator + waiting-on-network trigger.
//
// Subscribes to juradrop://progress via subscribeProgress(). Each event
// updates a sample buffer of (timestamp, percent) tuples; we synthesize
// byte counts from `percent × estimatedTotalBytes` because the existing
// `juradrop://progress` channel doesn't carry byte counts. A 1-second
// poll detects the waiting-on-network condition (FR-007 — ≥ 5 s without
// a fresh sample).

import { useEffect, useRef, useState } from 'react';

import { subscribeProgress } from './tauri-bridge';
import { useStatusStore } from './status-store';
import { WIZARD_STRINGS } from './wizard-strings';

const DEFAULT_WINDOW_MS = 10_000;
const DEFAULT_STALE_MS = 5_000;
// GAP-C / TLA+ finding — 500 ms polling cadence keeps the worst-case
// "Väntar på nätverk…" flip under the FR-007 5 s target. With 1000 ms
// the worst case was ~6 s; with 500 ms it's ~5.5 s.
const STALE_POLL_INTERVAL_MS = 500;
const ESTIMATED_TOTAL_BYTES = 2 * 1024 * 1024 * 1024; // 2 GiB ≈ gemma3:4b size

export interface ProgressEstimate {
  lastPct: number;
  lastByteCount: number;
  totalByteCount: number;
  lastProgressAt: number;
  bytesPerSecondRecent: number;
  label: 'downloading' | 'waiting';
  etaSeconds: number | null;
  etaRendered: string;
}

interface Sample {
  t: number;
  bytes: number;
}

interface Options {
  windowMs?: number;
  staleMs?: number;
  estimatedTotalBytes?: number;
}

/** FR-004 clarification — ETA formatter. */
export function formatEta(etaSeconds: number | null): string {
  if (etaSeconds === null || !Number.isFinite(etaSeconds) || etaSeconds < 0) {
    return WIZARD_STRINGS.progress_eta_unknown;
  }
  if (etaSeconds < 60) {
    const rounded = Math.max(5, Math.ceil(etaSeconds / 5) * 5);
    return `≈ ${rounded} s`;
  }
  const minutes = Math.max(1, Math.ceil(etaSeconds / 60));
  return `≈ ${minutes} min`;
}

/** Rolling-window mean bytes-per-second over the buffer. */
function meanBps(samples: Sample[]): number {
  if (samples.length < 2) return 0;
  const oldest = samples[0]!;
  const newest = samples[samples.length - 1]!;
  const dt = (newest.t - oldest.t) / 1000;
  if (dt <= 0) return 0;
  return (newest.bytes - oldest.bytes) / dt;
}

export function useProgressEstimate(opts: Options = {}): ProgressEstimate {
  const windowMs = opts.windowMs ?? DEFAULT_WINDOW_MS;
  const staleMs = opts.staleMs ?? DEFAULT_STALE_MS;
  const total = opts.estimatedTotalBytes ?? ESTIMATED_TOTAL_BYTES;

  // Subscribe to the store's progress_percent so component re-renders
  // tick with the percent. The sample buffer lives in a ref so it
  // doesn't trigger renders on every push.
  const storePct = useStatusStore((s) => s.status.progress_percent);

  const samplesRef = useRef<Sample[]>([]);
  const [label, setLabel] = useState<'downloading' | 'waiting'>('downloading');
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let unsub: (() => void) | undefined;
    const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
    if (inTauri) {
      void subscribeProgress((percent) => {
        const now = Date.now();
        const bytes = Math.floor((percent / 100) * total);
        samplesRef.current.push({ t: now, bytes });
        // Drop samples older than windowMs.
        while (samplesRef.current.length > 0 && now - samplesRef.current[0]!.t > windowMs) {
          samplesRef.current.shift();
        }
        setLabel('downloading');
        setTick((x) => x + 1);
      }).then((fn) => {
        unsub = fn;
      });
    }
    return () => {
      unsub?.();
    };
  }, [windowMs, total]);

  // FR-007 — poll for the stale-progress label flip every 500 ms so
  // the worst-case flip happens at staleMs + 500 ms (was staleMs + 1 s
  // before GAP-C / TLA+ tightening).
  useEffect(() => {
    const id = setInterval(() => {
      const samples = samplesRef.current;
      if (samples.length === 0) return;
      const last = samples[samples.length - 1]!;
      const elapsed = Date.now() - last.t;
      if (elapsed >= staleMs) {
        setLabel((current) => (current === 'waiting' ? current : 'waiting'));
      }
    }, STALE_POLL_INTERVAL_MS);
    return () => clearInterval(id);
  }, [staleMs]);

  // Derive the snapshot every render — pure function of the ref state.
  const samples = samplesRef.current;
  const last = samples.length > 0 ? samples[samples.length - 1]! : undefined;
  const lastByteCount = last?.bytes ?? 0;
  const derivedPct = total > 0 ? Math.round((lastByteCount / total) * 100) : 0;
  const lastPct = storePct ?? derivedPct;
  const lastProgressAt = last?.t ?? 0;
  const bps = label === 'waiting' ? 0 : meanBps(samples);
  const remainingBytes = Math.max(0, total - lastByteCount);
  const etaSeconds = bps > 0 ? remainingBytes / bps : null;

  // Mark `tick` as consumed so the linter doesn't complain.
  void tick;

  return {
    lastPct: storePct ?? lastPct,
    lastByteCount,
    totalByteCount: total,
    lastProgressAt,
    bytesPerSecondRecent: bps,
    label,
    etaSeconds,
    etaRendered: formatEta(etaSeconds),
  };
}

/** Swedish byte formatter — thin-space thousands, "MB av Y MB". */
export function formatBytesSwedish(bytes: number, total: number): string {
  const mb = Math.round(bytes / (1024 * 1024));
  const totalMb = Math.round(total / (1024 * 1024));
  return `${formatThousands(mb)} MB av ${formatThousands(totalMb)} MB`;
}

function formatThousands(n: number): string {
  // Swedish thin-space thousands separator (U+202F).
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}
